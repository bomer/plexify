import 'dart:async';

import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// A just_audio backend that exists entirely in Dart.
///
/// `flutter test` has no platform channels, so anything that reaches
/// `AudioPlayer.load` or `.seek` throws `MissingPluginException` and the
/// handler's own logic never runs. Installing this in its place makes the
/// parts of `PlexifyAudioHandler` that are plain Dart — which URL is loaded,
/// how far into the track the loaded stream begins — testable without an
/// engine.
///
/// Deliberately not an audio simulator. It records what it was asked to load
/// and reports a position, and nothing else; anything richer would be a second
/// implementation of just_audio to keep in step with the first.
class FakeJustAudio extends JustAudioPlatform {
  final players = <FakeAudioPlayer>[];

  /// The most recently created player, which is the one under test.
  FakeAudioPlayer get player => players.last;

  /// Installs this as just_audio's backend for the rest of the test.
  static FakeJustAudio install() {
    final fake = FakeJustAudio();
    JustAudioPlatform.instance = fake;
    return fake;
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = FakeAudioPlayer(request.id);
    players.add(player);
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    players.removeWhere((p) => p.id == request.id);
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    players.clear();
    return DisposeAllPlayersResponse();
  }
}

class FakeAudioPlayer extends AudioPlayerPlatform {
  FakeAudioPlayer(super.id);

  final _events = StreamController<PlaybackEventMessage>.broadcast();

  /// Every `load` this player has been given, oldest first. The URLs inside
  /// are what the handler actually chose to stream.
  final loads = <LoadRequest>[];

  /// Positions passed to an ordinary (non-reloading) seek.
  final seeks = <Duration>[];

  bool playing = false;

  /// What the player reports as its own position — stream time, which after a
  /// transcode reload is *not* track time.
  Duration position = Duration.zero;

  int? currentIndex;

  /// The URIs of the sources in the most recent load, in order.
  List<String> get loadedUris => _urisOf(loads.last.audioSourceMessage);

  static List<String> _urisOf(AudioSourceMessage message) => switch (message) {
    ConcatenatingAudioSourceMessage(:final children) => [
      for (final child in children) ..._urisOf(child),
    ],
    UriAudioSourceMessage(:final uri) => [uri],
    _ => const [],
  };

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    loads.add(request);
    currentIndex = request.initialIndex ?? 0;
    position = request.initialPosition ?? Duration.zero;
    _emit();
    return LoadResponse(duration: const Duration(minutes: 3));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    playing = true;
    _emit();
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    playing = false;
    _emit();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    seeks.add(request.position ?? Duration.zero);
    position = request.position ?? Duration.zero;
    if (request.index != null) currentIndex = request.index;
    _emit();
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
    SetShuffleOrderRequest request,
  ) async => SetShuffleOrderResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async => SetAndroidAudioAttributesResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await _events.close();
    return DisposeResponse();
  }

  void _emit() {
    if (_events.isClosed) return;
    _events.add(
      PlaybackEventMessage(
        processingState: ProcessingStateMessage.ready,
        updateTime: DateTime.now(),
        updatePosition: position,
        bufferedPosition: position,
        duration: const Duration(minutes: 3),
        icyMetadata: null,
        currentIndex: currentIndex,
        androidAudioSessionId: null,
      ),
    );
  }
}
