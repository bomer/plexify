import 'dart:async';

import '../db/app_database.dart';
import '../plex/plex_client.dart';
import '../plex/plex_models.dart';
import '../plex/plex_notifications.dart';
import 'library_writer.dart';

/// Applies Plex's push notifications to the local cache.
///
/// This is what makes newly added music appear without a refresh: Plex emits a
/// timeline entry the moment it finishes scanning an item, this fetches that one
/// item and writes it, and the drift streams the UI is watching repaint on their
/// own. No invalidation, no polling, no user gesture.
///
/// Changes are applied one at a time. They arrive in ones and twos even during a
/// large import — Plex reports each item as it finishes — so the ordering
/// guarantee is worth more than the concurrency.
class LiveSync {
  LiveSync({
    required PlexClient client,
    required AppDatabase db,
    required Stream<PlexLibraryChange> changes,
  }) : _client = client,
       _changes = changes,
       _writer = LibraryWriter(db),
       _db = db;

  final PlexClient _client;
  final AppDatabase _db;
  final LibraryWriter _writer;
  final Stream<PlexLibraryChange> _changes;

  StreamSubscription<PlexLibraryChange>? _subscription;

  /// Serialises applications so two notifications for the same album cannot
  /// interleave their fetches and writes.
  Future<void> _queue = Future.value();

  /// Counts changes actually written. Exposed for tests and diagnostics.
  int get applied => _applied;
  int _applied = 0;

  void start() {
    _subscription ??= _changes.listen((change) {
      _queue = _queue.then((_) => _apply(change));
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _queue;
  }

  /// Waits for everything received so far to finish being written.
  ///
  /// Only useful to tests — nothing in the app awaits this work, by design.
  Future<void> settle() => _queue;

  Future<void> _apply(PlexLibraryChange change) async {
    try {
      if (change.kind == PlexChangeKind.deleted) {
        await _writer.deleteItem(change.ratingKey);
        _applied++;
        return;
      }

      // Playlists are cheap to refresh wholesale and their notifications don't
      // identify what changed inside them, so one call replaces the lot.
      if (change.metadataType == PlexMetadataType.playlist) {
        await _writer.writePlaylists(await _client.playlists());
        _applied++;
        return;
      }

      final json = await _client.metadataItem(change.ratingKey);
      if (json == null) {
        // The item vanished between the notification and the fetch. Plex
        // already considers it gone, so the cache should too.
        await _writer.deleteItem(change.ratingKey);
        _applied++;
        return;
      }

      final type = change.metadataType ?? _typeFromJson(json);
      switch (type) {
        case PlexMetadataType.artist:
          await _writer.writeArtists([PlexArtist.fromJson(json)]);
        case PlexMetadataType.album:
          final album = PlexAlbum.fromJson(json);
          await _writer.writeAlbums([album]);
          await _ensureArtist(album.artistRatingKey);
        case PlexMetadataType.track:
          final track = PlexTrack.fromJson(json);
          await _writer.writeTracks([track]);
          await _ensureAlbum(track.albumRatingKey);
        default:
          // Some other library type — a photo, a film. Not ours.
          return;
      }
      _applied++;
    } on Object {
      // A change that fails to apply is dropped rather than retried. The cost
      // is bounded: the item keeps its old `updatedAt`, so the next delta sync
      // picks it up anyway. Retrying here would risk hammering a server that is
      // already unhappy.
    }
  }

  /// Fetches a track's album if the cache has never seen it.
  ///
  /// Without this a track pushed before its album — which happens routinely, as
  /// Plex finishes scanning individual files first — would be stored with a
  /// parent that does not exist locally, and the artist page joins through
  /// albums, so the track would simply not appear.
  Future<void> _ensureAlbum(String? albumRatingKey) async {
    if (albumRatingKey == null) return;
    final existing = await (_db.select(
      _db.albums,
    )..where((a) => a.ratingKey.equals(albumRatingKey))).getSingleOrNull();
    if (existing != null) return;

    final json = await _client.metadataItem(albumRatingKey);
    if (json == null) return;
    final album = PlexAlbum.fromJson(json);
    await _writer.writeAlbums([album]);
    await _ensureArtist(album.artistRatingKey);
  }

  Future<void> _ensureArtist(String? artistRatingKey) async {
    if (artistRatingKey == null) return;
    final existing = await (_db.select(
      _db.artists,
    )..where((a) => a.ratingKey.equals(artistRatingKey))).getSingleOrNull();
    if (existing != null) return;

    final json = await _client.metadataItem(artistRatingKey);
    if (json == null) return;
    await _writer.writeArtists([PlexArtist.fromJson(json)]);
  }

  /// Falls back to the textual `type` when the notification omitted the number.
  static int? _typeFromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'artist' => PlexMetadataType.artist,
      'album' => PlexMetadataType.album,
      'track' => PlexMetadataType.track,
      'playlist' => PlexMetadataType.playlist,
      _ => null,
    };
  }
}
