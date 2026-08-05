import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'playback_source.dart';

import '../plex/plex_client.dart';
import '../sync/library_writer.dart';

/// Tells Plex what is playing, and records the play when it finishes.
///
/// Without this, listening in Plexify is invisible to the server: it never
/// appears in Now Playing, never increments a play count, and never moves
/// `lastViewedAt` — which is the column Home's "Jump back in" shelf sorts on.
/// Running Plexify alongside another client, the history quietly splits in two,
/// and the half that was never reported cannot be reconstructed afterwards.
///
/// Two separate things are sent, because Plex does not derive one from the
/// other. A timeline says *where we are*; a scrobble says *this was played*. A
/// track can be reported all the way to its final second and still show a play
/// count of zero.
///
/// Everything here is best-effort. Reporting runs against a server that may be
/// asleep, unreachable, or mid-reconnect, and none of that may interrupt
/// playback — the audio is the point, the bookkeeping is a courtesy.
class TimelineReporter {
  TimelineReporter({
    required PlexClient client,
    required LibraryWriter writer,
    required Stream<MediaItem?> mediaItems,
    required Stream<PlaybackState> playbackStates,
    required Duration Function() position,
    this.interval = const Duration(seconds: 10),
    this.scrobbleAt = 0.9,
    DateTime Function()? now,
  }) : _client = client,
       _writer = writer,
       _mediaItems = mediaItems,
       _playbackStates = playbackStates,
       _position = position,
       _now = now ?? DateTime.now;

  final PlexClient _client;
  final LibraryWriter _writer;
  final Stream<MediaItem?> _mediaItems;
  final Stream<PlaybackState> _playbackStates;

  /// Read on demand rather than subscribed to: the position stream fires five
  /// times a second, and nothing here needs to know that often.
  final Duration Function() _position;
  final DateTime Function() _now;

  /// How often a running track is reported. Matches what Plex's own clients
  /// send; longer and the server starts treating the session as ended.
  final Duration interval;

  /// Fraction of a track that counts as having listened to it.
  final double scrobbleAt;

  Timer? _timer;
  StreamSubscription<MediaItem?>? _itemSubscription;
  StreamSubscription<PlaybackState>? _stateSubscription;

  /// Serialises the network work. Reports are ordered — a stale "playing"
  /// landing after a "stopped" would leave a ghost session on the server.
  Future<void> _queue = Future.value();

  String? _key;

  /// What the current track was started from. See `LibraryWriter.markPlayed`.
  PlaybackSource? _source;
  Duration _duration = Duration.zero;
  Duration _lastPosition = Duration.zero;
  late DateTime _lastPositionAt = _now();
  bool _playing = false;

  /// The track already counted, so a scrobble fires once per play.
  ///
  /// Cleared when the track changes, which means going back to a track you have
  /// just heard scrobbles it again. That is correct: it is a second play.
  String? _scrobbledKey;

  int get reports => _reports;
  int _reports = 0;
  int get scrobbles => _scrobbles;
  int _scrobbles = 0;
  DateTime? get lastReportAt => _lastReportAt;
  DateTime? _lastReportAt;
  String? get lastError => _lastError;
  String? _lastError;

  void start() {
    _itemSubscription ??= _mediaItems.listen(_onItem);
    _stateSubscription ??= _playbackStates.listen(_onState);
    _timer ??= Timer.periodic(interval, (_) => _enqueue(_reportRunning));
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _itemSubscription?.cancel();
    await _stateSubscription?.cancel();
    _itemSubscription = null;
    _stateSubscription = null;
    await reportStopped();
  }

  /// Tells the server this session is over.
  ///
  /// Worth sending explicitly on the way out: left to time out, the entry sits
  /// in Plex's dashboard claiming to be playing for minutes after the app has
  /// gone. Safe to call more than once — a second `stopped` for a session
  /// already closed is ignored.
  ///
  /// The caller is expected to bound this. It makes a network request, and an
  /// unreachable server must never be able to stop the app from closing.
  Future<void> reportStopped() {
    _enqueue(() => _report('stopped'));
    return _queue;
  }

  void _onItem(MediaItem? item) {
    final key = item?.extras?['ratingKey'] as String?;
    if (key == _key) return;

    final previous = _key;
    final previousDuration = _duration;
    // Worked out now, before the fields are reset out from under it.
    final previousPosition = _projectedPosition();

    _key = key;
    _source = PlaybackSource.decode(item?.extras?['source']);

    // Recorded the moment a track starts, not at the scrobble mark. "Jump
    // back in" is about what you put on, and quitting two minutes into a
    // track is not a reason to forget you put it on.
    final started = _source;
    if (started != null) {
      _enqueue(() async {
        try {
          await _writer.markStarted(started, _now());
        } on Object catch (error) {
          _lastError = '$error';
        }
      });
    }
    _duration = item?.duration ?? Duration.zero;
    _lastPosition = Duration.zero;
    _lastPositionAt = _now();

    _enqueue(() async {
      // A track that ran to its end between two ticks would otherwise never be
      // counted — the tick that would have noticed arrives only after it has
      // been replaced. Short tracks hit this constantly.
      if (previous != null) {
        await _maybeScrobble(previous, previousPosition, previousDuration);
        await _reportFor(
          previous,
          'stopped',
          previousPosition,
          previousDuration,
        );
      }
      // Only if it still refers to the track being left. Resetting
      // unconditionally is wrong twice over: done synchronously above, the
      // outgoing track loses its "already counted" mark and is counted again
      // here; done here unconditionally, it discards a mark the *incoming*
      // track may already have earned, because a queued report can run between
      // this event arriving and this closure executing.
      if (_scrobbledKey == previous) _scrobbledKey = null;
      if (key != null) await _report(_playing ? 'playing' : 'paused');
    });
  }

  /// Where the current track has most likely reached.
  ///
  /// The position getter follows the *player*, which has already moved on by
  /// the time a track change arrives — asking it then gives the new track's
  /// position, not the old one's final one. Projecting from the last sample
  /// instead is accurate for a track that ran to its end, and correctly small
  /// for one that was skipped a moment after that sample.
  Duration _projectedPosition() {
    if (!_playing) return _lastPosition;
    final elapsed = _now().difference(_lastPositionAt);
    final projected = _lastPosition + elapsed;
    return projected > _duration && _duration > Duration.zero
        ? _duration
        : projected;
  }

  void _onState(PlaybackState state) {
    if (state.playing == _playing) return;
    _playing = state.playing;
    // Pausing and resuming are exactly what a listener on another device is
    // waiting to see, so these do not wait for the next tick.
    _enqueue(() => _report(_playing ? 'playing' : 'paused'));
  }

  Future<void> _reportRunning() async {
    if (!_playing) return;
    await _report('playing');
  }

  Future<void> _report(String state) async {
    final key = _key;
    if (key == null) return;

    _lastPosition = _position();
    _lastPositionAt = _now();
    await _maybeScrobble(key, _lastPosition, _duration);
    await _reportFor(key, state, _lastPosition, _duration);
  }

  Future<void> _reportFor(
    String key,
    String state,
    Duration position,
    Duration duration,
  ) async {
    try {
      await _client.reportTimeline(
        ratingKey: key,
        state: state,
        position: position,
        duration: duration,
      );
      _reports++;
      _lastReportAt = _now();
      _lastError = null;
    } on Object catch (error) {
      _lastError = '$error';
    }
  }

  Future<void> _maybeScrobble(
    String key,
    Duration position,
    Duration duration,
  ) async {
    if (key == _scrobbledKey) return;
    if (duration <= Duration.zero) return;
    if (position.inMilliseconds < duration.inMilliseconds * scrobbleAt) return;

    // Set before the call, not after: a failed scrobble must not be retried on
    // every tick for the rest of the track.
    _scrobbledKey = key;

    try {
      await _client.scrobble(key);
      _scrobbles++;
    } on Object catch (error) {
      _lastError = '$error';
    }

    // Written even when Plex refused, because the play did happen. The next
    // sync reconciles it either way, and Home showing the track you just heard
    // is worth more than agreeing with a server that was briefly unreachable.
    try {
      await _writer.markPlayed(key, _now());
    } on Object catch (error) {
      _lastError = '$error';
    }
  }

  void _enqueue(Future<void> Function() work) {
    _queue = _queue.then((_) => work());
  }
}
