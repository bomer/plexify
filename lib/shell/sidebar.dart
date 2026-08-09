import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/plex/plex_models.dart';
import '../core/providers.dart';
import '../features/library/artwork.dart';
import '../features/library/playlist_detail_screen.dart';
import 'shell_destination.dart';

/// Desktop sidebar.
///
/// Recent playlists sit directly beneath the destinations rather than behind a
/// Library tab — reaching them in one click was a headline requirement, and
/// burying them one level down is exactly what makes Plexamp slow to navigate.
class Sidebar extends ConsumerWidget {
  const Sidebar({
    required this.onOpenPlaylist,
    required this.onSelectDestination,
    super.key,
  });

  /// Playlists open inside the active destination's navigator, so the shell
  /// owns the push rather than the sidebar.
  final void Function(PlexPlaylist) onOpenPlaylist;

  /// Selecting a destination is the shell's job for the same reason.
  ///
  /// It used to set the provider here, which meant tapping the destination you
  /// were already on did nothing — and since each tab owns its own navigator,
  /// an album opened from a Home shelf lives on Home's stack. Pressing Home
  /// from there changed no state and so moved nothing. Only the shell holds the
  /// navigator keys, so only the shell can pop one.
  final void Function(ShellDestination) onSelectDestination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(shellDestinationProvider);
    final playlists = ref.watch(recentPlaylistsProvider);

    return Container(
      // Widened when the playlist thumbnails grew from 28 to 48. The artwork
      // takes that width out of the title beside it, and at 240 the longest
      // real playlist names started truncating, which is a poor trade for a
      // picture. Nothing else on this screen notices the extra 24 pixels.
      width: 264,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Icon(
                    Icons.graphic_eq,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text('Plexify', style: theme.textTheme.titleMedium),
                ],
              ),
            ),

            // Settings is deliberately excluded here and pinned to the bottom
            // instead: it is the one destination you reach occasionally, and
            // sitting it above the playlists would push the thing you reach
            // constantly further down.
            for (final destination in ShellDestination.values)
              if (destination != ShellDestination.settings)
                _NavItem(
                  label: destination.label,
                  icon: destination == current
                      ? destination.selectedIcon
                      : destination.icon,
                  selected: destination == current,
                  onTap: () => onSelectDestination(destination),
                ),

            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Recent playlists',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            Expanded(
              child: playlists.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (items) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'No playlists yet',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, i) => _PlaylistItem(
                      playlist: items[i],
                      onTap: () => onOpenPlaylist(items[i]),
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 1),
            _NavItem(
              label: ShellDestination.settings.label,
              icon: current == ShellDestination.settings
                  ? ShellDestination.settings.selectedIcon
                  : ShellDestination.settings.icon,
              selected: current == ShellDestination.settings,
              onTap: () => onSelectDestination(ShellDestination.settings),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colour),
            const SizedBox(width: 14),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colour,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One playlist in the sidebar, with the mosaic Plex generates for it.
///
/// **The artwork is the point.** A dozen playlists as plain text rows is the
/// most monotonous region on the screen: identical size, identical weight,
/// identical colour, and the only thing distinguishing them is a word you have
/// to read. Artwork makes the list scannable by shape and colour instead, which
/// is how anyone actually finds a playlist they use often.
///
/// Two lines rather than one, so the row is the height of its own artwork
/// instead of a tall thumbnail with a short label floating beside it.
class _PlaylistItem extends StatelessWidget {
  const _PlaylistItem({required this.playlist, required this.onTap});

  final PlexPlaylist playlist;
  final VoidCallback onTap;

  /// Edge of the thumbnail.
  ///
  /// Large enough that a mosaic of four sleeves is four recognisable sleeves
  /// rather than a smudge, which is the entire reason for showing it. At 28 it
  /// was a colour swatch: better than nothing, and not actually a picture of
  /// anything.
  static const _thumb = 48.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: _thumb,
                height: _thumb,
                // Requested at a size the shelves also use rather than at 48,
                // so this shares their cache entry instead of making Plex
                // transcode a third copy of every playlist mosaic.
                child: Artwork(
                  thumb: playlist.thumb,
                  size: 300,
                  icon: Icons.queue_music,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Two lines against a 48px square, so the row is the height of its
            // artwork rather than a tall thumbnail with a short label floating
            // beside it.
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    playlistSubtitle(playlist),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The second line under a playlist's name in the sidebar.
///
/// Two facts worth the room, in the order they are worth it. **Smart comes
/// first** because it changes what the row means: those contents are generated
/// from rules, so what is in there today is not what was in there last week,
/// and that is the reason to open one. The count is the ordinary detail.
///
/// Falls back to naming the kind rather than showing an empty line, so every
/// row is the same height. A playlist can legitimately report no count: Plex
/// omits `leafCount` on some responses, and the sidebar renders from whatever
/// the last sync stored.
String playlistSubtitle(PlexPlaylist playlist) {
  final count = playlist.itemCount;
  final tracks = count > 0 ? '$count ${count == 1 ? 'track' : 'tracks'}' : null;

  if (playlist.smart) return tracks == null ? 'Smart' : 'Smart · $tracks';
  return tracks ?? 'Playlist';
}

/// Opens a playlist inside the given navigator.
void openPlaylist(NavigatorState navigator, PlexPlaylist playlist) {
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => PlaylistDetailScreen(playlist: playlist),
    ),
  );
}
