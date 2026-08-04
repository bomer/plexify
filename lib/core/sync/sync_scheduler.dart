import 'dart:async';

import '../db/app_database.dart';
import '../plex/plex_client.dart';
import '../plex/plex_models.dart';
import 'library_sync.dart';

/// Decides when to sync, and runs it.
///
/// The cheap tier of the sync design. `/library/sections` returns `updatedAt`
/// and `scannedAt` per section in one small response, so asking "has anything
/// changed?" costs almost nothing and can be asked often. Only when the answer
/// is yes does a delta sync follow.
///
/// This is the safety net beneath the notification socket rather than a
/// replacement for it: the socket is faster, but it cannot deliver what
/// happened while the app was closed, and it is the piece most likely to be
/// silently dropped by a network that thinks an idle connection is rubbish.
class SyncScheduler {
  SyncScheduler({
    required PlexClient client,
    required AppDatabase db,
    this.pollInterval = const Duration(seconds: 30),
  }) : _client = client,
       _db = db;

  final PlexClient _client;
  final AppDatabase _db;

  /// How often to ask whether anything changed. Cheap enough to be frequent —
  /// one small response, no metadata.
  final Duration pollInterval;

  final _progress = StreamController<SyncProgress>.broadcast();

  Timer? _timer;
  bool _busy = false;
  bool _stopped = false;

  /// Sync progress, for the banner.
  Stream<SyncProgress> get progress => _progress.stream;

  /// Number of completed passes. Exposed for tests and diagnostics.
  int get passes => _passes;
  int _passes = 0;

  /// Runs a first sync, then polls.
  ///
  /// The first pass is unconditional: an interrupted initial sync has to resume,
  /// and a cache built before the app last closed may have missed anything the
  /// socket would otherwise have pushed.
  Future<void> start() async {
    if (_stopped) return;
    _timer ??= Timer.periodic(pollInterval, (_) => unawaited(_tick()));
    await _tick(force: true);
  }

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    await _progress.close();
  }

  /// Polls immediately rather than waiting out the interval.
  ///
  /// For app resume and network reconnect — both moments when the cache is most
  /// likely to be stale and the user is most likely to be looking at it.
  Future<void> wake() => _tick();

  /// Pull-to-refresh: asks Plex to rescan, then syncs regardless of whether
  /// anything looks changed.
  ///
  /// Forced because the point of the gesture is to override our own judgement.
  /// Someone who pulls to refresh has already decided the screen is wrong, and
  /// answering "nothing changed" would be the app arguing with them.
  Future<void> refreshNow() async {
    final section = await _musicSection();
    if (section == null) return;
    try {
      await _client.refreshSection(section.key);
    } on Object {
      // A scan we could not start is not a reason to skip the sync — the
      // server may still hold changes we have not pulled.
    }
    await _tick(force: true);
  }

  Future<void> _tick({bool force = false}) async {
    // Ticks never overlap. A slow first sync of a large library would otherwise
    // have a second pass stacked on top of it every thirty seconds.
    if (_busy || _stopped) return;
    _busy = true;
    try {
      await _syncIfNeeded(force: force);
    } on Object catch (e) {
      _emit(SyncProgress(phase: SyncPhase.failed, message: '$e'));
    } finally {
      _busy = false;
    }
  }

  Future<void> _syncIfNeeded({required bool force}) async {
    final section = await _musicSection();
    if (section == null) return;

    final stored = await (_db.select(
      _db.syncState,
    )..where((s) => s.sectionKey.equals(section.key))).getSingleOrNull();

    // Only trust the delta cursor if a full pass previously finished against
    // this same server. Otherwise start from the beginning.
    final resumable =
        stored != null &&
        stored.initialSyncComplete &&
        stored.serverClientIdentifier == _client.server.clientIdentifier;

    if (!force && resumable && !_sectionChanged(section, stored)) return;

    await for (final update in LibrarySync(client: _client, db: _db).run(
      section,
      serverClientIdentifier: _client.server.clientIdentifier,
      minUpdatedAt: resumable ? stored.lastSyncedUpdatedAt : 0,
    )) {
      _emit(update);
    }
    _passes++;
  }

  /// Both clocks matter.
  ///
  /// `updatedAt` moves when metadata changes; `scannedAt` moves when Plex walks
  /// the files. A scan that finds new music bumps `scannedAt` first, so watching
  /// only `updatedAt` would miss exactly the case this exists for.
  static bool _sectionChanged(PlexSection section, SyncStateData stored) {
    return section.updatedAt != stored.serverUpdatedAt ||
        section.scannedAt != stored.serverScannedAt;
  }

  Future<PlexSection?> _musicSection() async {
    try {
      return await _client.musicSection();
    } on Object {
      // Unreachable server. Normal off the LAN; the next tick tries again.
      return null;
    }
  }

  void _emit(SyncProgress update) {
    if (!_progress.isClosed) _progress.add(update);
  }
}
