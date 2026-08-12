import 'dart:async';

import 'download_source.dart';

/// Watches whatever is arriving and tells Plex when something lands.
///
/// The last step of acquisition, and the only part of it that has to keep
/// running after the button was pressed. Without it a finished download sits in
/// the watch folder until Plex's own scheduled scan notices, which is exactly
/// the "add it, then scan, then check, then check again" dance this app exists
/// to remove.
///
/// **It adds a trigger, not a mechanism** (invariant 10). On completion it calls
/// the same [onComplete] the refresh button calls: ask Plex to rescan the
/// section, then run a sync pass. Nothing here writes to the cache, and nothing
/// here knows what a track is. Adding a second download source therefore added
/// a second *source of the trigger*, not a second recovery path.
///
/// **Polling is adaptive, and that is the whole reason it is affordable.** With
/// nothing downloading it asks every [idleInterval]; with something in flight,
/// every [activeInterval]. A fixed fast poll would run a request every few
/// seconds forever against a server most people are not downloading from.
///
/// Takes a poll function rather than a client, so it is the same monitor
/// whichever source is active and so it can be tested without either.
class DownloadMonitor {
  DownloadMonitor({
    required Future<List<DownloadJob>> Function() poll,
    required Future<void> Function() onComplete,
    this.activeInterval = const Duration(seconds: 5),
    this.idleInterval = const Duration(seconds: 60),
  }) : _poll = poll,
       _onComplete = onComplete;

  final Future<List<DownloadJob>> Function() _poll;
  final Future<void> Function() _onComplete;

  final Duration activeInterval;
  final Duration idleInterval;

  Timer? _timer;
  final _jobs = StreamController<List<DownloadJob>>.broadcast();

  /// What is arriving, as it stands. Broadcast so the downloads screen and any
  /// badge can both watch it without each polling separately.
  Stream<List<DownloadJob>> get jobs => _jobs.stream;

  List<DownloadJob> get latest => _latest;
  List<DownloadJob> _latest = const [];

  String? get lastError => _lastError;
  String? _lastError;

  /// Completions seen, for the Sync status screen. Every other background
  /// mechanism in this app publishes a counter, and the reason is the same
  /// here: "the download finished but nothing appeared" has three possible
  /// causes that look identical from the library screen.
  int get completions => _completions;
  int _completions = 0;

  int get polls => _polls;
  int _polls = 0;

  DateTime? get lastPollAt => _lastPollAt;
  DateTime? _lastPollAt;

  /// Ids already reported complete.
  ///
  /// Kept so a finished download that stays in the list, which is the normal
  /// case since qBittorrent seeds afterwards and slskd keeps transfers until
  /// they are cleared, does not ask Plex to rescan on every poll for the rest
  /// of the session.
  final _reported = <String>{};

  void start() {
    if (_timer != null) return;
    unawaited(_tick());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _jobs.close();
  }

  /// Polls now, whatever the schedule says. Used when the downloads screen
  /// opens, so it is never showing a minute-old list.
  Future<void> pollNow() => _tick();

  Future<void> _tick() async {
    _timer?.cancel();
    var active = false;

    try {
      final current = await _poll();
      _polls++;
      _lastPollAt = DateTime.now();
      _lastError = null;
      _latest = current;
      if (!_jobs.isClosed) _jobs.add(current);

      active = current.any((j) => !j.isComplete && !j.isFailed);

      // Seeded on the first poll rather than fired: a download that finished
      // before the app started is not news, and announcing every one of them at
      // launch would trigger a Plex rescan for nothing on every cold start.
      final finished = current.where((j) => j.isComplete).map((j) => j.id);
      final fresh = finished.where((id) => _reported.add(id)).toList();

      if (fresh.isNotEmpty && _seeded) {
        _completions += fresh.length;
        try {
          await _onComplete();
        } on Object catch (e) {
          _lastError = 'Could not tell Plex to rescan: $e';
        }
      }
      _seeded = true;
    } on Object catch (e) {
      _lastError = '$e';
      // Deliberately keeps polling. The server being asleep, restarting or
      // briefly unreachable is ordinary, and stopping on the first failure
      // would mean a monitor that only works when it was never needed.
    }

    if (_jobs.isClosed) return;
    _timer = Timer(active ? activeInterval : idleInterval, () {
      unawaited(_tick());
    });
  }

  bool _seeded = false;
}
