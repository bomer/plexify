import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/audio/playback_handler.dart';

import 'support/fake_just_audio.dart';

/// The queue side of autoplay: appending to a playing queue, and asking for a
/// refill early enough that the join is not a silence.
///
/// The timing is the whole design. just_audio is handed the entire queue up
/// front so it can buffer across a track boundary, which also means anything
/// appended after the last track has finished arrives too late to be reached
/// without an explicit skip. So the trigger fires while there is still music
/// playing, and these pin *when*.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeJustAudio audio;
  setUp(() => audio = FakeJustAudio.install());

  List<MediaItem> queueOf(int count, {String prefix = 'track'}) => [
    for (var i = 0; i < count; i++)
      MediaItem(
        id: 'https://server/$prefix$i',
        title: '$prefix $i',
        extras: {'ratingKey': '$prefix$i'},
      ),
  ];

  /// Moves the player onto [index] the way an automatic advance does, and lets
  /// the handler's stream listener see it.
  Future<void> advanceTo(PlexifyAudioHandler handler, int index) async {
    await handler.skipToQueueItem(index);
    await Future<void>.delayed(Duration.zero);
  }

  group('appendToQueue', () {
    test('extends both the published queue and the engine playlist', () async {
      // Two lists that must not drift: the engine plays by index and `queue` is
      // what every screen renders, so a mismatch means Up Next shows one track
      // and plays another. Nothing throws when that happens.
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);

      await handler.setQueueAndPlay(queueOf(3));
      await handler.appendToQueue(queueOf(2, prefix: 'radio'));

      expect(handler.queue.value, hasLength(5));
      expect(audio.player.loadedUris, hasLength(5));
      expect(audio.player.loadedUris.last, 'https://server/radio1');
    });

    test('leaves what is playing exactly where it was', () async {
      // The only visible effect of a refill should be that Up Next got longer.
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);

      await handler.setQueueAndPlay(queueOf(3), initialIndex: 1);
      final wasAt = handler.currentIndex;

      await handler.appendToQueue(queueOf(2, prefix: 'radio'));

      expect(handler.currentIndex, wasAt);
      expect(audio.player.playing, isTrue);
    });

    test('refuses to start playback on an empty queue', () async {
      // Starting playback belongs to setQueueAndPlay. A caller reaching for the
      // wrong one here would begin playing music nobody asked for.
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);

      await handler.appendToQueue(queueOf(2, prefix: 'radio'));

      expect(handler.queue.value, isEmpty);
      // Across every player rather than the last one, because a handler that
      // has never loaded anything has not created a platform player at all.
      expect(audio.players.expand((player) => player.loads), isEmpty);
    });
  });

  group('onQueueRunningLow', () {
    test('does not fire in the middle of a long queue', () async {
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);

      var asked = 0;
      handler.onQueueRunningLow = () => asked++;

      await handler.setQueueAndPlay(queueOf(10));
      await advanceTo(handler, 4);

      expect(asked, 0);
    });

    test('fires with tracks still to play, not once they have run out', () async {
      // Three from the end rather than at the end: a refill is a round trip to
      // a server that may be a relay away, and it has to land before the engine
      // reaches the boundary it is buffering towards.
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);

      var asked = 0;
      handler.onQueueRunningLow = () => asked++;

      await handler.setQueueAndPlay(queueOf(10));
      await advanceTo(handler, 7);

      expect(asked, 1);
      expect(handler.queue.value.length - handler.currentIndex!, 3);
    });

    test(
      'stays quiet while the queue repeats, because it never runs out',
      () async {
        // Repeat-all loops forever, so there is nothing to continue into and a
        // refill would quietly extend a queue the user asked to go round.
        final handler = PlexifyAudioHandler();
        addTearDown(handler.dispose);

        var asked = 0;
        handler.onQueueRunningLow = () => asked++;

        await handler.setQueueAndPlay(queueOf(5));
        await handler.setRepeatMode(AudioServiceRepeatMode.all);
        await advanceTo(handler, 4);

        expect(asked, 0);
      },
    );

    test('a longer queue pushes the trigger back out of reach', () async {
      // What proves a refill actually stops the asking rather than merely
      // delaying it: the same position in a queue twice as long is no longer
      // near the end.
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);

      var asked = 0;
      handler.onQueueRunningLow = () => asked++;

      await handler.setQueueAndPlay(queueOf(6));
      await advanceTo(handler, 4);
      expect(asked, 1);

      await handler.appendToQueue(queueOf(6, prefix: 'radio'));
      await advanceTo(handler, 5);

      expect(asked, 1);
    });
  });
}
