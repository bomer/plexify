import 'dart:async';

import '../db/app_database.dart';
import '../plex/plex_client.dart';
import '../plex/plex_models.dart';
import 'library_sync.dart';

/// Decides when to sync, and runs it.
///
/// The cheap tier of the sync design. `/library/sections` returns `updatedAt`
/// and `scannedAt` per section in one small response, so asking "has anything
/// changed?" costs almost nothing and can be asked often. When the answer is
/// yes, a delta sync follows.
///
/// Those clocks are not the whole story though — they describe the library's
/// shape, and a metadata-only edit such as rating an album moves neither. So a
/// slower [deltaInterval] sweep runs a pass regardless, and that pass is
/// **unfiltered**: Plex does not move a row's own `updatedAt` for a rating
/// either, so there is no cheap question that can find one.
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
    this.deltaInterval = const Duration(minutes: 15),
    DateTime Function()? now,
  }) : _client = client,
       _db = db,
       _now = now ?? DateTime.now;

  final PlexClient _client;
  final AppDatabase _db;

  /// How often to ask whether anything changed. Cheap enough to be frequent —
  /// one small response, no metadata.
  final Duration pollInterval;

  /// How often to sweep the whole library for edits no clock announced.
  ///
  /// The section's `updatedAt` and `scannedAt` track the library's *shape* —
  /// files appearing, a scan running. A metadata-only edit such as rating an
  /// album from Plex's own client does not reliably move either, so a scheduler
  /// that trusts them alone will never notice the stars you just set.
  ///
  /// **This sweep is unfiltered, and therefore expensive.** Plex does not move
  /// a row's `updatedAt` when its rating changes (measured, 6 August 2026), so
  /// there is no cheap question that can find one. Fifteen minutes rather than
  /// five is the price of doing it honestly: a full pass over an 11.5k-track
  /// library is around seventy requests, and three of those an hour is a
  /// defensible background cost where twelve is not.
  ///
  /// Nothing else waits on it. New music arrives by push in under a second, or
  /// by the [pollInterval] check within thirty seconds, both of which *can*
  /// filter. Only ratings set in another client wait on this, and the refresh
  /// button forces one immediately.
  final Duration deltaInterval;

  final DateTime Function() _now;
  DateTime? _lastDelta;

  final _progress = StreamController<SyncProgress>.broadcast();

  Timer? _timer;
  bool _busy = false;
  bool _stopped = false;

  /// Sync progress, for the banner.
  Stream<SyncProgress> get progress => _progress.stream;

  /// Number of completed passes. Exposed for tests and diagnostics.
  int get passes => _passes;
  int _passes = 0;

  /// When the cheap "has anything changed?" question was last asked and
  /// answered. Null means it has never completed — which usually means the
  /// server is unreachable rather than that the scheduler is idle.
  DateTime? get lastPollAt => _lastPoll;
  DateTime? _lastPoll;

  /// When a sync pass last finished.
  DateTime? get lastSyncAt => _lastDelta;

  /// Whatever went wrong most recently, kept so it can be read rather than
  /// inferred from an empty screen.
  String? get lastError => _lastError;
  String? _lastError;

  bool get isSyncing => _busy;

  /// Rows the last sync pulled down.
  ///
  /// **Read it against what triggered the pass.** A clock-triggered delta
  /// should report a handful; the whole library there means the filter stopped
  /// working. The fifteen-minute sweep reports the whole library *by design*,
  /// because it is unfiltered, because Plex offers no question that finds a
  /// changed rating.
  int get lastSyncRowCount => _lastSyncRowCount;
  int _lastSyncRowCount = 0;

  /// Runs a first check, then polls.
  ///
  /// **Not forced.** It used to be, and that turned every launch into a full
  /// pass: `_lastDelta` began null, so a sweep was always due, and the sweep is
  /// unfiltered. Quitting and reopening therefore refetched the entire library,
  /// about seventy requests, every time.
  ///
  /// Nothing is lost by asking rather than assuming. An interrupted initial
  /// sync still resumes, because `initialSyncComplete` being false makes the
  /// check below report a change regardless of the section clocks; and anything
  /// that happened while the app was closed moved one of those clocks, which is
  /// what they are for.
  Future<void> start() async {
    if (_stopped) return;
    // Restores the sweep clock from disk. Held only in memory it reset on every
    // launch, which is what made a sweep permanently due.
    _lastDelta ??= await _db.lastDeltaSweepAt();
    _timer ??= Timer.periodic(pollInterval, (_) => unawaited(_tick()));
    await _tick();
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

  /// Stops polling until [resume].
  ///
  /// Called when the app leaves the foreground. On Android the isolate stays
  /// alive for the whole of a playback session, so without this the poll runs
  /// for hours down a phone's mobile connection, checking for changes to a
  /// screen nobody is looking at. Nothing is lost by waiting: [resume] polls
  /// immediately, so the first thing you see on coming back is current.
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  /// Restarts polling and checks straight away.
  Future<void> resume() async {
    if (_stopped || _timer != null) return;
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_tick()));
    await _tick();
  }

  /// Pull-to-refresh: asks Plex to rescan, then syncs regardless of whether
  /// anything looks changed.
  ///
  /// Forced because the point of the gesture is to override our own judgement.
  /// Someone who pulls to refresh has already decided the screen is wrong, and
  /// answering "nothing changed" would be the app arguing with them.
  /// Rewinds the delta cursor and resyncs everything.
  ///
  /// For when the cache is wrong in a way an incremental pass cannot fix. The
  /// only honest repair when we cannot tell what is missing.
  Future<void> fullResync() async {
    await _db.rewindSyncCursor();
    _lastDelta = null;
    await _tick(force: true);
  }

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
      _lastError = '$e';
      _emit(SyncProgress(phase: SyncPhase.failed, message: '$e'));
    } finally {
      _busy = false;
    }
  }

  Future<void> _syncIfNeeded({required bool force}) async {
    final section = await _musicSection();
    if (section == null) return;
    _lastPoll = _now();

    final stored = await (_db.select(
      _db.syncState,
    )..where((s) => s.sectionKey.equals(section.key))).getSingleOrNull();

    // Only trust the delta cursor if a full pass previously finished against
    // this same server. Otherwise start from the beginning.
    final resumable =
        stored != null &&
        stored.initialSyncComplete &&
        stored.serverClientIdentifier == _client.server.clientIdentifier;

    final changed = !resumable || _sectionChanged(section, stored);
    final sweepDue = _deltaSweepDue();
    if (!force && !changed && !sweepDue) return;

    // **The cursor is only used when the section clocks are what triggered
    // this.** Measured on 6 August 2026, and it is the whole shape of the
    // problem: adding music moves `updatedAt`, rating something does not.
    //
    // So a clock-triggered pass can filter, because whatever moved the clock
    // also moved the timestamp, and fetching seventeen rows instead of
    // thirteen thousand is the entire point of a delta sync.
    //
    // The sweep cannot. It exists precisely to catch metadata edits that no
    // clock announces, and stars set in Plex are the case it was built for.
    // Filtering it by a timestamp that does not move for those edits leaves it
    // running, costing requests, and structurally unable to find the one thing
    // it is for. That regression shipped for about an hour and presented as a
    // favourite set on the phone never reaching the desktop.
    //
    // Forced passes go unfiltered too. Someone who pressed refresh has already
    // decided the screen is wrong, and answering with a cheap query that cannot
    // see ratings would be the app arguing with them.
    final useCursor = resumable && changed && !sweepDue && !force;

    final fetched = <SyncPhase, int>{};

    await for (final update in LibrarySync(client: _client, db: _db).run(
      section,
      serverClientIdentifier: _client.server.clientIdentifier,
      minUpdatedAt: useCursor ? stored.lastSyncedUpdatedAt : 0,
    )) {
      if (update.phase == SyncPhase.failed) _lastError = update.message;
      fetched[update.phase] = update.done;
      _emit(update);
    }

    _lastSyncRowCount = fetched.values.fold(0, (a, b) => a + b);
    _lastDelta = _now();
    // Persisted so the interval means elapsed time rather than uptime.
    await _db.markDeltaSweep(_lastDelta!);
    _passes++;
  }

  /// Whether it is time to sweep for edits the section clocks never announced.
  bool _deltaSweepDue() {
    final last = _lastDelta;
    return last == null || _now().difference(last) >= deltaInterval;
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
    } on Object catch (e) {
      // Unreachable server. Normal off the LAN; the next tick tries again.
      // Recorded rather than swallowed, because "nothing is syncing" and "the
      // server has been refusing us for an hour" look identical otherwise.
      _lastError = '$e';
      return null;
    }
  }

  void _emit(SyncProgress update) {
    if (!_progress.isClosed) _progress.add(update);
  }
}
