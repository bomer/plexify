import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/audio/playback_handler.dart';

import 'support/fake_just_audio.dart';

/// A transcode has no Range support and no declared length (#8), so the player
/// cannot seek it — the stream is restarted at an `offset=` instead, and its
/// clock begins again from zero.
///
/// That leaves the handler owing everyone else the difference. Get it wrong
/// and nothing throws: the progress bar simply reads a track two thirds
/// through as barely started, and the scrobble threshold is never crossed, so
/// the play quietly never reaches Plex's history.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeJustAudio audio;

  setUp(() {
    audio = FakeJustAudio.install();
  });

  /// `AudioPlayer.position` extrapolates from the last event using wall-clock
  /// time, so it runs a millisecond or two ahead of whatever was last set.
  /// Asserting to the second is the resolution the claim is actually about.
  Matcher aboutSeconds(int seconds) => predicate<Duration>(
    (d) => (d.inMilliseconds - seconds * 1000).abs() < 1000,
    'about ${seconds}s',
  );

  MediaItem item(String ratingKey, {required bool transcoded}) => MediaItem(
    id: 'https://tower.example:32400/stream/$ratingKey',
    title: 'Track $ratingKey',
    duration: const Duration(minutes: 3),
    extras: {
      'ratingKey': ratingKey,
      'qualityDecision': transcoded ? 'transcode' : 'directPlay',
      if (transcoded) 'transcodeSession': 'session-1',
    },
  );

  /// A handler with [items] queued and playing, and a resolver that rebuilds a
  /// transcode URL at an offset the way `PlaybackController` does.
  Future<PlexifyAudioHandler> playing(List<MediaItem> items) async {
    final handler = PlexifyAudioHandler();
    addTearDown(handler.dispose);
    handler.resolveSeekUrl = (item, offset) async =>
        item.extras?['qualityDecision'] == 'transcode'
        ? '${item.id}?offset=${offset.inSeconds}'
        : null;
    await handler.setQueueAndPlay(items);
    return handler;
  }

  test('reloads the stream at an offset rather than seeking it', () async {
    final handler = await playing([item('1', transcoded: true)]);

    await handler.seek(const Duration(seconds: 120));

    // The player was handed a new URL, not asked to seek within one it has no
    // way to seek.
    expect(audio.player.loadedUris.single, endsWith('?offset=120'));
    expect(audio.player.seeks, isEmpty);
  });

  test('reports position in track time after a reload', () async {
    final handler = await playing([item('1', transcoded: true)]);

    await handler.seek(const Duration(seconds: 120));

    // The player's own clock restarted at zero with the new stream; the
    // handler adds back where that stream began.
    expect(audio.player.position, Duration.zero);
    expect(handler.position, aboutSeconds(120));
  });

  test('measures a second seek from the start of the track', () async {
    final handler = await playing([item('1', transcoded: true)]);

    await handler.seek(const Duration(seconds: 120));
    await handler.seek(const Duration(seconds: 30));

    // Rebuilt from the queue's canonical offset-zero URL each time. Chaining
    // off the loaded URL instead would compound the offsets and land at 150s.
    expect(audio.player.loadedUris.single, endsWith('?offset=30'));
    expect(handler.position, aboutSeconds(30));
  });

  test(
    'keeps the rest of the queue loaded around the reloaded track',
    () async {
      final handler = await playing([
        item('1', transcoded: true),
        item('2', transcoded: true),
      ]);

      await handler.seek(const Duration(seconds: 120));

      // Loading the one track alone would end playback at the end of it, and
      // take gapless advance with it.
      expect(audio.player.loadedUris, hasLength(2));
      expect(audio.player.loadedUris.first, endsWith('?offset=120'));
      expect(audio.player.loadedUris.last, endsWith('/stream/2'));
    },
  );

  test('leaves the queue holding offset-zero URLs', () async {
    final handler = await playing([item('1', transcoded: true)]);

    await handler.seek(const Duration(seconds: 120));

    // The queue is what Up Next renders and what a later seek rebuilds from.
    // An offset baked into it would be both wrong on screen and cumulative.
    expect(handler.queue.value.single.id, isNot(contains('offset')));
  });

  test('a direct-played track seeks without a reload', () async {
    final handler = await playing([item('3', transcoded: false)]);
    final loadsBefore = audio.player.loads.length;

    await handler.seek(const Duration(seconds: 120));

    // A static file supports Range, so rebuilding its URL would throw away a
    // working seek and restart the download for nothing.
    expect(audio.player.loads, hasLength(loadsBefore));
    expect(audio.player.seeks, [const Duration(seconds: 120)]);
    expect(handler.position, aboutSeconds(120));
  });

  test(
    'falls back to an ordinary seek when the URL cannot be rebuilt',
    () async {
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);
      handler.resolveSeekUrl = (_, _) async => null;
      await handler.setQueueAndPlay([item('4', transcoded: true)]);

      // Worse than a real transcode seek, but never an exception into the
      // transport controls — and the offset must not be claimed for a stream
      // that was never restarted.
      await handler.seek(const Duration(seconds: 120));

      expect(audio.player.seeks, [const Duration(seconds: 120)]);
      expect(handler.position, aboutSeconds(120));
    },
  );

  test('playing a new queue puts the clock back to the player\'s', () async {
    final handler = await playing([item('1', transcoded: true)]);
    await handler.seek(const Duration(seconds: 120));
    expect(handler.position, aboutSeconds(120));

    // Left stale, every position for the rest of the session would be
    // overstated by wherever the last seek landed — and the next track would
    // scrobble the moment it started.
    await handler.setQueueAndPlay([item('5', transcoded: true)]);

    expect(handler.position, aboutSeconds(0));
  });

  group('shuffle and repeat', () {
    test('are published, not just set on the player', () async {
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);
      await handler.setQueueAndPlay([item('1', transcoded: false)]);

      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      // `playbackState` is fed by `pipe`, which delivers asynchronously, so
      // the last state published has not reached the subject yet.
      await Future<void>.delayed(Duration.zero);

      // The lock screen renders whatever the state says. A control that
      // toggles the engine but not the reported state shows the wrong icon
      // for ever, which reads as the button not working.
      expect(
        handler.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.all,
      );
      expect(
        handler.playbackState.value.repeatMode,
        AudioServiceRepeatMode.one,
      );
    });

    test('turn back off again', () async {
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);
      await handler.setQueueAndPlay([item('1', transcoded: false)]);

      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      await handler.setRepeatMode(AudioServiceRepeatMode.none);
      await Future<void>.delayed(Duration.zero);

      expect(
        handler.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.none,
      );
      expect(
        handler.playbackState.value.repeatMode,
        AudioServiceRepeatMode.none,
      );
    });
  });
}
