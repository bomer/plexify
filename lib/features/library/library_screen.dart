import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart' show AlbumSort;
import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import 'album_detail_screen.dart';
import 'album_list_screen.dart';
import 'artist_detail_screen.dart';
import 'artwork.dart';
import 'playlist_detail_screen.dart';
import 'sync_banner.dart';

/// What the Library tab is currently showing.
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
          // Sorting only applies to the album grid, so the control is hidden
          // elsewhere rather than shown doing nothing.
          if (view == LibraryView.albums) const AlbumSortButton(),
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
            child: switch (view) {
              LibraryView.artists => const _ArtistsView(),
              LibraryView.albums => const AlbumGrid(),
              LibraryView.playlists => const _PlaylistsView(),
            },
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

class _ArtistsView extends ConsumerWidget {
  const _ArtistsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    final theme = Theme.of(context);

    return artists.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (items) {
        if (items.isEmpty) {
          return const _Empty(message: 'No artists cached yet.');
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final artist = items[i];
            return ListTile(
              leading: ClipOval(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Artwork(
                    thumb: artist.thumb,
                    size: 100,
                    icon: Icons.person,
                  ),
                ),
              ),
              title: Text(
                artist.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ArtistDetailScreen(artist: artist),
                ),
              ),
            );
          },
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
              subtitle: Text(
                playlist.itemCount == 1
                    ? '1 track'
                    : '${playlist.itemCount} tracks',
                style: theme.textTheme.bodySmall,
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
