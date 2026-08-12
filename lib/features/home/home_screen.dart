import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/shelf_item.dart';
import '../../core/discovery/discovery.dart';
import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../../shell/horizontal_scroll.dart';
import '../../shell/layout.dart';
import '../settings/sync_actions.dart';
import '../library/album_detail_screen.dart';
import '../library/album_cover.dart';
import '../library/artist_detail_screen.dart';
import '../radio/radio_action.dart';
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
                  // Above the server's rows, because these are records already
                  // chosen rather than suggested, and a shelf of them is worth
                  // more than any recommendation underneath it.
                  _Shelf(
                    title: 'Favourites',
                    items: _albums(ref.watch(favouriteAlbumsProvider)),
                    // Nothing rated yet is the normal state on day one, and an
                    // empty row would read as broken rather than unused.
                    hideWhenEmpty: true,
                  ),
                  // Whatever the server publishes for this library, in its
                  // order and under its own titles. More by an artist, more in
                  // a genre, most played in a month, top albums from a decade,
                  // and whatever a later Plex adds without this needing to
                  // know. Absent rather than empty while unreachable, which is
                  // the trade for not computing them here.
                  for (final shelf
                      in ref.watch(hubShelvesProvider).valueOrNull ??
                          const <DiscoveryShelf>[])
                    _Shelf(
                      title: shelf.title,
                      items: AsyncValue.data(shelf.items),
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
AsyncValue<List<ShelfItem>> _albums(AsyncValue<List<PlexAlbum>> albums) =>
    albums.whenData(
      // Zero for the timestamp: these shelves have their own order — added
      // date, rating — and never sort on it.
      (list) => [for (final a in list) ShelfItem.album(a, 0)],
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
      items: AsyncValue.data(value.items),
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
  final AsyncValue<List<ShelfItem>> items;
  final bool hideWhenEmpty;
  final double tileSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = items.valueOrNull ?? const <ShelfItem>[];

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

class _ShelfTile extends ConsumerWidget {
  const _ShelfTile({required this.entry, required this.size});

  final ShelfItem entry;
  final double size;

  /// **A station plays; everything else opens.** Its key is a play queue source
  /// rather than a path, so there is no screen to push and nothing to fetch: the
  /// server decides what is in it at the moment you ask.
  Future<void> _tap(BuildContext context, WidgetRef ref) async {
    if (entry.station case final station?) {
      return playStation(context, ref, station);
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (entry) {
          ShelfItem(playlist: final playlist?) => PlaylistDetailScreen(
            playlist: playlist,
          ),
          ShelfItem(artist: final artist?) => ArtistDetailScreen(
            artist: artist,
          ),
          _ => AlbumDetailScreen(album: entry.album!),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final album = entry.album;

    return SizedBox(
      width: size,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _tap(context, ref),
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
                        icon: switch (entry) {
                          ShelfItem(isArtist: true) => Icons.person,
                          ShelfItem(isStation: true) => Icons.radio,
                          _ => Icons.queue_music,
                        },
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
