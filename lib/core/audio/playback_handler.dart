import 'dart:async';
import 'dart:io';

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
    //
    // `handleError` rather than letting it through: `pipe` is `addStream`, and
    // an error reaching `playbackState` closes the subscription for good — one
    // unreachable track would leave the media session frozen for the rest of
    // the session, long after the connection came back.
    // One writer, and it is this controller.
    //
    // `playbackState` is fed by `pipe`, which is `addStream`, and rxdart
    // refuses a manual `add` while a stream is being piped in. Piping the
    // player's events straight in therefore made the subject unwritable by
    // anything else, which is what broke `super.stop()` and would have broken
    // shuffle and repeat the same way. Everything that wants to publish a
    // state now goes through here instead.
    _player.playbackEventStream
        .handleError((Object _) => onPlaybackFailed?.call())
        .listen((event) => _publish(_toPlaybackState(event)));
    _states.stream.pipe(playbackState);

    // The channel just_audio actually reports playback failures on. They ride
    // on the event's `errorCode` rather than as a stream error, so the
    // `handleError` above never sees them — it covers the platform dropping
    // out entirely, which is a different fault.
    //
    // Worth listening to at all because the audio engine does its own HTTP:
    // a queue of URLs pointing at an address that stopped answering fails
    // here and nowhere else, so without this nothing in the app can tell.
    _player.errorStream.listen((_) => onPlaybackFailed?.call());

    // Keep the "now playing" metadata in step with the current queue index, so
    // the lock screen shows the right track after an automatic advance.
    _player.currentIndexStream.listen((index) {
      final items = queue.value;
      if (index == null || index < 0 || index >= items.length) return;

      // Only a genuine *change* of track means the player's clock is the
      // track's clock again. Reloading the current track's stream at an offset
      // re-emits the same index, and clearing the offset here would throw away
      // the seek that had just been performed — leaving every position
      // understated by however far in the user had skipped.
      if (index != _currentIndex) {
        _currentIndex = index;
        _streamStartedAt = Duration.zero;
      }
      mediaItem.add(items[index]);
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

  final _states = StreamController<PlaybackState>();

  void _publish(PlaybackState state) {
    if (!_states.isClosed) _states.add(state);
  }

  /// Called when the queue runs dry. Phase 6 hooks sonic radio in here to keep
  /// playback going; until then it simply stops.
  void Function()? _onQueueExhausted;
  set onQueueExhausted(void Function()? callback) =>
      _onQueueExhausted = callback;

  /// Rebuilds a playback URL to begin at [offset], or returns null if the item
  /// cannot be restarted partway in.
  ///
  /// Set by whatever knows how to build URLs — this handler deliberately does
  /// not. See [seek] for why it is needed at all.
  /// Readable as well as writable so a departing owner can check the resolver
  /// is still its own before clearing it, rather than wiping its
  /// replacement's.
  Future<String?> Function(MediaItem item, Duration offset)? resolveSeekUrl;

  /// Where this item's audio may be cached, or null to stream it straight
  /// through.
  ///
  /// Null is the honest answer in more cases than it looks: on a metered
  /// connection, for a URL carrying a seek offset, or when the cache could
  /// not open. Set by whatever owns those policies, which is not this class.
  File? Function(MediaItem item)? resolveCacheFile;

  /// How far into the current track the loaded stream begins.
  ///
  /// Non-zero only after a transcode seek, where the stream is restarted at an
  /// offset and the player's own clock therefore starts again from zero. Every
  /// position this handler reports adds it back, so the rest of the app —
  /// progress bar, lock screen, scrobble threshold — keeps working in track
  /// time rather than stream time.
  Duration _streamStartedAt = Duration.zero;

  /// The queue index [_streamStartedAt] belongs to, so a reload of the current
  /// track can be told apart from an advance to the next one.
  int? _currentIndex;

  /// Called when the engine fails to load or play the current source.
  ///
  /// Almost always a dead URL rather than a broken file: every playback URL
  /// embeds the server address that was live when the queue was built, and the
  /// engine does its own HTTP, so nothing else in the app can see it fail.
  void Function()? onPlaybackFailed;

  AudioPlayer get player => _player;

  /// Position within the *track*, which is not the player's position once a
  /// transcode has been seeked. Prefer this over `player.position` everywhere.
  Duration get position => _streamStartedAt + _player.position;

  int? get currentIndex => _player.currentIndex ?? _currentIndex;

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

    _streamStartedAt = Duration.zero;
    _currentIndex = index;
    queue.add(items);
    mediaItem.add(items[index]);

    await _player.setAudioSources(
      items.map(_toAudioSource).toList(),
      initialIndex: index,
      initialPosition: Duration.zero,
    );
    await _player.play();
  }

  /// Streams through a cache file when one is offered, straight from the
  /// network when not.
  ///
  /// `LockCachingAudioSource` writes the file as the track plays, so this
  /// costs nothing extra on the first listen and everything on the second.
  AudioSource _toAudioSource(MediaItem item) {
    final uri = Uri.parse(item.id);
    final file = resolveCacheFile?.call(item);
    if (file == null) return AudioSource.uri(uri);
    // Marked experimental upstream, and the only caching source just_audio
    // offers. #8 confirmed it copes with Plex's transcode stream: it needs a
    // 200 on the first fetch, tolerates a missing content-length, and still
    // renames the completed file. Pinned in pubspec, so an upstream change
    // arrives as a deliberate upgrade rather than a surprise.
    // ignore: experimental_member_use
    return LockCachingAudioSource(uri, cacheFile: file);
  }

  /// Swaps the queue for one built against a new connection, carrying on from
  /// [resumeAt].
  ///
  /// Distinct from [setQueueAndPlay] in what it preserves rather than in what
  /// it does: the same tracks in the same order at the same position, only
  /// reachable again. Every URL in a queue is fixed when it is built and
  /// embeds the server address of that moment, so a change of route leaves the
  /// whole queue pointing somewhere that no longer answers — not just the
  /// track playing.
  ///
  /// [streamStartsAt] is how far into the current track its *URL* already
  /// begins: non-zero when the current item is a transcode rebuilt at an
  /// offset, since a transcode cannot be seeked and must arrive already at the
  /// right place. Zero for a direct play, which seeks normally.
  Future<void> resumeQueue(
    List<MediaItem> items, {
    required int index,
    required Duration resumeAt,
    Duration streamStartsAt = Duration.zero,
  }) async {
    if (items.isEmpty) return;
    final at = index.clamp(0, items.length - 1);

    // Whether it *was* playing, captured before the reload replaces the state.
    // A queue rebuilt because the connection died should not start playing
    // under someone who had deliberately paused.
    final wasPlaying = _player.playing;

    _streamStartedAt = streamStartsAt;
    _currentIndex = at;
    queue.add(items);
    mediaItem.add(items[at]);

    await _player.setAudioSources(
      items.map(_toAudioSource).toList(),
      initialIndex: at,
      initialPosition: resumeAt - streamStartsAt,
    );

    if (wasPlaying) await _player.play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  /// Output level, 0 to 1.
  ///
  /// Applies to this app's own stream only. It is not the system volume and
  /// deliberately does not try to be: the OS mixer is where a phone's hardware
  /// keys land, and an app that fought it would leave two numbers to be wrong
  /// independently.
  ///
  /// Not part of the `audio_service` interface, which has no general volume
  /// call. `androidSetRemoteVolume` exists and is a different thing entirely:
  /// it is for casting to a device whose volume the phone does not own.
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  /// The level the engine is actually at, which is what the slider follows.
  ///
  /// Read from the player rather than from settings so the control cannot drift
  /// from the thing it controls, in either direction.
  Stream<double> get volumeStream => _player.volumeStream;

  /// Seeks within the current track.
  ///
  /// Ordinary files seek the way anyone would expect. A **transcode cannot**:
  /// #8 measured that Plex's music transcoder answers 200 to a ranged request
  /// and offers the whole stream, and declares no length at all — so there is
  /// nothing for the player to seek *within*. Its only handle on the middle of
  /// a track is `offset=`, which starts a fresh transcode partway in.
  ///
  /// So for a transcode this reloads the stream at [position] and remembers
  /// where it began, rather than asking the player to do something it has no
  /// way to do. The session id is reused deliberately: Plex replaces the
  /// stream for a session it already knows, where a new id would leave the
  /// old transcode running for nobody.
  ///
  /// Falls back to an ordinary seek if the URL cannot be rebuilt — worse, but
  /// no worse than before, and never an exception into the transport controls.
  @override
  Future<void> seek(Duration position) async {
    final item = mediaItem.value;
    final resolve = resolveSeekUrl;

    if (item == null || resolve == null || !_isTranscode(item)) {
      _streamStartedAt = Duration.zero;
      return _player.seek(position);
    }

    final url = await resolve(item, position);
    if (url == null) return _player.seek(position);

    final items = queue.value;
    final index = _player.currentIndex ?? items.indexOf(item);
    if (index < 0 || index >= items.length) return _player.seek(position);

    final playing = _player.playing;

    // Rebuilt whole rather than swapping one entry, so the queue either side
    // of the current track stays loaded and gapless advance still works.
    // `queue` itself is left alone: its ids are the canonical offset-zero
    // URLs, which is what keeps a second seek measuring from the start of the
    // track rather than compounding on the first.
    _streamStartedAt = position;
    await _player.setAudioSources(
      [
        for (final (i, queued) in items.indexed)
          AudioSource.uri(Uri.parse(i == index ? url : queued.id)),
      ],
      initialIndex: index,
      initialPosition: Duration.zero,
    );

    if (playing) await _player.play();
  }

  static bool _isTranscode(MediaItem item) =>
      item.extras?['qualityDecision'] == 'transcode';

  /// Shuffle and repeat, which `BaseAudioHandler` declares and does not
  /// implement.
  ///
  /// Published back through `_toPlaybackState` as well as set on the player,
  /// because the lock screen renders whatever the state says. A control that
  /// toggles the engine but not the reported state shows the wrong icon
  /// forever, which reads as the button not working.
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async {
    final on = mode != AudioServiceShuffleMode.none;
    // Ordering matters: just_audio requires a shuffle order to exist before
    // enabling, or the first shuffled advance replays the current track.
    if (on) await _player.shuffle();
    await _player.setShuffleModeEnabled(on);
    _shuffle = mode;
    _republish();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => LoopMode.all,
      AudioServiceRepeatMode.none => LoopMode.off,
    });
    _repeat = repeatMode;
    _republish();
  }

  AudioServiceShuffleMode _shuffle = AudioServiceShuffleMode.none;
  AudioServiceRepeatMode _repeat = AudioServiceRepeatMode.none;

  /// Pushes the current state through the same mapping the player's events
  /// use, so a mode change is visible without waiting for the next event.
  void _republish() => _publish(_toPlaybackState(_player.playbackEvent));

  /// Moves a queue entry, keeping the engine's playlist and the published
  /// queue in step.
  ///
  /// Both have to move or they drift apart silently: the engine plays by index
  /// and `queue` is what every screen and the lock screen render, so a
  /// mismatch means tapping the third row plays the fourth track. Nothing
  /// throws when that happens, which is what makes it worth being careful
  /// about.
  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    final items = List<MediaItem>.of(queue.value);
    if (!_inRange(oldIndex, items) || !_inRange(newIndex, items)) return;
    if (oldIndex == newIndex) return;

    await _player.moveAudioSource(oldIndex, newIndex);
    items.insert(newIndex, items.removeAt(oldIndex));
    queue.add(items);

    // The current track may have shifted without changing, so the index the
    // state reports has to be recomputed rather than assumed.
    _currentIndex = _player.currentIndex;
    _republish();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    final items = List<MediaItem>.of(queue.value);
    if (!_inRange(index, items)) return;

    // Removing the track that is playing would stop it, which is not what
    // swiping a row *further down the list* should ever do. The caller only
    // offers this for upcoming entries; this is the guard for when it does
    // not.
    if (index == _player.currentIndex) return;

    await _player.removeAudioSourceAt(index);
    items.removeAt(index);
    queue.add(items);
    _currentIndex = _player.currentIndex;
    _republish();
  }

  static bool _inRange(int index, List<MediaItem> items) =>
      index >= 0 && index < items.length;

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  /// Jumps to a track someone picked out of the queue, **and plays it**.
  ///
  /// The play is the point. Seeking alone keeps whatever state the player was
  /// in, so tapping a song in Up Next while paused selected it and sat there —
  /// which reads as the app queueing your choice and ignoring it. Launch
  /// restores paused deliberately, so that was the state most likely to be in
  /// when reaching for this.
  ///
  /// Deliberately not done for [skipToNext] and [skipToPrevious]: those arrive
  /// from lock-screen and media-key buttons, where starting playback that
  /// somebody had paused would be the surprising behaviour rather than the
  /// intuitive one. Picking a specific track out of a list is a different
  /// gesture with a different obvious answer.
  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  /// Stops playback and lets the media session go idle.
  ///
  /// Deliberately does **not** call `super.stop()`. `BaseAudioHandler.stop`
  /// pushes an idle state into `playbackState` by hand, and this handler feeds
  /// that same subject from the player via `pipe` — rxdart refuses a manual
  /// `add` while a stream is being piped in, so the super call throws
  /// "You cannot add items while items are being added from addStream". It was
  /// also redundant: stopping the player emits an idle event that arrives
  /// through the pipe on its own.
  @override
  Future<void> stop() => _player.stop();

  /// Stops and forgets everything that was loaded.
  ///
  /// Separate from [stop], which ends the session but leaves the queue in
  /// place so the transport can resume it. Signing out is the case where that
  /// is wrong: the mini player hides on a null `mediaItem` and nothing else, so
  /// a plain stop would leave the last track of the old server's library on
  /// screen, pointing at a URL that no longer resolves.
  Future<void> clearQueue() async {
    await stop();
    queue.add(const []);
    mediaItem.add(null);
  }

  Future<void> dispose() async {
    await _states.close();
    await _player.dispose();
  }

  /// Translates just_audio's event model into the media session's.
  PlaybackState _toPlaybackState(PlaybackEvent event) {
    final playing = _player.playing;

    return PlaybackState(
      // Which buttons the lock screen and notification offer.
      //
      // MediaControl.stop is deliberately absent. On Android 13+ audio_service
      // converts it into a PlaybackStateCompat.CustomAction, which requires a
      // non-zero icon resource; the icon is resolved by name against *our*
      // package and comes back 0, so the builder throws
      // IllegalArgumentException and the entire notification fails to post —
      // taking the lock-screen and quick-settings controls with it. Verified on
      // Android 16. Play/pause and skip are the conventional set for a music
      // player regardless; stop adds nothing here.
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      // Which controls stay visible in the collapsed notification.
      androidCompactActionIndices: const [0, 1, 2],
      shuffleMode: _shuffle,
      repeatMode: _repeat,
      processingState: _processingState(event.processingState),
      playing: playing,
      // Track time, not stream time — see [position].
      updatePosition: position,
      bufferedPosition: _streamStartedAt + _player.bufferedPosition,
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
