import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio/playback_source.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../player/playback_controller.dart';

/// A playlist's tracks, in playlist order.
///
/// Read-only in v1 — no reordering or editing. Items are fetched on first open
/// and cached, so returning is instant.
class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({required this.playlist, super.key});

  final PlexPlaylist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tracks = ref.watch(playlistTracksProvider(playlist.ratingKey));

    return Scaffold(
      appBar: AppBar(title: Text(playlist.title)),
      body: tracks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('$error', textAlign: TextAlign.center),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('This playlist is empty.'));
          }

          return ListView.builder(
            itemCount: items.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Text(
                        '${items.length} tracks',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                        onPressed: () => ref
                            .read(playbackControllerProvider)
                            ?.playTracks(
                              items,
                              source: PlaybackSource(
                                PlaybackSourceKind.playlist,
                                playlist.ratingKey,
                              ),
                            ),
                      ),
                    ],
                  ),
                );
              }

              final index = i - 1;
              final track = items[index];

              return ListTile(
                dense: true,
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    track.artist,
                    track.album,
                  ].where((s) => s.isNotEmpty).join(' — '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                enabled: track.isPlayable,
                onTap: () => ref
                    .read(playbackControllerProvider)
                    ?.playTracks(
                      items,
                      startIndex: index,
                      source: PlaybackSource(
                        PlaybackSourceKind.playlist,
                        playlist.ratingKey,
                      ),
                    ),
              );
            },
          );
        },
      ),
    );
  }
}
