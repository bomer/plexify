import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../../shell/layout.dart';
import '../player/playback_controller.dart';
import 'album_detail_screen.dart';
import 'artwork.dart';
import 'rating_controller.dart';
import 'star_rating.dart';
import 'track_rating_sheet.dart';

/// An artist's discography, oldest first.
class ArtistDetailScreen extends ConsumerWidget {
  const ArtistDetailScreen({required this.artist, super.key});

  final PlexArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final albums = ref.watch(artistAlbumsProvider(artist.ratingKey));

    return Scaffold(
      body: albums.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('$error', textAlign: TextAlign.center),
          ),
        ),
        data: (items) => CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 260,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(artist.title, style: const TextStyle(fontSize: 16)),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Artwork(thumb: artist.thumb, size: 600, icon: Icons.person),
                    // Without a scrim the title is unreadable over light
                    // artwork, which most artist images are.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            theme.colorScheme.surface.withValues(alpha: 0.9),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text(
                      items.length == 1 ? '1 album' : '${items.length} albums',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (items.isNotEmpty)
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                        onPressed: () => _playEverything(ref, items),
                      ),
                  ],
                ),
              ),
            ),

            if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No albums for this artist.')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _AlbumCard(album: items[i]),
                ),
              ),

            // Every track, flat, underneath the albums. For an artist you only
            // have a handful of songs by, scrolling to the track you want beats
            // guessing which album it was on.
            _TrackList(artistRatingKey: artist.ratingKey),
          ],
        ),
      ),
    );
  }

  /// Plays the discography in order, album by album.
  ///
  /// Tracks are gathered up front so the queue is complete before playback
  /// starts — appending as each album resolves would let the first album end
  /// before the second arrived.
  Future<void> _playEverything(WidgetRef ref, List<PlexAlbum> albums) async {
    final controller = ref.read(playbackControllerProvider);
    if (controller == null) return;

    final tracks = <PlexTrack>[];
    for (final album in albums) {
      tracks.addAll(await ref.read(tracksProvider(album.ratingKey).future));
    }
    if (tracks.isNotEmpty) await controller.playTracks(tracks);
  }
}

/// All of an artist's tracks, in discography order.
class _TrackList extends ConsumerWidget {
  const _TrackList({required this.artistRatingKey});

  final String artistRatingKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final compact = isCompactLayout(context);
    final tracks =
        ref.watch(artistTracksProvider(artistRatingKey)).valueOrNull ??
        const <PlexTrack>[];

    if (tracks.isEmpty) return const SliverToBoxAdapter();

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text('Tracks', style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Text(
                  '${tracks.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),

        SliverList.builder(
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final track = tracks[i];
            return ListTile(
              dense: true,
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                track.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // Stars are desktop-only here for the same reason as the album
              // screen: on a phone they crowd out the title and the album.
              trailing: compact
                  ? null
                  : StarRating(
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
              enabled: track.isPlayable,
              // Queues the whole discography from here, so playing one track
              // keeps going through the rest rather than stopping dead.
              onTap: () => ref
                  .read(playbackControllerProvider)
                  ?.playTracks(tracks, startIndex: i),
              onLongPress: compact
                  ? () => showTrackRatingSheet(context, ref, track)
                  : null,
            );
          },
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final PlexAlbum album;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AlbumDetailScreen(album: album),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Artwork(thumb: album.thumb),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          if (album.year != null)
            Text(
              '${album.year}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
