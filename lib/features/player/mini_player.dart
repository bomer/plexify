import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Persistent transport bar.
///
/// Phase 1 keeps this deliberately plain. In Phase 4 tapping it expands the
/// full Now Playing view as an overlay *over* the current screen without
/// unmounting it, so dismissing returns you exactly where you were mid-browse.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final theme = Theme.of(context);

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, itemSnapshot) {
        final item = itemSnapshot.data;
        // Nothing loaded yet — take up no space at all rather than showing an
        // empty bar.
        if (item == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, stateSnapshot) {
            final state = stateSnapshot.data;
            final playing = state?.playing ?? false;
            final buffering =
                state?.processingState == AudioProcessingState.loading ||
                state?.processingState == AudioProcessingState.buffering;

            return Material(
              color: theme.colorScheme.surfaceContainerHigh,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      if (item.artUri != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            item.artUri.toString(),
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.music_note),
                          ),
                        )
                      else
                        const Icon(Icons.music_note),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              item.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        onPressed: handler.skipToPrevious,
                      ),
                      if (buffering)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        IconButton(
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          onPressed: playing ? handler.pause : handler.play,
                        ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        onPressed: handler.skipToNext,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
