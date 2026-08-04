import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
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
  Stream<List<Album>> watchAlbums({AlbumSort sort = AlbumSort.recentlyAdded}) {
    final query = select(albums)
      ..orderBy(switch (sort) {
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
