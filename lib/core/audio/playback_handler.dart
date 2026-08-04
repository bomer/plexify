import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Bridges [AudioPlayer] to the platform's media session.
///
/// `audio_service` is what makes playback survive backgrounding on Android and
/// puts working controls on the lock screen and in the notification shade. All
/// playback goes through here — nothing else in the app should touch
/// [AudioPlayer] directly.
///
/// Queue semantics are deliberately simple: playing something **replaces** the
/// queue with a flat list. There is no separate protected "manual queue" tier.
class PlexifyAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  PlexifyAudioHandler() {
    // Mirror just_audio's state into the media session.
    _player.playbackEventStream.map(_toPlaybackState).pipe(playbackState);

    // Keep the "now playing" metadata in step with the current queue index, so
    // the lock screen shows the right track after an automatic advance.
    _player.currentIndexStream.listen((index) {
      final items = queue.value;
      if (index != null && index >= 0 && index < items.length) {
        mediaItem.add(items[index]);
      }
    });

    // just_audio does not advance past the end on its own; without this the
    // session is left showing a paused final track forever.
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _onQueueExhausted?.call();
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();

  /// Called when the queue runs dry. Phase 6 hooks sonic radio in here to keep
  /// playback going; until then it simply stops.
  void Function()? _onQueueExhausted;
  set onQueueExhausted(void Function()? callback) =>
      _onQueueExhausted = callback;

  AudioPlayer get player => _player;

  /// Replaces the queue and starts playing at [initialIndex].
  ///
  /// Uses `setAudioSources` rather than the deprecated
  /// `ConcatenatingAudioSource`, and hands the engine the whole list at once so
  /// it can pre-buffer the next track and transition gaplessly.
  Future<void> setQueueAndPlay(
    List<MediaItem> items, {
    int initialIndex = 0,
  }) async {
    if (items.isEmpty) return;
    final index = initialIndex.clamp(0, items.length - 1);

    queue.add(items);
    mediaItem.add(items[index]);

    await _player.setAudioSources(
      items.map((item) => AudioSource.uri(Uri.parse(item.id))).toList(),
      initialIndex: index,
      initialPosition: Duration.zero,
    );
    await _player.play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  Future<void> dispose() => _player.dispose();

  /// Translates just_audio's event model into the media session's.
  PlaybackState _toPlaybackState(PlaybackEvent event) {
    final playing = _player.playing;

    return PlaybackState(
      // Which buttons the lock screen and notification offer.
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      // Which controls stay visible in the collapsed notification.
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _processingState(event.processingState),
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  static AudioProcessingState _processingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }
}
