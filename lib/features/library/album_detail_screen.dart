import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../../shell/layout.dart';
import '../player/playback_controller.dart';
import 'rating_controller.dart';
import 'artwork.dart';
import 'star_rating.dart';
import 'track_rating_sheet.dart';

/// Track list for one album. Tapping a track replaces the queue and plays from
/// that point — the flat replace semantics agreed for v1.
class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({required this.album, super.key});

  final PlexAlbum album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tracks = ref.watch(tracksProvider(album.ratingKey));
    final client = ref.watch(plexClientProvider);
    final art = client?.artworkUrl(album.thumb, width: 600, height: 600);
    final compact = isCompactLayout(context);

    return Scaffold(
      appBar: AppBar(title: Text(album.title)),
      body: tracks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('$error', textAlign: TextAlign.center),
          ),
        ),
        data: (items) => ListView.builder(
          itemCount: items.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return _Header(album: album, artUrl: art, theme: theme);
            }
            final index = i - 1;
            final track = items[index];

            return ListTile(
              leading: SizedBox(
                width: 28,
                child: Text(
                  '${track.index}',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: track.isPlayable
                  ? null
                  : Text(
                      'Unavailable',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Five stars per row eats most of a phone's width and pushes
                  // the title — the thing being scanned for — into an ellipsis.
                  // Long press opens the same rating instead.
                  if (!compact)
                    StarRating(
                      rating: track.userRating,
                      size: 15,
                      onRate: (stars) async {
                        final ok = await ref
                            .read(ratingControllerProvider)
                            ?.rateTrack(track, stars);
                        if (ok == false && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not save rating to Plex'),
                            ),
                          );
                        }
                      },
                    ),
                  if (!compact) const SizedBox(width: 8),
                  Text(
                    _formatDuration(track.duration),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              enabled: track.isPlayable,
              onTap: () {
                final controller = ref.read(playbackControllerProvider);
                controller?.playTracks(items, startIndex: index);
              },
              onLongPress: compact
                  ? () => showTrackRatingSheet(context, ref, track)
                  : null,
            );
          },
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.album,
    required this.artUrl,
    required this.theme,
  });

  final PlexAlbum album;
  final String? artUrl;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 120,
              height: 120,
              // Through the cache like every other surface. `Image.network`
              // here meant the one image most likely to be looked at twice
              // was the one never stored, re-fetched on every open — and it
              // could not draw at all while disconnected.
              child: Artwork(thumb: album.thumb, size: 600),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(album.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  album.artist,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (album.year != null) ...[
                  const SizedBox(height: 2),
                  Text('${album.year}', style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 6),

                // Reads the album back out of the cache so the stars reflect
                // the optimistic write immediately, rather than the snapshot
                // this screen was pushed with.
                Consumer(
                  builder: (context, ref, _) {
                    final live =
                        ref
                            .watch(albumsProvider)
                            .valueOrNull
                            ?.where((a) => a.ratingKey == album.ratingKey)
                            .firstOrNull ??
                        album;

                    return StarRating(
                      rating: live.userRating,
                      onRate: (stars) async {
                        final controller = ref.read(ratingControllerProvider);
                        final ok = await controller?.rateAlbum(live, stars);
                        if (ok == false && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not save rating to Plex'),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),

                const SizedBox(height: 10),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                  onPressed: () async {
                    final items = await ref.read(
                      tracksProvider(album.ratingKey).future,
                    );
                    ref.read(playbackControllerProvider)?.playTracks(items);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
