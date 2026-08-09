import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart' show AlbumSort, PlaylistSort;
import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import 'album_detail_screen.dart';
import 'album_list_screen.dart';
import 'artist_detail_screen.dart';
import 'artist_list.dart';
import 'artwork.dart';
import '../settings/sync_actions.dart';
import 'playlist_detail_screen.dart';
import 'sync_banner.dart';

/// What the Library tab is currently showing.
///
/// **There is no favourites view.** There was, and it was a fourth thing to
/// choose between that answered a question the other three already answer:
/// Artists and Albums each carry a favourites filter, so "show me my
/// favourites" is a toggle on the list you are already looking at rather than a
/// separate place to go to. See [_FavouritesFilterButton].
enum LibraryView { artists, albums, playlists }

final libraryViewProvider = StateProvider<LibraryView>(
  (ref) => LibraryView.albums,
);

/// The Library tab: artists, albums or playlists.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(libraryViewProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          // These only apply to the album grid, so they are hidden elsewhere
          // rather than shown doing nothing.
          if (view == LibraryView.artists) const _ArtistFavouritesButton(),
          if (view == LibraryView.albums) ...[
            const _FavouritesFilterButton(),
            const AlbumSortButton(),
          ],
          if (view == LibraryView.playlists) const _PlaylistSortButton(),
          const SyncActions(),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SegmentedButton<LibraryView>(
              segments: const [
                ButtonSegment(
                  value: LibraryView.artists,
                  label: Text('Artists'),
                ),
                ButtonSegment(value: LibraryView.albums, label: Text('Albums')),
                ButtonSegment(
                  value: LibraryView.playlists,
                  label: Text('Playlists'),
                ),
              ],
              selected: {view},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  ref.read(libraryViewProvider.notifier).state =
                      selection.first,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          const SyncBanner(),
          Expanded(
            // One gesture does both halves of the job: asks Plex to rescan the
            // library, then pulls whatever changed. Previously that meant
            // triggering a scan in Plex, waiting, and re-checking here.
            child: RefreshIndicator(
              onRefresh: () async =>
                  ref.read(syncSchedulerProvider)?.refreshNow(),
              child: switch (view) {
                LibraryView.artists => const _ArtistsView(),
                LibraryView.albums => const AlbumGrid(),
                LibraryView.playlists => const _PlaylistsView(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Sort control for the album grid.
class AlbumSortButton extends ConsumerWidget {
  const AlbumSortButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<AlbumSort>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort),
      initialValue: ref.watch(albumSortProvider),
      onSelected: (value) => ref.read(albumSortProvider.notifier).state = value,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: AlbumSort.recentlyAdded,
          child: Text('Recently added'),
        ),
        PopupMenuItem(value: AlbumSort.title, child: Text('Title A–Z')),
        PopupMenuItem(value: AlbumSort.artist, child: Text('Artist A–Z')),
      ],
    );
  }
}

/// Sort control for the playlist list.
///
/// The two name orders put smart playlists first; recent does not. See
/// `AppDatabase._playlistOrder` for why that is not simply inconsistent.
class _PlaylistSortButton extends ConsumerWidget {
  const _PlaylistSortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<PlaylistSort>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort),
      initialValue: ref.watch(playlistSortProvider),
      onSelected: (value) =>
          ref.read(playlistSortProvider.notifier).state = value,
      itemBuilder: (context) => const [
        PopupMenuItem(value: PlaylistSort.recent, child: Text('Recent')),
        PopupMenuItem(value: PlaylistSort.titleAsc, child: Text('Name A–Z')),
        PopupMenuItem(value: PlaylistSort.titleDesc, child: Text('Name Z–A')),
      ],
    );
  }
}

/// Toggles the album grid between everything and favourites only.
class _FavouritesFilterButton extends ConsumerWidget {
  const _FavouritesFilterButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(albumFavouritesOnlyProvider);

    return IconButton(
      tooltip: active ? 'Showing favourites' : 'Show favourites only',
      isSelected: active,
      icon: const Icon(Icons.star_border),
      selectedIcon: const Icon(Icons.star),
      onPressed: () =>
          ref.read(albumFavouritesOnlyProvider.notifier).state = !active,
    );
  }
}

/// The same filter for the Artists list.
///
/// Its own provider rather than sharing the album one: filtering the artists
/// list should not silently filter the album grid you switch to next.
class _ArtistFavouritesButton extends ConsumerWidget {
  const _ArtistFavouritesButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(artistFavouritesOnlyProvider);

    return IconButton(
      tooltip: active ? 'Showing favourites' : 'Show favourites only',
      isSelected: active,
      icon: const Icon(Icons.star_border),
      selectedIcon: const Icon(Icons.star),
      onPressed: () =>
          ref.read(artistFavouritesOnlyProvider.notifier).state = !active,
    );
  }
}

class _ArtistsView extends ConsumerWidget {
  const _ArtistsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);

    return artists.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (items) {
        if (items.isEmpty) {
          return const _Empty(message: 'No artists cached yet.');
        }
        return ArtistList(
          artists: items,
          onOpen: (artist) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ArtistDetailScreen(artist: artist),
            ),
          ),
        );
      },
    );
  }
}

class _PlaylistsView extends ConsumerWidget {
  const _PlaylistsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final theme = Theme.of(context);

    return playlists.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (items) {
        if (items.isEmpty) {
          return const _Empty(message: 'No playlists on this server.');
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final playlist = items[i];
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Artwork(
                    thumb: playlist.thumb,
                    size: 120,
                    icon: Icons.queue_music,
                  ),
                ),
              ),
              title: Text(
                playlist.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Row(
                children: [
                  Text(
                    playlist.itemCount == 1
                        ? '1 track'
                        : '${playlist.itemCount} tracks',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (playlist.smart) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.auto_awesome,
                      size: 12,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Smart',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlaylistDetailScreen(playlist: playlist),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

/// Opens an album from anywhere in the library.
void openAlbum(BuildContext context, PlexAlbum album) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => AlbumDetailScreen(album: album)),
  );
}
