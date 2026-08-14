import 'dart:async';

import '../catalog/catalog_models.dart';
import 'download_source.dart';

/// How far along one request is.
enum AcquireStage {
  /// In the queue, nothing asked yet.
  waiting,

  /// Being searched for right now. Exactly one request is ever in this state.
  searching,

  /// Handed to the download server, which is now fetching it.
  ///
  /// **The end of this queue's responsibility.** From here `DownloadMonitor`
  /// sees it as a job on the server, which is the thing that actually knows
  /// about bytes and progress. Two systems tracking one download is how they
  /// come to disagree.
  handedOver,

  /// Searched, and nothing found that confidently names the record.
  notFound,

  /// The server could not be reached, or refused.
  failed,
}

/// One album somebody asked for.
class AcquireRequest {
  const AcquireRequest({
    required this.release,
    this.stage = AcquireStage.waiting,
    this.detail,
  });

  final CatalogRelease release;
  final AcquireStage stage;

  /// The server's own words when this went wrong, or what was queued when it
  /// went right. Shown on the Downloads screen, where it can actually be read.
  final String? detail;

  /// The MusicBrainz release-group id, which is the identity throughout.
  String get id => release.mbid;

  bool get isFinished =>
      stage == AcquireStage.handedOver ||
      stage == AcquireStage.notFound ||
      stage == AcquireStage.failed;

  AcquireRequest at(AcquireStage stage, {String? detail}) =>
      AcquireRequest(release: release, stage: stage, detail: detail);
}

/// Albums waiting to be found, searched for one at a time.
///
/// **Why this exists at all.** Searching used to happen inline, inside the tap:
/// a Soulseek search takes fifteen to twenty-five seconds, and the app sat on a
/// progress banner for all of it. Asking for three albums meant three
/// concurrent searches and six queued snackbars playing out long after their
/// searches had finished, which read as the app being stuck. The work is
/// genuinely slow, so the honest answer is to accept it and get out of the way
/// rather than to make the user watch.
///
/// **Strictly one at a time**, and that is a decision rather than a
/// simplification. Soulseek searches are slow because they wait on strangers,
/// not because they are throttled here, so running three at once mostly means
/// three slow searches instead of one, and results arriving in an order
/// unrelated to the order they were asked for.
///
/// Modelled on [DownloadMonitor]: session-lived, takes a getter rather than a
/// client so it can be tested without a server, and publishes a broadcast
/// stream so several screens can watch one queue.
///
/// **Held in memory only.** Persisting it would mean a drift table and a schema
/// bump for state that is minutes old, and anything already handed over
/// survives on the download server regardless. A queue lost to an app restart
/// is lost, which is a real limitation and a cheap one.
class AcquireQueue {
  AcquireQueue({required Future<DownloadSource?> Function() source})
    : _source = source;

  final Future<DownloadSource?> Function() _source;

  final _controller = StreamController<List<AcquireRequest>>.broadcast();
  final _requests = <AcquireRequest>[];

  bool _running = false;
  bool _closed = false;

  /// Everything asked for this session, in the order it was asked for.
  Stream<List<AcquireRequest>> get stream => _controller.stream;

  List<AcquireRequest> get requests => List.unmodifiable(_requests);

  /// Whether a search is in flight, for anything that wants to say so.
  bool get isBusy => _running;

  /// How many are still to be dealt with.
  int get pending =>
      _requests.where((r) => !r.isFinished).length;

  /// Adds [release], unless it is already here.
  ///
  /// Returns false when it was already queued, so the caller can say "already
  /// on the list" instead of silently doing nothing. Deduplicated on the
  /// release-group id, which makes a double tap harmless.
  bool add(CatalogRelease release) {
    if (_closed) return false;
    if (_requests.any((r) => r.id == release.mbid)) return false;

    _requests.add(AcquireRequest(release: release));
    _publish();
    unawaited(_drain());
    return true;
  }

  /// Puts a finished request back in the queue.
  ///
  /// Worth having because the failures that actually happen are a phone on a
  /// flaky mobile link, and the fix for those is to ask again.
  bool retry(String id) {
    final index = _requests.indexWhere((r) => r.id == id);
    if (index < 0 || !_requests[index].isFinished) return false;

    _requests[index] = _requests[index].at(AcquireStage.waiting);
    _publish();
    unawaited(_drain());
    return true;
  }

  /// Forgets a request. Only affects this list; anything already handed over is
  /// the download server's business now.
  bool remove(String id) {
    final before = _requests.length;
    _requests.removeWhere((r) => r.id == id && r.stage != AcquireStage.searching);
    if (_requests.length == before) return false;
    _publish();
    return true;
  }

  /// Drops everything that is done with, leaving whatever is still to come.
  void clearFinished() {
    _requests.removeWhere((r) => r.isFinished);
    _publish();
  }

  Future<void> close() async {
    _closed = true;
    await _controller.close();
  }

  /// Works through the queue until nothing is waiting.
  ///
  /// Re-entrant by guard rather than by lock: [add] and [retry] both call this,
  /// and the guard means a second caller returns immediately and lets the one
  /// already running pick up whatever was just appended.
  Future<void> _drain() async {
    if (_running || _closed) return;
    _running = true;

    try {
      while (!_closed) {
        final index = _requests.indexWhere(
          (r) => r.stage == AcquireStage.waiting,
        );
        if (index < 0) break;

        _requests[index] = _requests[index].at(AcquireStage.searching);
        _publish();

        final result = await _find(_requests[index].release);

        // Found again by id rather than by index: the list can have been
        // reordered or shortened by a removal while the search was running,
        // and writing to a stale index would mark the wrong album.
        final now = _requests.indexWhere((r) => r.id == result.id);
        if (now >= 0) _requests[now] = result;
        _publish();
      }
    } finally {
      _running = false;
    }
  }

  Future<AcquireRequest> _find(CatalogRelease release) async {
    final request = AcquireRequest(release: release);
    try {
      final source = await _source();
      if (source == null) {
        return request.at(
          AcquireStage.failed,
          detail: 'No download server is set up.',
        );
      }

      final outcome = await source.queueBest(release);

      if (outcome.error != null) {
        return request.at(AcquireStage.failed, detail: outcome.error);
      }

      final queued = outcome.queued;
      if (queued != null) {
        return request.at(AcquireStage.handedOver, detail: queued.title);
      }

      // Found things, none of them confidently this record. Deliberately not a
      // best guess: queueing the wrong album puts it in the folder Plex
      // watches under this album's name, and the first anyone knows is a
      // tribute record in the library.
      return request.at(
        AcquireStage.notFound,
        detail: outcome.candidates.isEmpty
            ? 'Nobody has it right now.'
            : '${outcome.candidates.length} results, none clearly this record. '
                  'Open the artist and long press to choose.',
      );
    } on Object catch (e) {
      return request.at(AcquireStage.failed, detail: '$e');
    }
  }

  void _publish() {
    if (!_controller.isClosed) _controller.add(List.unmodifiable(_requests));
  }
}
