import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// The `ratingKey` of the track currently loaded, or null when nothing is.
///
/// Every track list wants this and none of them should reach into the audio
/// handler for it. Distinct, so a list of forty rows does not rebuild five
/// times a second as the position ticks.
final nowPlayingTrackKeyProvider = StreamProvider<String?>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.mediaItem
      .map((item) => item?.extras?['ratingKey'] as String?)
      .distinct();
});

/// Whether [ratingKey] is the track loaded in the player right now.
///
/// Loaded rather than *sounding*: a paused track is still the one you are on,
/// and a row that lost its marker every time you hit pause would flicker
/// through exactly the interaction it exists to support.
bool isNowPlaying(WidgetRef ref, String ratingKey) =>
    ref.watch(nowPlayingTrackKeyProvider).valueOrNull == ratingKey;

/// A small marker for the row that is playing.
///
/// Animates only while actually sounding, so a paused track keeps the marker
/// but stops moving. That distinction is the useful one at a glance: which
/// track am I on, and is it running.
class PlayingIndicator extends ConsumerWidget {
  const PlayingIndicator({this.size = 18, super.key});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final colour = Theme.of(context).colorScheme.primary;

    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return Icon(
          playing ? Icons.graphic_eq : Icons.pause,
          size: size,
          color: colour,
        );
      },
    );
  }
}
