import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../../shell/horizontal_scroll.dart';
import '../../shell/layout.dart';
import '../settings/sync_actions.dart';
import '../library/album_detail_screen.dart';
import '../library/album_cover.dart';
import '../library/sync_banner.dart';

/// Landing screen: what you were listening to, and what's new.
///
/// Everything here reads from the local cache, so it renders instantly on cold
/// start rather than waiting on the network.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);
    final recentlyAdded = ref.watch(recentlyAddedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Home'), actions: const [SyncActions()]),
      body: Column(
        children: [
          const SyncBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async =>
                  ref.read(syncSchedulerProvider)?.refreshNow(),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _Shelf(
                    title: 'Jump back in',
                    albums: recentlyPlayed,
                    // Hidden entirely rather than shown empty: on a fresh install
                    // nothing has been played, and an empty row reads as broken.
                    hideWhenEmpty: true,
                  ),
                  _Shelf(title: 'Recently added', albums: recentlyAdded),
                  _Shelf(
                    title: 'Favourites',
                    albums: ref.watch(favouriteAlbumsProvider),
                    // Nothing rated yet is the normal state on day one, and an
                    // empty row would read as broken rather than unused.
                    hideWhenEmpty: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontally scrolling row of albums.
class _Shelf extends ConsumerWidget {
  const _Shelf({
    required this.title,
    required this.albums,
    this.hideWhenEmpty = false,
  });

  final String title;
  final AsyncValue<List<PlexAlbum>> albums;
  final bool hideWhenEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = albums.valueOrNull ?? const <PlexAlbum>[];

    if (items.isEmpty) {
      if (hideWhenEmpty || albums.isLoading) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Text(
          'Nothing here yet',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Text(title, style: theme.textTheme.titleMedium),
        ),
        SizedBox(
          // Taller on desktop by exactly the height the scrollbar takes, so
          // adding it does not crop the covers it sits under.
          height: isCompactLayout(context) ? 208 : 220,
          child: HorizontalScroll(
            builder: (context, controller) => ListView.separated(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) => _ShelfTile(album: items[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShelfTile extends StatelessWidget {
  const _ShelfTile({required this.album});

  final PlexAlbum album;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 150,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AlbumDetailScreen(album: album),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: AlbumCover(album: album, size: 150),
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
      ),
    );
  }
}
