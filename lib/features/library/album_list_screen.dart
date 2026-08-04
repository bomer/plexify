import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import 'album_detail_screen.dart';
import 'sync_banner.dart';

/// Album grid. Phase 1 fetches straight from Plex on every visit; Phase 2 puts
/// the drift cache behind [albumsProvider] so this stops being network-bound.
class AlbumListScreen extends ConsumerWidget {
  const AlbumListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Albums'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(albumsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          const SyncBanner(),
          Expanded(child: _body(context, ref, albums)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<PlexAlbum>> albums,
  ) {
    return albums.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorView(
        message: '$error',
        onRetry: () => ref.invalidate(albumsProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const _ErrorView(message: 'No albums found in this library.');
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(albumsProvider),
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              // Sizing by extent rather than a fixed column count means
              // the same grid works on a phone and a wide desktop window.
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

class _AlbumTile extends ConsumerWidget {
  const _AlbumTile({required this.album});

  final PlexAlbum album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final client = ref.watch(plexClientProvider);
    final art = client?.artworkUrl(album.thumb);

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
              child: art == null
                  ? _ArtPlaceholder(theme: theme)
                  : Image.network(
                      art,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, _, _) => _ArtPlaceholder(theme: theme),
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

class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.album,
        size: 40,
        color: theme.colorScheme.onSurfaceVariant,
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
