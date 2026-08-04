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
