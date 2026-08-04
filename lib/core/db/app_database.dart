import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../plex/plex_models.dart' show PlexRating;
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
  tables: [Artists, Albums, Tracks, Playlists, PlaylistItems, SyncState],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'plexify'));

  @override
  int get schemaVersion => 3;

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

  Future<void> setTrackRating(String ratingKey, int? rating) async {
    await (update(tracks)..where((t) => t.ratingKey.equals(ratingKey))).write(
      TracksCompanion(userRating: Value(rating)),
    );
  }

  /// Artists, alphabetically by normalised name.
  Stream<List<Artist>> watchArtists() {
    final query = select(artists)
      ..orderBy([(a) => OrderingTerm.asc(a.normalisedTitle)]);
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

  /// Albums most recently played, for the Home screen.
  Stream<List<Album>> watchRecentlyPlayedAlbums({int limit = 20}) {
    final query = select(albums)
      ..where((a) => a.lastViewedAt.isNotNull())
      ..orderBy([(a) => OrderingTerm.desc(a.lastViewedAt)])
      ..limit(limit);
    return query.watch();
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
