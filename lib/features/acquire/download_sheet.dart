import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_models.dart';
import '../../core/providers.dart';
import '../../core/qbit/torrent_ranking.dart';
import '../settings/qbittorrent_screen.dart';
import 'acquire_controller.dart';

/// Queues a record in one tap, and only when that is safe.
///
/// **The compromise this encodes.** "One click to download" is the thing worth
/// having on an artist page, and blindly adding the top-seeded search hit is not
/// a safe way to provide it: torrent search matches filenames, so the most
/// popular result for an album is routinely a different record that shares a
/// word. Seeder count measures popularity, never correctness.
///
/// So the button searches, and adds *only* if a result's filename actually names
/// this artist and this album ([bestAutomaticChoice]). When one does, it is
/// queued and the snackbar says what — with **Change** open beside it, because
/// the user should be able to see and undo a decision made for them. When none
/// does, nothing is added and the list opens instead. One tap in the common
/// case, and never one tap away from the wrong album.
Future<void> acquire(
  BuildContext context,
  WidgetRef ref,
  CatalogRelease release,
) async {
  final controller = await ref.read(acquireControllerProvider.future);
  if (!context.mounted) return;
  if (controller == null) {
    _notConfigured(context);
    return;
  }

  // Searching runs plugins across several trackers and takes seconds, so it
  // gets a dialog rather than an unexplained pause on a button.
  final outcome = await _whileSearching(
    context,
    release,
    () => controller.queueBest(release),
  );
  if (!context.mounted || outcome == null) return;

  if (outcome.error != null) {
    _report(context, outcome.error!);
    if (outcome.candidates.isNotEmpty) {
      await showAcquireSheet(context, ref, release, prefetched: outcome);
    }
    return;
  }

  final queued = outcome.queued;
  if (queued == null) {
    // Found things, none of them confidently this record. Deliberately not a
    // "best guess" — showing the list is the honest answer and costs one tap.
    await showAcquireSheet(context, ref, release, prefetched: outcome);
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Queued ${queued.result.fileName}'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Change',
        onPressed: () =>
            unawaitedSheet(context, ref, release, prefetched: outcome),
      ),
    ),
  );
}

/// Fire-and-forget wrapper so a `SnackBarAction` can open the sheet.
void unawaitedSheet(
  BuildContext context,
  WidgetRef ref,
  CatalogRelease release, {
  AcquireOutcome? prefetched,
}) {
  showAcquireSheet(context, ref, release, prefetched: prefetched);
}

/// Shows every search hit, ranked, and adds whichever one is tapped.
Future<void> showAcquireSheet(
  BuildContext context,
  WidgetRef ref,
  CatalogRelease release, {
  AcquireOutcome? prefetched,
}) async {
  final controller = await ref.read(acquireControllerProvider.future);
  if (!context.mounted) return;
  if (controller == null) {
    _notConfigured(context);
    return;
  }

  // Reused when the caller already searched, which is the whole point of
  // `prefetched`: opening the list after an automatic attempt must not run the
  // same twenty-second search a second time.
  final outcome =
      prefetched ??
      await _whileSearching(context, release, () => controller.find(release));
  if (!context.mounted || outcome == null) return;

  if (outcome.candidates.isEmpty) {
    _report(
      context,
      outcome.error ??
          'Nothing found for ${release.artist} — ${release.title}.',
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ResultList(
      release: release,
      candidates: outcome.candidates,
      onPick: (picked) async {
        final error = await controller.add(picked.result);
        if (!context.mounted) return;
        Navigator.of(context).pop();
        _report(
          context,
          error ?? 'Queued ${picked.result.fileName}',
          isError: error != null,
        );
      },
    ),
  );
}

/// Runs [work] behind a dialog that can be cancelled by walking away from it.
///
/// Returns null if the sheet was dismissed before the search finished, which
/// the callers treat as "do nothing" — the search itself is already bounded by
/// a timeout in the client.
Future<AcquireOutcome?> _whileSearching(
  BuildContext context,
  CatalogRelease release,
  Future<AcquireOutcome> Function() work,
) async {
  var dismissed = false;
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text('Searching for ${release.title}…')),
        ],
      ),
    ),
  ).then((_) => dismissed = true);

  final outcome = await work();
  if (context.mounted && !dismissed) Navigator.of(context).pop();
  await dialog;
  return dismissed ? null : outcome;
}

void _notConfigured(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('qBittorrent is not set up yet'),
      action: SnackBarAction(
        label: 'Settings',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const QbittorrentScreen()),
        ),
      ),
    ),
  );
}

void _report(BuildContext context, String message, {bool isError = false}) {
  final theme = Theme.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? theme.colorScheme.errorContainer : null,
    ),
  );
}

class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.release,
    required this.candidates,
    required this.onPick,
  });

  final CatalogRelease release;
  final List<RankedTorrent> candidates;
  final ValueChanged<RankedTorrent> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confident = candidates.where((c) => c.matchesRelease).length;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                '${release.artist} — ${release.title}',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                confident == 0
                    // Said plainly rather than hidden. Every result here shares
                    // words with the album and none of them names it, which is
                    // exactly when a hasty tap costs a wrong download.
                    ? 'No result clearly names this album. Check the filenames.'
                    : '$confident of ${candidates.length} name this album',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: candidates.length,
                itemBuilder: (context, i) {
                  final candidate = candidates[i];
                  return ListTile(
                    leading: Icon(
                      candidate.matchesRelease
                          ? Icons.check_circle_outline
                          : Icons.help_outline,
                      color: candidate.matchesRelease
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      candidate.result.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(_describe(candidate)),
                    onTap: () => onPick(candidate),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _describe(RankedTorrent candidate) {
    final parts = <String>[
      if (candidate.result.hasSeeders)
        '${candidate.result.seeders} seeders'
      else
        'seeders unknown',
      if (candidate.result.hasSize) formatBytes(candidate.result.sizeBytes),
      if (candidate.format != AudioFormat.unknown) candidate.format.name,
    ];
    return parts.join(' · ');
  }
}

/// Bytes as something readable. Shared with the downloads screen.
String formatBytes(int bytes) {
  if (bytes <= 0) return '—';
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).round()} MB';
  }
  return '${(bytes / 1024).round()} KB';
}
