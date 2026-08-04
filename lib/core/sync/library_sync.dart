import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../plex/plex_client.dart';
import '../plex/plex_models.dart';
import 'library_writer.dart';

/// Which pass the sync is currently on.
enum SyncPhase { idle, artists, albums, tracks, done, failed }

/// Progress snapshot for the UI.
class SyncProgress {
  const SyncProgress({
    required this.phase,
    this.done = 0,
    this.total = 0,
    this.message,
  });

  final SyncPhase phase;
  final int done;
  final int total;
  final String? message;

  /// Null while the total is unknown, so the UI can show an indeterminate bar
  /// rather than a bogus 0%.
  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);

  bool get isFinished => phase == SyncPhase.done || phase == SyncPhase.failed;
}

/// Fills the local cache from Plex.
///
/// Pulls artists, albums and tracks in three paginated passes, writing each
/// page in a transaction so an interrupted run leaves a consistent — if
/// partial — database that the next run resumes rather than restarts.
///
/// Tracks are fetched at the **section** level rather than per album. On a
/// 50k-track library the per-album approach would mean thousands of round
/// trips; this is a few hundred.
class LibrarySync {
  LibrarySync({
    required PlexClient client,
    required AppDatabase db,
    this.pageSize = 200,
  }) : _client = client,
       _db = db,
       _writer = LibraryWriter(db);

  final PlexClient _client;
  final AppDatabase _db;
  final LibraryWriter _writer;
  final int pageSize;

  /// Runs a full pass over the section.
  ///
  /// [minUpdatedAt] turns this into a delta sync: pass the last stored value to
  /// fetch only what changed. Zero (the default) syncs everything.
  Stream<SyncProgress> run(
    PlexSection section, {
    required String serverClientIdentifier,
    int minUpdatedAt = 0,
  }) async* {
    try {
      // Plex ratingKeys are unique only within a server. If the cache belongs
      // to a different one, keeping it would blend two libraries into a single
      // incoherent view.
      final reset = await _resetIfServerChanged(serverClientIdentifier);
      final effectiveMin = reset ? 0 : minUpdatedAt;

      var newestUpdatedAt = effectiveMin;

      // Note `await for` rather than `yield*`. In an async* function, `yield*`
      // forwards an inner stream's errors straight to subscribers without
      // passing through the enclosing try/catch — so a mid-sync HTTP failure
      // would escape as an unhandled stream error instead of becoming a
      // SyncPhase.failed event. `await for` throws into this body, which is
      // what the error handling below depends on.
      await for (final p in _pass<PlexArtist>(
        section: section,
        phase: SyncPhase.artists,
        type: PlexClient.typeArtist,
        parse: PlexArtist.fromJson,
        minUpdatedAt: effectiveMin,
        write: _writer.writeArtists,
        newest: (items) => items.map((a) => a.updatedAt ?? 0),
        onNewest: (v) => newestUpdatedAt = _max(newestUpdatedAt, v),
      )) {
        yield p;
      }

      await for (final p in _pass<PlexAlbum>(
        section: section,
        phase: SyncPhase.albums,
        type: PlexClient.typeAlbum,
        parse: PlexAlbum.fromJson,
        minUpdatedAt: effectiveMin,
        write: _writer.writeAlbums,
        newest: (items) => items.map((a) => a.updatedAt ?? 0),
        onNewest: (v) => newestUpdatedAt = _max(newestUpdatedAt, v),
      )) {
        yield p;
      }

      await for (final p in _pass<PlexTrack>(
        section: section,
        phase: SyncPhase.tracks,
        type: PlexClient.typeTrack,
        parse: PlexTrack.fromJson,
        minUpdatedAt: effectiveMin,
        write: _writer.writeTracks,
        newest: (items) => items.map((t) => t.updatedAt ?? 0),
        onNewest: (v) => newestUpdatedAt = _max(newestUpdatedAt, v),
      )) {
        yield p;
      }

      // Playlists come from /playlists, not the section walk, so they are a
      // separate pass. Only the list is synced here — items are fetched lazily
      // when a playlist is opened, since syncing every item up front would mean
      // one request per playlist for data most of which is never looked at.
      await _syncPlaylists();

      await _markComplete(
        section: section,
        serverClientIdentifier: serverClientIdentifier,
        newestUpdatedAt: newestUpdatedAt,
      );

      yield const SyncProgress(phase: SyncPhase.done);
    } on Object catch (e) {
      // A failed sync must not poison the cache. Whatever landed stays, and
      // initialSyncComplete remains false so the next run resumes.
      yield SyncProgress(phase: SyncPhase.failed, message: '$e');
    }
  }

  /// One paginated pass over a metadata type.
  Stream<SyncProgress> _pass<T>({
    required PlexSection section,
    required SyncPhase phase,
    required int type,
    required T Function(Map<String, dynamic>) parse,
    required int minUpdatedAt,
    required Future<void> Function(List<T>) write,
    required Iterable<int> Function(List<T>) newest,
    required void Function(int) onNewest,
  }) async* {
    var start = 0;
    var total = 0;

    while (true) {
      final page = await _client.sectionPage<T>(
        section.key,
        type: type,
        parse: parse,
        start: start,
        size: pageSize,
        minUpdatedAt: minUpdatedAt,
      );

      if (page.items.isEmpty) break;

      await write(page.items);
      for (final value in newest(page.items)) {
        onNewest(value);
      }

      start += page.items.length;
      total = page.totalSize > 0 ? page.totalSize : start;

      yield SyncProgress(phase: phase, done: start, total: total);

      // A short page means the server has nothing more, which is a more
      // reliable stop condition than trusting totalSize alone — that can shift
      // mid-sync if someone adds music while we run.
      if (page.items.length < pageSize) break;
      if (start >= total && page.totalSize > 0) break;
    }
  }

  /// Refreshes the playlist list.
  ///
  /// Failures are swallowed: playlists are a sidebar convenience, and losing
  /// them should not fail a library sync that otherwise succeeded.
  Future<void> _syncPlaylists() async {
    try {
      await _writer.writePlaylists(await _client.playlists());
    } on Object {
      // Non-fatal; the rest of the sync stands.
    }
  }

  /// Wipes the cache if it was built against a different server.
  ///
  /// Returns true if a reset happened, in which case the caller must ignore any
  /// stored delta cursor — it refers to a library that is no longer ours.
  Future<bool> _resetIfServerChanged(String serverClientIdentifier) async {
    final existing = await _db.select(_db.syncState).get();
    if (existing.isEmpty) return false;

    final differs = existing.any(
      (row) => row.serverClientIdentifier != serverClientIdentifier,
    );
    if (differs) {
      await _db.clearLibrary();
    }
    return differs;
  }

  Future<void> _markComplete({
    required PlexSection section,
    required String serverClientIdentifier,
    required int newestUpdatedAt,
  }) async {
    await _db
        .into(_db.syncState)
        .insertOnConflictUpdate(
          SyncStateCompanion.insert(
            sectionKey: section.key,
            serverClientIdentifier: serverClientIdentifier,
            lastSyncedUpdatedAt: Value(newestUpdatedAt),
            serverUpdatedAt: Value(section.updatedAt),
            serverScannedAt: Value(section.scannedAt),
            initialSyncComplete: const Value(true),
          ),
        );
  }

  static int _max(int a, int b) => a > b ? a : b;
}
