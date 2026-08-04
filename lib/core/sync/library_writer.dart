import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/normalise.dart';
import '../plex/plex_models.dart';

/// Writes Plex models into the local cache.
///
/// Every path that stores library data goes through here — the bulk sync, the
/// push-notification sync, and the revalidation that happens when a screen
/// opens. Keeping one copy matters because the mapping is the awkward part: a
/// field added to a table has to reach all three, and three hand-maintained
/// copies is how a column ends up populated on one path and null on another.
///
/// All writes are upserts. The cache is additive by design, so a partial row
/// arriving from a lighter endpoint should update what it knows and leave the
/// rest alone rather than being rejected.
class LibraryWriter {
  const LibraryWriter(this._db);

  final AppDatabase _db;

  Future<void> writeArtists(List<PlexArtist> items) async {
    if (items.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _db.artists,
        items.map(
          (a) => ArtistsCompanion.insert(
            ratingKey: a.ratingKey,
            title: a.title,
            normalisedTitle: normalise(a.title),
            thumb: Value(a.thumb),
            updatedAt: Value(a.updatedAt),
            addedAt: Value(a.addedAt),
          ),
        ),
      );
    });
  }

  Future<void> writeAlbums(List<PlexAlbum> items) async {
    if (items.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _db.albums,
        items.map(
          (a) => AlbumsCompanion.insert(
            ratingKey: a.ratingKey,
            title: a.title,
            normalisedTitle: normalise(a.title),
            artistRatingKey: Value(a.artistRatingKey),
            artistTitle: a.artist,
            normalisedArtist: normalise(a.artist),
            thumb: Value(a.thumb),
            year: Value(a.year),
            updatedAt: Value(a.updatedAt),
            addedAt: Value(a.addedAt),
            lastViewedAt: Value(a.lastViewedAt),
            userRating: Value(a.userRating),
          ),
        ),
      );
    });
  }

  /// Stores tracks.
  ///
  /// [fallbackAlbumRatingKey] fills in the album link for endpoints that omit
  /// `parentRatingKey` — notably `/library/metadata/{album}/children`, where the
  /// parent is implied by the request rather than repeated in each row. Without
  /// it those tracks land unlinked and disappear from the album they came from.
  Future<void> writeTracks(
    List<PlexTrack> items, {
    String? fallbackAlbumRatingKey,
  }) async {
    if (items.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _db.tracks,
        items.map(
          (t) => TracksCompanion.insert(
            ratingKey: t.ratingKey,
            title: t.title,
            normalisedTitle: normalise(t.title),
            albumRatingKey: Value(t.albumRatingKey ?? fallbackAlbumRatingKey),
            albumTitle: Value(t.album),
            artistTitle: Value(t.artist),
            trackIndex: Value(t.index),
            discIndex: Value(t.discIndex),
            durationMs: Value(t.durationMs),
            partKey: Value(t.partKey),
            container: Value(t.container),
            thumb: Value(t.thumb),
            updatedAt: Value(t.updatedAt),
            addedAt: Value(t.addedAt),
            lastViewedAt: Value(t.lastViewedAt),
            userRating: Value(t.userRating),
          ),
        ),
      );
    });
  }

  Future<void> writePlaylists(List<PlexPlaylist> items) async {
    if (items.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _db.playlists,
        items.map(
          (p) => PlaylistsCompanion.insert(
            ratingKey: p.ratingKey,
            title: p.title,
            normalisedTitle: normalise(p.title),
            thumb: Value(p.thumb),
            itemCount: Value(p.itemCount),
            durationMs: Value(p.durationMs),
            updatedAt: Value(p.updatedAt),
            lastViewedAt: Value(p.lastViewedAt),
            smart: Value(p.smart),
          ),
        ),
      );
    });
  }

  /// Removes an item and anything beneath it.
  ///
  /// The ratingKey could name any kind of item, so all four tables are tried —
  /// the notification that prompted this does not always say which.
  ///
  /// Children are removed explicitly. Plex usually sends a delete for each
  /// affected item, but not reliably, and the tables carry no foreign keys to
  /// cascade for us. An album deleted without its tracks would leave rows that
  /// still appear in artist listings and then 404 on play — worse than being
  /// absent, because it looks like a broken player rather than a deleted album.
  Future<void> deleteItem(String ratingKey) async {
    await _db.transaction(() async {
      final albumKeys = await (_db.selectOnly(_db.albums)
            ..addColumns([_db.albums.ratingKey])
            ..where(_db.albums.artistRatingKey.equals(ratingKey)))
          .map((row) => row.read(_db.albums.ratingKey)!)
          .get();

      for (final albumKey in [ratingKey, ...albumKeys]) {
        await (_db.delete(
          _db.tracks,
        )..where((t) => t.albumRatingKey.equals(albumKey))).go();
      }

      await (_db.delete(
        _db.albums,
      )..where((a) => a.artistRatingKey.equals(ratingKey))).go();

      await (_db.delete(
        _db.tracks,
      )..where((t) => t.ratingKey.equals(ratingKey))).go();
      await (_db.delete(
        _db.albums,
      )..where((a) => a.ratingKey.equals(ratingKey))).go();
      await (_db.delete(
        _db.artists,
      )..where((a) => a.ratingKey.equals(ratingKey))).go();

      await (_db.delete(
        _db.playlistItems,
      )..where((i) => i.playlistRatingKey.equals(ratingKey))).go();
      await (_db.delete(
        _db.playlistItems,
      )..where((i) => i.trackRatingKey.equals(ratingKey))).go();
      await (_db.delete(
        _db.playlists,
      )..where((p) => p.ratingKey.equals(ratingKey))).go();
    });
  }
}
