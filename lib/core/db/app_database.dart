import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../plex/plex_models.dart' show PlexRating;
import 'normalise.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// How the album grid is ordered.
enum AlbumSort { recentlyAdded, title, artist }

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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'plexify'));

  @override
  int get schemaVersion => 8;

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
      ..orderBy([
        (a) => OrderingTerm.desc(a.userRating),
        (a) => OrderingTerm.asc(a.normalisedArtist),
        (a) => OrderingTerm.asc(a.year),
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
  /// Plex leaves `lastViewedAt` null on playlists that have never been played,
  /// and those must sort last rather than first — a null sorting high would put
  /// every unplayed playlist above the ones actually being used.
  Stream<List<Playlist>> watchPlaylists({int? limit}) {
    final query = select(playlists)
      ..orderBy([
        (p) => OrderingTerm(
          expression: p.lastViewedAt,
          mode: OrderingMode.desc,
          nulls: NullsOrder.last,
        ),
        (p) => OrderingTerm.asc(p.normalisedTitle),
      ]);
    if (limit != null) query.limit(limit);
    return query.watch();
  }

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
    });
  }
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
