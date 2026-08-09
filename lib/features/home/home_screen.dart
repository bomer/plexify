import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/recently_played.dart';
import '../../core/discovery/discovery.dart';
import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../../shell/horizontal_scroll.dart';
import '../../shell/layout.dart';
import '../settings/sync_actions.dart';
import '../library/album_detail_screen.dart';
import '../library/album_cover.dart';
import '../library/artwork.dart';
import '../library/cover_frame.dart';
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
                    // The one row with larger tiles, so the page opens on
                    // something rather than on the first of eight identical
                    // bands. Deliberately only one: a second would be a
                    // competing emphasis, and past that the variation is just
                    // noise.
                    tileSize: _leadTile,
                  ),
                  _Shelf(
                    title: 'Recently added',
                    items: _albums(recentlyAdded),
                  ),
                  // The discovery rows, in the order they are most likely to
                  // have something in them. Each is absent rather than empty
                  // when it has nothing, so the screen closes up around the
                  // gap instead of showing four "Nothing here yet" labels on a
                  // fresh install or an offline start.
                  _DiscoveryShelf(shelf: ref.watch(moreByArtistShelfProvider)),
                  _DiscoveryShelf(shelf: ref.watch(mostPlayedShelfProvider)),
                  _DiscoveryShelf(shelf: ref.watch(genreShelfProvider)),
                  _Shelf(
                    title: 'Favourites',
                    items: _albums(ref.watch(favouriteAlbumsProvider)),
                    // Nothing rated yet is the normal state on day one, and an
                    // empty row would read as broken rather than unused.
                    hideWhenEmpty: true,
                  ),
                  _DiscoveryShelf(
                    shelf: ref.watch(buriedTreasureShelfProvider),
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

/// Cover edge on the first shelf, and on every other one.
const double _leadTile = 196;
const double _tile = 150;

/// Space a tile needs under its cover for two lines of text, plus the
/// scrollbar's height on desktop so adding it does not crop the covers above.
double _shelfChrome(bool compact) => compact ? 58 : 70;

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

/// A row whose title the provider worked out, and which is not there at all
/// when there is nothing to put in it.
///
/// Separate from [_Shelf] because the two differ in the thing that matters:
/// a fixed shelf that is empty is worth saying so about, since "Recently added"
/// with nothing under it means the sync has not run. A discovery shelf that is
/// empty has no title to show either, and saying "Nothing here yet" under a
/// heading nobody asked for is worse than silence.
class _DiscoveryShelf extends StatelessWidget {
  const _DiscoveryShelf({required this.shelf});

  final AsyncValue<DiscoveryShelf?> shelf;

  @override
  Widget build(BuildContext context) {
    final value = shelf.valueOrNull;
    if (value == null) return const SizedBox.shrink();
    return _Shelf(
      title: value.title,
      items: AsyncValue.data([
        for (final album in value.albums) RecentlyPlayed.album(album, 0),
      ]),
      hideWhenEmpty: true,
    );
  }
}

/// A horizontally scrolling row of albums and playlists.
class _Shelf extends ConsumerWidget {
  const _Shelf({
    required this.title,
    required this.items,
    this.hideWhenEmpty = false,
    this.tileSize = _tile,
  });

  final String title;
  final AsyncValue<List<RecentlyPlayed>> items;
  final bool hideWhenEmpty;
  final double tileSize;

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
          // More above than below, so the heading binds to the row under it
          // rather than floating equidistant between two.
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
        SizedBox(
          height: tileSize + _shelfChrome(isCompactLayout(context)),
          child: HorizontalScroll(
            builder: (context, controller) => ListView.separated(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) =>
                  _ShelfTile(entry: entries[i], size: tileSize),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShelfTile extends StatelessWidget {
  const _ShelfTile({required this.entry, required this.size});

  final RecentlyPlayed entry;
  final double size;

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
      width: size,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _open(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverFrame(
              // Only albums get the hover play button. A playlist's tracks are
              // not loaded until it is opened, so playing one from here would
              // mean a network round trip behind a hover — and a smart
              // playlist has to be revalidated before it can be trusted at
              // all.
              child: album != null
                  ? AlbumCover(album: album, size: size)
                  : SizedBox(
                      width: size,
                      height: size,
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
              // Semibold, matching the sidebar. A cover, a name and a detail
              // under it is the same shape everywhere in this app, and weight
              // is what separates the name from the detail; colour alone
              // leaves both reading as labels.
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
