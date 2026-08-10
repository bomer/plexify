import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../plex/plex_models.dart' show PlexRating;
import 'normalise.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// How the album grid is ordered.
enum AlbumSort { recentlyAdded, title, artist }

/// How the playlist list is ordered.
enum PlaylistSort {
  /// Most recently opened first, which is what the sidebar has always shown.
  recent,

  titleAsc,
  titleDesc,
}

/// The local library cache.
///
/// This is a **cache**, never a second source of truth. Plex remains
/// authoritative; everything here exists so browsing is instant instead of
/// network-bound. The invariant that keeps that honest: reads may consult this
/// database to answer *faster*, but absence from it never means absence from
/// the library. See `docs/PLAN.md`.
@DriftDatabase(
  tables: [
    Artists,
    Albums,
    Tracks,
    Playlists,
    PlaylistItems,
    SyncState,
    PlaybackHistory,
    CatalogReleases,
    CatalogQueries,
    CatalogArtists,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'plexify'));

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // v2 adds ratings and the smart-playlist flag.
      //
      // Migrated rather than recreated deliberately: an existing install has a
      // fully synced library, and dropping it would mean sitting through
      // another full sync for the sake of three nullable columns. The new
      // columns simply start empty and fill on the next delta sync.
      if (from < 2) {
        await m.addColumn(albums, albums.userRating);
        await m.addColumn(tracks, tracks.userRating);
        await m.addColumn(playlists, playlists.smart);
        await m.createIndex(idxAlbumsRating);
      }

      // v3 rewinds the delta cursor, forcing one full pass.
      //
      // The v2 rating columns start empty, and a delta sync cannot fill them:
      // it asks Plex for rows changed since the cursor, and a rating set months
      // ago has not changed since. Without this, an upgraded install would show
      // every album unrated indefinitely and look like the feature was broken.
      //
      // Safe to repeat — every write on the sync path is an upsert, so the pass
      // refreshes rows rather than duplicating them, and it runs in the
      // background while the cache stays fully browsable.
      if (from < 3) {
        await m.database
            .update(syncState)
            .write(const SyncStateCompanion(lastSyncedUpdatedAt: Value(0)));
      }

      // v4 adds the part size the quality policy (#23) derives a source
      // bitrate from.
      //
      // No cursor rewind needed this time, unlike v3: a row left null here
      // degrades safely rather than silently — QualityPolicy treats an
      // unknown source rate as "nothing measured yet" and transcodes as it
      // would have before this column existed, never the reverse. The next
      // sync that touches a track backfills it.
      if (from < 4) {
        await m.addColumn(tracks, tracks.partSizeBytes);
      }

      // v5 gives "jump back in" a column of its own.
      //
      // It read `Albums.lastViewedAt`, which is Plex's and is rewritten by
      // every sync — so an album the server had stamped kept coming back on
      // the shelf no matter what was suppressed locally. Nothing to migrate:
      // the table starts empty and fills from the next thing played.
      if (from < 5) {
        await m.createTable(playbackHistory);
      }

      // v6 gives artists a rating, so the Artists list can filter on
      // favourites the way the album grid already does.
      //
      // Like v4 this does not rewind the sync cursor: an unrated artist and an
      // artist whose rating has not synced yet look the same to the filter,
      // and the next pass that touches the row fills it in. Unlike the v2
      // ratings there is no backfill problem worth a full pass, because an
      // artist rating is rare enough that waiting is not a broken-looking
      // feature.
      if (from < 6) {
        await m.addColumn(artists, artists.userRating);
        await m.createIndex(idxArtistsRating);
      }

      // v7 rewinds the delta cursor so the artist ratings v6 added actually
      // arrive.
      //
      // v6 shipped without this on the reasoning that an unrated artist and
      // one whose rating had not synced look the same to a filter. That was
      // wrong, and wrong in a way already learned once at v3: a delta sync
      // asks Plex for rows changed since the cursor, and an artist rated
      // months ago has not changed since. Without a rewind the filter would
      // have stayed empty indefinitely and looked broken.
      //
      // Its own version rather than folding it into v6, because v6 has
      // already run on installs that took the previous build; editing that
      // branch would never execute for them.
      //
      // Safe to repeat: every sync write is an upsert, so the pass refreshes
      // rows rather than duplicating them, and the cache stays browsable
      // while it runs.
      if (from < 7) {
        await m.database
            .update(syncState)
            .write(const SyncStateCompanion(lastSyncedUpdatedAt: Value(0)));
      }

      // v8 gives the delta sweep somewhere to remember when it last ran.
      //
      // The scheduler held that in memory, so it reset on every launch and a
      // sweep was always due: quitting and reopening ran a full pass every
      // time. Starts null, which reads as "never swept" and sweeps once, which
      // is the same thing a fresh install does.
      if (from < 8) {
        await m.addColumn(syncState, syncState.lastDeltaSweepAt);
      }

      // v9 adds the catalog cache — records that exist, as opposed to records
      // you own.
      //
      // Three new tables and nothing touched, so no cursor rewind and no
      // resync: these are filled by MusicBrainz, not by Plex, and start empty
      // on a fresh install and an upgrade alike. `Albums.mbid` has existed
      // since v1 and is only now written; a row where it is still null falls
      // back to normalised artist and title, which is the path most rows take
      // anyway because Plex records an MBID for very few of them.
      if (from < 9) {
        await m.createTable(catalogReleases);
        await m.createTable(catalogQueries);
        await m.createTable(catalogArtists);
      }
    },
    beforeOpen: (details) async {
      // Off by default in SQLite; without it the playlist and album foreign
      // keys are documentation rather than constraints.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Live view of every cached album.
  ///
  /// Returns a stream rather than a future so the grid repopulates on its own
  /// as sync writes pages in — no manual invalidation, and the library visibly
  /// fills on first run instead of appearing all at once at the end.
  Stream<List<Album>> watchAlbums({
    AlbumSort sort = AlbumSort.recentlyAdded,
    bool favouritesOnly = false,
  }) {
    final query = select(albums);
    if (favouritesOnly) {
      query.where(
        (a) => a.userRating.isBiggerOrEqualValue(PlexRating.favouriteThreshold),
      );
    }
    query.orderBy(switch (sort) {
      AlbumSort.recentlyAdded => [
        (a) => OrderingTerm.desc(a.addedAt),
        (a) => OrderingTerm.asc(a.normalisedTitle),
      ],
      AlbumSort.title => [(a) => OrderingTerm.asc(a.normalisedTitle)],
      AlbumSort.artist => [
        (a) => OrderingTerm.asc(a.normalisedArtist),
        (a) => OrderingTerm.asc(a.year),
        (a) => OrderingTerm.asc(a.normalisedTitle),
      ],
    });
    return query.watch();
  }

  /// Tracks for one album, in disc then track order.
  Stream<List<Track>> watchTracksForAlbum(String albumRatingKey) {
    final query = select(tracks)
      ..where((t) => t.albumRatingKey.equals(albumRatingKey))
      ..orderBy([
        (t) => OrderingTerm.asc(t.discIndex),
        (t) => OrderingTerm.asc(t.trackIndex),
      ]);
    return query.watch();
  }

  /// Favourite albums — four stars or better — best rated first.
  Stream<List<Album>> watchFavouriteAlbums({int? limit}) {
    final query = select(albums)
      ..where(
        (a) => a.userRating.isBiggerOrEqualValue(PlexRating.favouriteThreshold),
      )
      // **Newest first within a rating, not alphabetical.** Most favourites end
      // up at the same four or five stars, so an alphabetical tiebreak makes
      // the row degenerate to whichever artists happen to start with A, for
      // ever. Sorting the tier by when the album arrived means the shelf moves
      // as the library does, and something rated last week is visible without
      // scrolling past two hundred that were not.
      ..orderBy([
        (a) => OrderingTerm.desc(a.userRating),
        (a) => OrderingTerm(
          expression: a.addedAt,
          mode: OrderingMode.desc,
          nulls: NullsOrder.last,
        ),
        // Deterministic where both above tie, so the row does not reshuffle
        // between rebuilds.
        (a) => OrderingTerm.asc(a.normalisedArtist),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  /// Favourite tracks — four stars or better.
  Stream<List<Track>> watchFavouriteTracks({int? limit}) {
    final query = select(tracks)
      ..where(
        (t) => t.userRating.isBiggerOrEqualValue(PlexRating.favouriteThreshold),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.userRating),
        (t) => OrderingTerm.asc(t.artistTitle),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

  /// Applies a rating locally.
  ///
  /// Called before the server request so the star fills instantly; the caller
  /// reverts on failure. A rating that only appears after a network round trip
  /// feels broken, and this is a gesture people repeat quickly.
  Future<void> setAlbumRating(String ratingKey, int? rating) async {
    await (update(albums)..where((a) => a.ratingKey.equals(ratingKey))).write(
      AlbumsCompanion(userRating: Value(rating)),
    );
  }

  /// One track's rating, live.
  ///
  /// Narrower than watching the whole track so a rating sheet does not rebuild
  /// on unrelated writes to the row.
  Stream<int?> watchTrackRating(String ratingKey) {
    final query = select(tracks)..where((t) => t.ratingKey.equals(ratingKey));
    return query.watchSingleOrNull().map((row) => row?.userRating).distinct();
  }

  Future<void> setArtistRating(String ratingKey, int? rating) async {
    await (update(artists)..where((a) => a.ratingKey.equals(ratingKey))).write(
      ArtistsCompanion(userRating: Value(rating)),
    );
  }

  Future<void> setTrackRating(String ratingKey, int? rating) async {
    await (update(tracks)..where((t) => t.ratingKey.equals(ratingKey))).write(
      TracksCompanion(userRating: Value(rating)),
    );
  }

  /// Everything matching [query], from the cache, in one pass per table.
  ///
  /// Matches the normalised columns, which is why they exist and are indexed:
  /// searching "dont look back" finds "Don't Look Back In Anger" without the
  /// caller thinking about apostrophes or case. `normalise` is applied to the
  /// query too, so both sides are folded the same way.
  ///
  /// `contains` rather than `startsWith` because people search for the word
  /// they remember, not the first one. That gives up the index for a table
  /// scan, which is the right trade at this size: a 50k-track library is a few
  /// milliseconds, and the alternative is a full-text index to maintain on
  /// every sync write.
  Future<LibraryMatches> search(String query, {int limit = 20}) async {
    final needle = normalise(query);
    if (needle.isEmpty) return const LibraryMatches.empty();
    final pattern = '%$needle%';

    final artistRows =
        await (select(artists)
              ..where((a) => a.normalisedTitle.like(pattern))
              ..orderBy([(a) => OrderingTerm.asc(a.normalisedTitle)])
              ..limit(limit))
            .get();

    final albumRows =
        await (select(albums)
              ..where(
                (a) =>
                    a.normalisedTitle.like(pattern) |
                    a.normalisedArtist.like(pattern),
              )
              ..orderBy([(a) => OrderingTerm.asc(a.normalisedTitle)])
              ..limit(limit))
            .get();

    final trackRows =
        await (select(tracks)
              ..where((t) => t.normalisedTitle.like(pattern))
              ..orderBy([(t) => OrderingTerm.asc(t.normalisedTitle)])
              ..limit(limit))
            .get();

    return LibraryMatches(
      artists: artistRows,
      albums: albumRows,
      tracks: trackRows,
    );
  }

  /// Artists, alphabetically by normalised name.
  Stream<List<Artist>> watchArtists({bool favouritesOnly = false}) {
    final query = select(artists);
    if (favouritesOnly) {
      query.where(
        (a) => a.userRating.isBiggerOrEqualValue(PlexRating.favouriteThreshold),
      );
    }
    query.orderBy([(a) => OrderingTerm.asc(a.normalisedTitle)]);
    return query.watch();
  }

  /// One artist's albums, oldest first.
  ///
  /// Chronological rather than alphabetical: a discography reads as a timeline,
  /// and albums without a year sort last so they don't head the list.
  Stream<List<Album>> watchAlbumsForArtist(String artistRatingKey) {
    final query = select(albums)
      ..where((a) => a.artistRatingKey.equals(artistRatingKey))
      ..orderBy([
        (a) => OrderingTerm(
          expression: a.year,
          mode: OrderingMode.asc,
          nulls: NullsOrder.last,
        ),
        (a) => OrderingTerm.asc(a.normalisedTitle),
      ]);
    return query.watch();
  }

  /// Every track by an artist, in discography order.
  ///
  /// Joined through albums rather than read off a column on the track: Plex's
  /// `grandparentRatingKey` would be more direct, but adding it would mean a
  /// migration plus a full resync before existing caches had any values. The
  /// join gives the same answer from data already stored.
  ///
  /// Ordered album-chronologically then by disc and track, so it reads as a
  /// discography rather than an arbitrary pile.
  Stream<List<Track>> watchTracksForArtist(String artistRatingKey) {
    final query =
        select(tracks).join([
            innerJoin(
              albums,
              albums.ratingKey.equalsExp(tracks.albumRatingKey),
            ),
          ])
          ..where(albums.artistRatingKey.equals(artistRatingKey))
          ..orderBy([
            OrderingTerm(
              expression: albums.year,
              mode: OrderingMode.asc,
              nulls: NullsOrder.last,
            ),
            OrderingTerm.asc(tracks.discIndex),
            OrderingTerm.asc(tracks.trackIndex),
          ]);

    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(tracks)).toList(),
    );
  }

  /// Playlists, most recently played first.
  ///
  /// **Joined against the local play history, and that join is the whole point
  /// of this being more than three lines.** `Playlists.lastViewedAt` is
  /// *Plex's* column and Plexify never moves it: playback reports
  /// `/:/timeline` and `/:/scrobble` against the **track**, so the server never
  /// learns a playlist was involved, and its own last-viewed stays wherever
  /// Plex web or Plexamp last left it. Every sync then writes that stale value
  /// back over anything stored locally, so there was nowhere to put a local
  /// one even if the write existed.
  ///
  /// The effect was a "Recent playlists" list that never moved however much you
  /// listened, ordered by something no action in this app could change. Exactly
  /// the bug [PlaybackHistory] was introduced to fix for albums at schema v5,
  /// in a second place that never got the same treatment.
  ///
  /// The sort key is therefore the *later* of the two. Local wins when it is
  /// newer, which is the normal case; Plex's fills in for a playlist played
  /// elsewhere and never here, which is why this is a max rather than a
  /// coalesce.
  Stream<List<Playlist>> watchPlaylists({
    int? limit,
    PlaylistSort sort = PlaylistSort.recent,
  }) {
    final query = select(playlists).join([
      leftOuterJoin(
        playbackHistory,
        playbackHistory.ratingKey.equalsExp(playlists.ratingKey) &
            // Albums and playlists share this table and ratingKeys are only
            // unique per type, so without this an album would lend its play
            // time to whichever playlist carried the same key.
            playbackHistory.kind.equals('playlist'),
      ),
    ])..orderBy(_playlistOrder(sort));

    if (limit != null) query.limit(limit);
    return query.watch().map(
      (rows) => [for (final row in rows) row.readTable(playlists)],
    );
  }

  /// The later of "played here" and "viewed on the server", as one number.
  ///
  /// SQLite's two-argument `MAX` is a scalar function rather than the aggregate
  /// drift exposes, so this is written out. The table and column names are the
  /// generated ones and are held to by the tests rather than by the compiler,
  /// which is what reaching past the query builder costs.
  static const _playlistRecency = CustomExpression<int>(
    'MAX(COALESCE(playback_history.started_at, 0), '
    'COALESCE(playlists.last_viewed_at, 0))',
  );

  /// Ordering terms for one [PlaylistSort].
  ///
  /// **Smart playlists come first under either name sort, and not under
  /// recent.** They are the ones that are worth going to on purpose: their
  /// contents change on their own, so "what is in it today" is the question,
  /// where a hand-made playlist is a thing you already know. Alphabetical is
  /// the order you use when you are looking for something specific, which is
  /// exactly when that distinction is worth surfacing. Recent is already an
  /// order of relevance and grouping by kind on top of it would only fight it.
  List<OrderingTerm> _playlistOrder(PlaylistSort sort) => switch (sort) {
    PlaylistSort.recent => [
      // No `nulls last` clause needed any more: the expression coalesces to
      // zero, so a playlist neither played here nor viewed on the server sorts
      // below every one that was, and ties fall through to the title.
      OrderingTerm(expression: _playlistRecency, mode: OrderingMode.desc),
      OrderingTerm.asc(playlists.normalisedTitle),
    ],
    PlaylistSort.titleAsc => [
      OrderingTerm.desc(playlists.smart),
      OrderingTerm.asc(playlists.normalisedTitle),
    ],
    PlaylistSort.titleDesc => [
      // Still descending on `smart`, so the group stays at the top rather than
      // flipping to the bottom with the letters. Reversing the sort means
      // reversing the alphabet, not turning the list upside down.
      OrderingTerm.desc(playlists.smart),
      OrderingTerm.desc(playlists.normalisedTitle),
    ],
  };

  /// Albums this device started playing, newest first.
  ///
  /// Driven by [PlaybackHistory] rather than `Albums.lastViewedAt`, which is
  /// Plex's column: it is rewritten by every sync, so an album the server had
  /// stamped kept reappearing on the shelf, and it only moves at the 90%
  /// scrobble mark, so a short listen recorded nothing at all.
  ///
  /// Returned with the time started, because the shelf merges these with
  /// playlists and needs one clock to sort both on.
  Stream<List<(Album, int)>> watchRecentlyPlayedAlbums({int limit = 20}) {
    final query =
        select(playbackHistory).join([
            innerJoin(
              albums,
              albums.ratingKey.equalsExp(playbackHistory.ratingKey),
            ),
          ])
          ..where(playbackHistory.kind.equals('album'))
          ..orderBy([OrderingTerm.desc(playbackHistory.startedAt)])
          ..limit(limit);

    return query.watch().map(
      (rows) => [
        for (final row in rows)
          (row.readTable(albums), row.readTable(playbackHistory).startedAt),
      ],
    );
  }

  /// Playlists this device started playing, newest first.
  ///
  /// Unlike [watchPlaylists], which lists everything for the sidebar, this
  /// shows only what was actually put on — "Jump back in" is about what you
  /// did, not what exists.
  Stream<List<(Playlist, int)>> watchRecentlyPlayedPlaylists({int limit = 20}) {
    final query =
        select(playbackHistory).join([
            innerJoin(
              playlists,
              playlists.ratingKey.equalsExp(playbackHistory.ratingKey),
            ),
          ])
          ..where(playbackHistory.kind.equals('playlist'))
          ..orderBy([OrderingTerm.desc(playbackHistory.startedAt)])
          ..limit(limit);

    return query.watch().map(
      (rows) => [
        for (final row in rows)
          (row.readTable(playlists), row.readTable(playbackHistory).startedAt),
      ],
    );
  }

  /// Albums most recently added, for the Home screen.
  Stream<List<Album>> watchRecentlyAddedAlbums({int limit = 20}) {
    final query = select(albums)
      ..orderBy([(a) => OrderingTerm.desc(a.addedAt)])
      ..limit(limit);
    return query.watch();
  }

  /// Albums nothing has ever played, oldest first.
  ///
  /// Two sources of "played", and both are needed. Plex's `lastViewedAt` covers
  /// every other client and everything before this app existed; the local
  /// history table covers this app, which deliberately does not write
  /// `lastViewedAt` (see [PlaybackHistory]). Checking only one would call an
  /// album buried the day after it was listened to.
  ///
  /// [addedBefore] keeps this week's arrivals out of it. They have their own
  /// shelf, and an album that showed up on Tuesday is not buried treasure.
  ///
  /// Oldest first, and deliberately more rows than any shelf shows: the caller
  /// shuffles the result, so the limit is the pool to draw from rather than the
  /// row itself.
  Stream<List<Album>> watchNeverPlayedAlbums({
    int? addedBefore,
    int limit = 300,
  }) {
    final played = selectOnly(playbackHistory)
      ..addColumns([playbackHistory.ratingKey])
      ..where(playbackHistory.kind.equals('album'));

    final query = select(albums)
      ..where((a) {
        var where = a.lastViewedAt.isNull() & a.ratingKey.isNotInQuery(played);
        if (addedBefore != null) {
          // Nulls kept: an album with no addedAt at all is old enough by any
          // reading, and dropping it would quietly shrink the pool on
          // libraries scanned by older agents.
          where =
              where &
              (a.addedAt.isNull() | a.addedAt.isSmallerThanValue(addedBefore));
        }
        return where;
      })
      ..orderBy([(a) => OrderingTerm.asc(a.addedAt)])
      ..limit(limit);
    return query.watch();
  }

  /// Which album each of these tracks belongs to.
  ///
  /// **Plex's play history does not say.** Its rows carry the track's own
  /// ratingKey and, measured against James's server on 10 August 2026, no
  /// `parentRatingKey` at all: 43 plays in a month resolved to zero albums.
  /// The cache already holds the link for every track it has synced, so the
  /// answer is here rather than in another request.
  ///
  /// Tracks the cache has never seen are absent from the result rather than
  /// mapped to null, so a caller iterating the map only ever sees links that
  /// exist.
  Future<Map<String, String>> albumKeysForTracks(
    Iterable<String> trackRatingKeys,
  ) async {
    final keys = trackRatingKeys.toList();
    if (keys.isEmpty) return const {};

    final rows =
        await (selectOnly(tracks)
              ..addColumns([tracks.ratingKey, tracks.albumRatingKey])
              ..where(tracks.ratingKey.isIn(keys)))
            .get();

    return {
      for (final row in rows)
        row.read(tracks.ratingKey)!: ?row.read(tracks.albumRatingKey),
    };
  }

  /// Albums by ratingKey, for joining a server-side result back to local rows.
  ///
  /// The play-history shelf gets counts from Plex and everything else from
  /// here: titles, artists, artwork. Anything the cache does not hold is
  /// absent from the result rather than an error, which is also how an album
  /// deleted since it was played drops out of the row on its own.
  Future<List<Album>> albumsByKeys(Iterable<String> ratingKeys) {
    final keys = ratingKeys.toList();
    if (keys.isEmpty) return Future.value(const []);
    return (select(albums)..where((a) => a.ratingKey.isIn(keys))).get();
  }

  /// Tracks in a playlist, in stored playlist order.
  Stream<List<Track>> watchPlaylistTracks(String playlistRatingKey) {
    final query =
        select(playlistItems).join([
            innerJoin(
              tracks,
              tracks.ratingKey.equalsExp(playlistItems.trackRatingKey),
            ),
          ])
          ..where(playlistItems.playlistRatingKey.equals(playlistRatingKey))
          ..orderBy([OrderingTerm.asc(playlistItems.position)]);

    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(tracks)).toList(),
    );
  }

  /// Replaces a playlist's contents.
  ///
  /// Delete-then-insert rather than upsert: playlists are reordered and have
  /// items removed, so a merge would leave stale positions behind.
  Future<void> replacePlaylistItems(
    String playlistRatingKey,
    List<PlaylistItemsCompanion> items,
  ) async {
    await transaction(() async {
      await (delete(
        playlistItems,
      )..where((i) => i.playlistRatingKey.equals(playlistRatingKey))).go();
      await batch((batch) => batch.insertAll(playlistItems, items));
    });
  }

  /// Rewinds the delta cursor so the next sync walks the whole library.
  ///
  /// The escape hatch for when the cache and Plex have diverged in a way the
  /// incremental path cannot reconcile — every write on the sync path is an
  /// upsert, so this refreshes rows rather than duplicating them, and nothing
  /// is dropped in the meantime.
  Future<void> rewindSyncCursor() async {
    await update(
      syncState,
    ).write(const SyncStateCompanion(lastSyncedUpdatedAt: Value(0)));
  }

  /// When the delta sweep last completed, or null if it never has.
  ///
  /// One row per section and only ever one section, so the earliest non-null
  /// value is the answer. Null means sweep now.
  Future<DateTime?> lastDeltaSweepAt() async {
    final rows = await select(syncState).get();
    final stamps = rows
        .map((r) => r.lastDeltaSweepAt)
        .whereType<int>()
        .toList();
    if (stamps.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      stamps.reduce((a, b) => a > b ? a : b),
    );
  }

  Future<void> markDeltaSweep(DateTime at) async {
    await update(syncState).write(
      SyncStateCompanion(lastDeltaSweepAt: Value(at.millisecondsSinceEpoch)),
    );
  }

  /// Every album, reduced to the three fields catalog matching needs.
  ///
  /// A projection rather than `select(albums)` because this is rebuilt into a
  /// set of keys on every album write, and during a first sync that is
  /// thousands of times — reading twelve columns to use three would put the
  /// whole row through the isolate boundary for nothing.
  ///
  /// A stream rather than a future so "albums I am missing" corrects itself the
  /// moment a download lands and syncs, which is the one time anybody is
  /// watching that list closely.
  Stream<List<AlbumIdentity>> watchAlbumIdentities() {
    final query = selectOnly(albums)
      ..addColumns([albums.mbid, albums.artistTitle, albums.title]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          AlbumIdentity(
            mbid: row.read(albums.mbid),
            artist: row.read(albums.artistTitle) ?? '',
            title: row.read(albums.title) ?? '',
          ),
      ],
    );
  }

  /// The same, for one artist. Used by the artist page, which only ever
  /// compares a discography against that artist's own albums.
  Future<List<AlbumIdentity>> albumIdentitiesForArtist(
    String artistRatingKey,
  ) async {
    final query = selectOnly(albums)
      ..addColumns([albums.mbid, albums.artistTitle, albums.title])
      ..where(albums.artistRatingKey.equals(artistRatingKey));
    final rows = await query.get();
    return [
      for (final row in rows)
        AlbumIdentity(
          mbid: row.read(albums.mbid),
          artist: row.read(albums.artistTitle) ?? '',
          title: row.read(albums.title) ?? '',
        ),
    ];
  }

  Future<int> countCatalogReleases() async {
    final count = catalogReleases.mbid.count();
    final row = await (selectOnly(
      catalogReleases,
    )..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  /// Drops everything MusicBrainz told us.
  ///
  /// Not called by sign-out — MBIDs are global and mean the same thing on any
  /// server, so unlike the library cache there is nothing here that could
  /// collide. It exists for the settings screen, so a discography that resolved
  /// to the wrong artist can be thrown away and asked again.
  Future<void> clearCatalog() async {
    await transaction(() async {
      await delete(catalogQueries).go();
      await delete(catalogReleases).go();
      await delete(catalogArtists).go();
    });
  }

  Future<int> countArtists() async {
    final count = artists.ratingKey.count();
    final row = await (selectOnly(artists)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> countPlaylists() async {
    final count = playlists.ratingKey.count();
    final row = await (selectOnly(playlists)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> countRatedAlbums() async {
    final count = albums.ratingKey.count();
    final row =
        await (selectOnly(albums)
              ..addColumns([count])
              ..where(albums.userRating.isNotNull()))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> countAlbums() async {
    final count = albums.ratingKey.count();
    final row = await (selectOnly(albums)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> countTracks() async {
    final count = tracks.ratingKey.count();
    final row = await (selectOnly(tracks)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  /// Drops every cached row.
  ///
  /// Used when the connected server changes: Plex ratingKeys are unique only
  /// within a server, so keeping rows from a previous one would silently blend
  /// two libraries together.
  Future<void> clearLibrary() async {
    await transaction(() async {
      await delete(playlistItems).go();
      await delete(playlists).go();
      await delete(tracks).go();
      await delete(albums).go();
      await delete(artists).go();
      await delete(syncState).go();
      // Deliberately not the catalog tables. MBIDs are global, so unlike
      // ratingKeys there is nothing here that could collide with another
      // server — and a test asserts they survive, because adding them looks
      // tidy and nothing else would notice.
    });
  }
}

/// An album stripped to what deciding "do I already own this?" needs.
///
/// A named type rather than a record, because it crosses from the database into
/// the catalog matcher and back through a provider — and three unlabelled
/// strings in a row is exactly the shape that gets silently transposed.
class AlbumIdentity {
  const AlbumIdentity({
    required this.mbid,
    required this.artist,
    required this.title,
  });

  final String? mbid;
  final String artist;
  final String title;
}

/// What the cache had for a query.
///
/// Three lists rather than one ranked list: the sections are meaningful to
/// look at, and an artist is not competing with a track for the same slot.
class LibraryMatches {
  const LibraryMatches({
    required this.artists,
    required this.albums,
    required this.tracks,
  });

  const LibraryMatches.empty()
    : artists = const [],
      albums = const [],
      tracks = const [];

  final List<Artist> artists;
  final List<Album> albums;
  final List<Track> tracks;

  bool get isEmpty => artists.isEmpty && albums.isEmpty && tracks.isEmpty;
}
