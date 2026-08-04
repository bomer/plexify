import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/sync/library_sync.dart';

/// Slim progress strip shown while the library cache is filling.
///
/// Occupies no space once sync finishes. Browsing is never blocked on it — the
/// first sync of a large library takes a while, and making someone stare at a
/// modal spinner for that would be worse than the problem it solves.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(librarySyncProvider);

    final progress = async.valueOrNull;
    if (progress == null || progress.phase == SyncPhase.done) {
      return const SizedBox.shrink();
    }

    if (progress.phase == SyncPhase.failed) {
      return _Strip(
        color: theme.colorScheme.errorContainer,
        child: Row(
          children: [
            Icon(
              Icons.cloud_off,
              size: 16,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                // Whatever landed is still usable, so this is informational
                // rather than an error state that blocks anything.
                'Library sync interrupted — will resume',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final label = switch (progress.phase) {
      SyncPhase.artists => 'Syncing artists',
      SyncPhase.albums => 'Syncing albums',
      SyncPhase.tracks => 'Syncing tracks',
      _ => 'Syncing library',
    };

    final counts = progress.total > 0
        ? ' ${progress.done} of ${progress.total}'
        : '';

    return _Strip(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$label$counts…', style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              // Null while the total is unknown gives an indeterminate bar
              // rather than a misleading 0%.
              value: progress.fraction,
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: child,
      ),
    );
  }
}
