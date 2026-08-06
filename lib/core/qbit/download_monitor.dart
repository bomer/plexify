import 'dart:async';

import 'qbit_client.dart';
import 'qbit_models.dart';

/// Watches the Music category and tells Plex when something lands.
///
/// The last step of acquisition, and the only part of it that has to keep
/// running after the button was pressed. Without it a finished download sits in
/// the watch folder until Plex's own scheduled scan notices — which is exactly
/// the "add it, then scan, then check, then check again" dance this app exists
/// to remove.
///
/// **It adds a trigger, not a mechanism** (invariant 10). On completion it calls
/// the same [onComplete] the refresh button calls: ask Plex to rescan the
/// section, then run a sync pass. Nothing here writes to the cache, and nothing
/// here knows what a track is.
///
/// **Polling is adaptive, and that is the whole reason it is affordable.** With
/// nothing downloading it asks every [idleInterval]; with something in flight,
/// every [activeInterval]. A fixed fast poll would run a request every few
/// seconds forever against a server most people are not downloading from.
class DownloadMonitor {
  DownloadMonitor({
    required QbitClient Function() client,
    required Future<void> Function() onComplete,
    this.activeInterval = const Duration(seconds: 5),
    this.idleInterval = const Duration(seconds: 60),
  }) : _client = client,
       _onComplete = onComplete;

  final QbitClient Function() _client;
  final Future<void> Function() _onComplete;

  final Duration activeInterval;
  final Duration idleInterval;

  Timer? _timer;
  final _torrents = StreamController<List<QbitTorrent>>.broadcast();

  /// The Music category as it stands. Broadcast so the downloads screen and any
  /// badge can both watch it without each polling separately.
  Stream<List<QbitTorrent>> get torrents => _torrents.stream;

  List<QbitTorrent> get latest => _latest;
  List<QbitTorrent> _latest = const [];

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

  /// Hashes already reported complete.
  ///
  /// Kept so a finished torrent that stays in the list — which is the normal
  /// case, since qBittorrent seeds afterwards — does not ask Plex to rescan on
  /// every poll for the rest of the session.
  final _reported = <String>{};

  void start() {
    if (_timer != null) return;
    unawaited(_tick());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _torrents.close();
  }

  /// Polls now, whatever the schedule says. Used when the downloads screen
  /// opens, so it is never showing a minute-old list.
  Future<void> pollNow() => _tick();

  Future<void> _tick() async {
    _timer?.cancel();
    var active = false;

    try {
      final current = await _client().torrents();
      _polls++;
      _lastPollAt = DateTime.now();
      _lastError = null;
      _latest = current;
      if (!_torrents.isClosed) _torrents.add(current);

      active = current.any((t) => !t.isComplete && !t.isFailed);

      // Seeded on the first poll rather than fired: a torrent that finished
      // before the app started is not news, and announcing every one of them at
      // launch would trigger a Plex rescan for nothing on every cold start.
      final finished = current.where((t) => t.isComplete).map((t) => t.hash);
      final fresh = finished.where((hash) => _reported.add(hash)).toList();

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
      // Deliberately keeps polling. qBittorrent being asleep, restarting or
      // briefly unreachable is ordinary, and stopping on the first failure
      // would mean a monitor that only works when it was never needed.
    }

    if (_torrents.isClosed) return;
    _timer = Timer(active ? activeInterval : idleInterval, () {
      unawaited(_tick());
    });
  }

  bool _seeded = false;
}
