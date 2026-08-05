import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/plex/plex_models.dart';
import '../core/providers.dart';
import '../features/library/playlist_detail_screen.dart';
import 'shell_destination.dart';

/// Desktop sidebar.
///
/// Recent playlists sit directly beneath the destinations rather than behind a
/// Library tab — reaching them in one click was a headline requirement, and
/// burying them one level down is exactly what makes Plexamp slow to navigate.
class Sidebar extends ConsumerWidget {
  const Sidebar({required this.onOpenPlaylist, super.key});

  /// Playlists open inside the active destination's navigator, so the shell
  /// owns the push rather than the sidebar.
  final void Function(PlexPlaylist) onOpenPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(shellDestinationProvider);
    final playlists = ref.watch(recentPlaylistsProvider);

    return Container(
      width: 240,
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
                  onTap: () =>
                      ref.read(shellDestinationProvider.notifier).state =
                          destination,
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
              onTap: () => ref.read(shellDestinationProvider.notifier).state =
                  ShellDestination.settings,
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

class _PlaylistItem extends StatelessWidget {
  const _PlaylistItem({required this.playlist, required this.onTap});

  final PlexPlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        child: Text(
          playlist.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Opens a playlist inside the given navigator.
void openPlaylist(NavigatorState navigator, PlexPlaylist playlist) {
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => PlaylistDetailScreen(playlist: playlist),
    ),
  );
}
