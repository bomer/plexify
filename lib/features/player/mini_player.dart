import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/playback_handler.dart';
import '../../core/providers.dart';
import 'player_providers.dart';

/// Persistent transport bar.
///
/// Tapping anywhere other than a transport button expands the full Now Playing
/// view over the current screen — which is a sibling layer in the shell's
/// [Stack], not a pushed route, so the screen underneath is never unmounted.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, this.aboveNavigationBar = false});

  /// Whether a [NavigationBar] sits directly below this.
  ///
  /// When one does it owns the bottom system inset, and reserving it here as
  /// well pads for a screen edge that is two widgets away — roughly doubling
  /// the bar's height for no visible reason.
  final bool aboveNavigationBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final theme = Theme.of(context);
    final reconnecting = ref.watch(reconnectingProvider).valueOrNull ?? false;

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
                bottom: !aboveNavigationBar,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MiniProgress(handler: handler, duration: item.duration),
                    InkWell(
                      onTap: () =>
                          ref.read(nowPlayingExpandedProvider.notifier).state =
                              true,
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
                                  // The artist line doubles as the status line
                                  // while reconnecting. A reconnect takes
                                  // seconds and playback has usually just
                                  // stopped, so without it the player sits
                                  // silent and looks broken — and the artist
                                  // is the one thing on this bar nobody is
                                  // reading at that moment.
                                  if (reconnecting)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 10,
                                          height: 10,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Reconnecting…',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                        ),
                                      ],
                                    )
                                  else
                                    Text(
                                      item.artist ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else
                              IconButton(
                                icon: Icon(
                                  playing ? Icons.pause : Icons.play_arrow,
                                ),
                                onPressed: playing
                                    ? handler.pause
                                    : handler.play,
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
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Hairline progress line across the top of the mini player.
///
/// Deliberately not interactive — scrubbing belongs in the expanded player,
/// where the target is big enough to hit accurately. This is an at-a-glance
/// indicator of how far through the track you are.
class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.handler, required this.duration});

  final PlexifyAudioHandler handler;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final totalMs = duration?.inMilliseconds ?? 0;
    if (totalMs <= 0) return const SizedBox(height: 2);

    return StreamBuilder<Duration>(
      stream: handler.player.positionStream,
      builder: (context, snapshot) {
        final positionMs = snapshot.data?.inMilliseconds ?? 0;
        return LinearProgressIndicator(
          value: (positionMs / totalMs).clamp(0.0, 1.0),
          minHeight: 2,
          backgroundColor: Colors.transparent,
        );
      },
    );
  }
}
