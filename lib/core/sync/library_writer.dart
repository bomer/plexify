import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/normalise.dart';
import '../audio/playback_source.dart';
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
            userRating: Value(a.userRating),
          ),
        ),
      );
    });
  }

  Future<void> writeAlbums(List<PlexAlbum> items) async {
    if (items.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.albums, items.map(_albumRow));
    });
  }

  /// Inserts an album only if the cache has never seen it.
  ///
  /// For paths that need a row to exist before writing to it — rating, most
  /// importantly. Those updates are `UPDATE ... WHERE ratingKey = ?`, which
  /// matches nothing for an album the sync has not reached yet and fails
  /// silently rather than loudly.
  ///
  /// Insert-or-ignore rather than upsert: a row already here came from a full
  /// listing and is richer than whatever partial object prompted this, so it
  /// must not be overwritten.
  Future<void> ensureAlbum(PlexAlbum album) async {
    await _db
        .into(_db.albums)
        .insert(_albumRow(album), mode: InsertMode.insertOrIgnore);
  }

  /// Inserts an artist only if the cache has never seen it. See [ensureAlbum].
  Future<void> ensureArtist(PlexArtist artist) async {
    await _db
        .into(_db.artists)
        .insert(
          ArtistsCompanion.insert(
            ratingKey: artist.ratingKey,
            title: artist.title,
            normalisedTitle: normalise(artist.title),
            thumb: Value(artist.thumb),
            updatedAt: Value(artist.updatedAt),
            addedAt: Value(artist.addedAt),
            userRating: Value(artist.userRating),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Inserts a track only if the cache has never seen it. See [ensureAlbum].
  Future<void> ensureTrack(PlexTrack track) async {
    await _db
        .into(_db.tracks)
        .insert(_trackRow(track), mode: InsertMode.insertOrIgnore);
  }

  AlbumsCompanion _albumRow(PlexAlbum a) => AlbumsCompanion.insert(
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
  );

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
        items.map((t) => _trackRow(t, fallbackAlbumRatingKey)),
      );
    });
  }

  TracksCompanion _trackRow(PlexTrack t, [String? fallbackAlbumRatingKey]) =>
      TracksCompanion.insert(
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
        partSizeBytes: Value(t.partSizeBytes),
        thumb: Value(t.thumb),
        updatedAt: Value(t.updatedAt),
        addedAt: Value(t.addedAt),
        lastViewedAt: Value(t.lastViewedAt),
        userRating: Value(t.userRating),
      );

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

  /// Records locally that a track was played, and its album with it.
  ///
  /// Plex is told separately, but waiting for that to come back around through
  /// a sync would leave Home's "Jump back in" showing yesterday's listening for
  /// up to five minutes after a play. Writing both ends keeps the shelf honest
  /// immediately; the next sweep simply agrees with it.
  ///
  /// Plex stores these as epoch **seconds**, so the same unit is used here —
  /// milliseconds would sort correctly among themselves and wrongly against
  /// every row the sync wrote.
  /// These mirror what Plex records, so they stay Plex-shaped: the track and
  /// its album, at the scrobble mark. What the shelf reads is
  /// [markStarted], which is a different question with a different answer.
  Future<void> markPlayed(String trackRatingKey, DateTime at) async {
    final seconds = at.millisecondsSinceEpoch ~/ 1000;

    await _db.transaction(() async {
      await (_db.update(_db.tracks)
            ..where((t) => t.ratingKey.equals(trackRatingKey)))
          .write(TracksCompanion(lastViewedAt: Value(seconds)));

      final albumKey =
          await (_db.selectOnly(_db.tracks)
                ..addColumns([_db.tracks.albumRatingKey])
                ..where(_db.tracks.ratingKey.equals(trackRatingKey)))
              .map((row) => row.read(_db.tracks.albumRatingKey))
              .getSingleOrNull();

      if (albumKey != null) {
        await (_db.update(_db.albums)
              ..where((a) => a.ratingKey.equals(albumKey)))
            .write(AlbumsCompanion(lastViewedAt: Value(seconds)));
      }
    });
  }

  /// Records that [source] was *started*, which is what "Jump back in" means.
  ///
  /// Two things this does that stamping `lastViewedAt` could not. It happens
  /// when playback begins rather than at the 90% scrobble mark, so putting
  /// something on and leaving after two minutes still counts — the old
  /// behaviour recorded nothing at all, which is why the shelf sat on an album
  /// from half an hour earlier. And it writes a table no sync touches, so an
  /// album Plex stamped server-side can no longer reappear over the top of it.
  ///
  /// Upserted on the primary key, so putting the same album on twice moves it
  /// up the shelf rather than listing it twice.
  Future<void> markStarted(PlaybackSource source, DateTime at) async {
    await _db
        .into(_db.playbackHistory)
        .insertOnConflictUpdate(
          PlaybackHistoryCompanion.insert(
            kind: source.kind.name,
            ratingKey: source.ratingKey,
            startedAt: at.millisecondsSinceEpoch ~/ 1000,
          ),
        );
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
      final albumKeys =
          await (_db.selectOnly(_db.albums)
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
