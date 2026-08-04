import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart' show AlbumSort;
import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import 'album_detail_screen.dart';
import 'album_list_screen.dart';
import 'artist_detail_screen.dart';
import '../player/playback_controller.dart';
import 'artwork.dart';
import 'playlist_detail_screen.dart';
import 'star_rating.dart';
import 'sync_banner.dart';

/// What the Library tab is currently showing.
enum LibraryView { artists, albums, playlists, favourites }

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
          if (view == LibraryView.albums) ...[
            const _FavouritesFilterButton(),
            const AlbumSortButton(),
          ],
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
                ButtonSegment(
                  value: LibraryView.favourites,
                  label: Text('Favourites'),
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
                LibraryView.favourites => const _FavouritesView(),
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

/// Favourite albums and tracks — four stars or better.
class _FavouritesView extends ConsumerWidget {
  const _FavouritesView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final albums = ref.watch(favouriteAlbumsProvider).valueOrNull ?? const [];
    final tracks = ref.watch(favouriteTracksProvider).valueOrNull ?? const [];

    if (albums.isEmpty && tracks.isEmpty) {
      return const _Empty(
        message:
            'Nothing rated four stars or higher yet.\n'
            'Rate an album or track and it will show up here.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (albums.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Albums', style: theme.textTheme.titleSmall),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 0.72,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: albums.length,
            itemBuilder: (context, i) {
              final album = albums[i];
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => openAlbum(context, album),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Artwork(thumb: album.thumb),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    StarRating(rating: album.userRating, size: 14),
                  ],
                ),
              );
            },
          ),
        ],

        if (tracks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
            child: Text('Tracks', style: theme.textTheme.titleSmall),
          ),
          for (final track in tracks)
            ListTile(
              dense: true,
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  track.artist,
                  track.album,
                ].where((s) => s.isNotEmpty).join(' — '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: StarRating(rating: track.userRating, size: 14),
              enabled: track.isPlayable,
              onTap: () => ref
                  .read(playbackControllerProvider)
                  ?.playTracks(tracks, startIndex: tracks.indexOf(track)),
            ),
        ],
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
