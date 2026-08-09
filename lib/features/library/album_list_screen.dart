import 'package:flutter/material.dart';
// ScrollCacheExtent lives in the rendering layer and is not re-exported by
// material.dart.
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import 'album_detail_screen.dart';
import 'album_cover.dart';
import 'cover_frame.dart';

/// The album grid.
///
/// Chrome-free: [LibraryScreen] supplies the app bar, view toggle and sync
/// banner, so this is only the content and can be embedded anywhere.
class AlbumGrid extends ConsumerWidget {
  const AlbumGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);

    return albums.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorView(
        message: '$error',
        onRetry: () => ref.invalidate(albumsFallbackProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const _ErrorView(message: 'No albums found in this library.');
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(albumsFallbackProvider),
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            // A full screen of rows built ahead of the viewport, which on this
            // grid means a screen of artwork already fetching. Building a tile
            // is what starts its image load, so this *is* the prefetch — the
            // framework has the machinery, and a scroll listener calling
            // precacheImage would only duplicate it. Expressed against the
            // viewport rather than in pixels so a tall desktop window gets
            // proportionally more, not the same as a phone.
            scrollCacheExtent: const ScrollCacheExtent.viewport(1),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              // Sizing by extent rather than a fixed column count means the
              // same grid works on a phone and a wide desktop window.
              maxCrossAxisExtent: 200,
              childAspectRatio: 0.75,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _AlbumTile(album: items[i]),
          ),
        );
      },
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.album});

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
            child: CoverFrame(
              child: LayoutBuilder(
                builder: (context, c) =>
                    AlbumCover(album: album, size: c.maxWidth),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            album.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
