import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../player/playback_controller.dart';
import 'album_detail_screen.dart';
import 'artwork.dart';

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
