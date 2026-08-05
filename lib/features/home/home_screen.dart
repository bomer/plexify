import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/recently_played.dart';
import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../../shell/horizontal_scroll.dart';
import '../../shell/layout.dart';
import '../settings/sync_actions.dart';
import '../library/album_detail_screen.dart';
import '../library/album_cover.dart';
import '../library/artwork.dart';
import '../library/playlist_detail_screen.dart';
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
                    items: recentlyPlayed,
                    // Hidden entirely rather than shown empty: on a fresh install
                    // nothing has been played, and an empty row reads as broken.
                    hideWhenEmpty: true,
                  ),
                  _Shelf(
                    title: 'Recently added',
                    items: _albums(recentlyAdded),
                  ),
                  _Shelf(
                    title: 'Favourites',
                    items: _albums(ref.watch(favouriteAlbumsProvider)),
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

/// Lifts an album-only shelf into the mixed type the row now speaks.
///
/// Only "Jump back in" holds two kinds of thing; the rest are albums by
/// definition, and giving them their own widget would mean two copies of the
/// tile to keep in step.
AsyncValue<List<RecentlyPlayed>> _albums(AsyncValue<List<PlexAlbum>> albums) =>
    albums.whenData(
      // Zero for the timestamp: these shelves have their own order — added
      // date, rating — and never sort on it.
      (list) => [for (final a in list) RecentlyPlayed.album(a, 0)],
    );

/// A horizontally scrolling row of albums and playlists.
class _Shelf extends ConsumerWidget {
  const _Shelf({
    required this.title,
    required this.items,
    this.hideWhenEmpty = false,
  });

  final String title;
  final AsyncValue<List<RecentlyPlayed>> items;
  final bool hideWhenEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = items.valueOrNull ?? const <RecentlyPlayed>[];

    if (entries.isEmpty) {
      if (hideWhenEmpty || items.isLoading) return const SizedBox.shrink();
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
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) => _ShelfTile(entry: entries[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShelfTile extends StatelessWidget {
  const _ShelfTile({required this.entry});

  final RecentlyPlayed entry;

  void _open(BuildContext context) {
    final playlist = entry.playlist;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => playlist != null
            ? PlaylistDetailScreen(playlist: playlist)
            : AlbumDetailScreen(album: entry.album!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final album = entry.album;

    return SizedBox(
      width: 150,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _open(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              // Only albums get the hover play button. A playlist's tracks are
              // not loaded until it is opened, so playing one from here would
              // mean a network round trip behind a hover — and a smart
              // playlist has to be revalidated before it can be trusted at
              // all.
              child: album != null
                  ? AlbumCover(album: album, size: 150)
                  : SizedBox(
                      width: 150,
                      height: 150,
                      child: Artwork(
                        thumb: entry.thumb,
                        size: 600,
                        icon: Icons.queue_music,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              entry.subtitle,
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
