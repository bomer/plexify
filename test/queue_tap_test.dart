import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/audio/playback_handler.dart';

import 'support/fake_just_audio.dart';

/// Tapping a track in Up Next.
///
/// Reported as "click a song queues it but doesn't start playing", which is
/// exactly what it did: `skipToQueueItem` seeked to the index and left the
/// player in whatever state it was already in. Paused in, paused out — the app
/// took the instruction and appeared to ignore it.
///
/// Paused is also the state most likely to be in when reaching for that list,
/// because a launch restores the previous queue **paused** on purpose.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeJustAudio audio;
  setUp(() => audio = FakeJustAudio.install());

  List<MediaItem> queueOf(int count) => [
    for (var i = 0; i < count; i++)
      MediaItem(id: 'https://server/track$i', title: 'Track $i'),
  ];

  test('picking a track out of the queue starts it', () async {
    final handler = PlexifyAudioHandler();
    addTearDown(handler.dispose);

    await handler.setQueueAndPlay(queueOf(3));
    await handler.pause();
    expect(audio.player.playing, isFalse);

    await handler.skipToQueueItem(2);

    // Both halves matter: the right track, and actually playing it.
    expect(handler.currentIndex, 2);
    expect(audio.player.playing, isTrue);
  });

  test('an index outside the queue is ignored rather than played', () async {
    final handler = PlexifyAudioHandler();
    addTearDown(handler.dispose);

    await handler.setQueueAndPlay(queueOf(2));
    await handler.pause();

    await handler.skipToQueueItem(9);
    await handler.skipToQueueItem(-1);

    // The guard has to come before the play, or a bad index from a media
    // session client starts playback on whatever was already loaded.
    expect(audio.player.playing, isFalse);
  });

  test('skipping forward does not resume a paused player', () async {
    final handler = PlexifyAudioHandler();
    addTearDown(handler.dispose);

    await handler.setQueueAndPlay(queueOf(3));
    await handler.pause();

    await handler.skipToNext();

    // Deliberately different from tapping a track. Next and previous arrive
    // from lock-screen and media-key buttons, where starting playback somebody
    // had paused is the surprising outcome rather than the intuitive one.
    expect(audio.player.playing, isFalse);
  });
}
