import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/acquire/acquire_queue.dart';
import '../../core/acquire/download_source.dart';
import '../../core/providers.dart';
import '../settings/download_source_screen.dart';

/// What the chosen source is currently bringing in.
///
/// Read-only on purpose. This is a music player that can ask for a record, not
/// a torrent client and not a Soulseek client: pausing, reprioritising and
/// deleting all exist perfectly well in qBittorrent's and slskd's own
/// interfaces, and rebuilding them here would mean keeping a second copy in
/// step for no gain.
///
/// What it *is* for is answering the question the flow creates, "I asked for
/// that album twenty minutes ago, where is it?", which otherwise means opening
/// another app to find out.
///
/// **Not a history.** Nothing here is persisted: it mirrors whatever the server
/// currently holds, so an item disappears from this screen when it is cleared
/// there. A torrent stays visible while qBittorrent seeds it; a Soulseek folder
/// stays until the transfers are removed.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    // The monitor idles at a minute between polls when nothing is downloading,
    // so without this the screen could open onto a list that is a minute old.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(downloadMonitorProvider)?.pollNow();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monitor = ref.watch(downloadMonitorProvider);
    final downloads = ref.watch(downloadsProvider);
    final kind = ref.watch(downloadSourceKindProvider);
    final requests =
        ref.watch(acquireRequestsProvider).valueOrNull ??
        const <AcquireRequest>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            tooltip: '${kind.label} settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DownloadSourceScreen(kind: kind),
              ),
            ),
          ),
        ],
      ),
      body: monitor == null
          ? _NotConfigured(kind: kind)
          : RefreshIndicator(
              onRefresh: () async => monitor.pollNow(),
              child: ListView(
                children: [
                  if (monitor.lastError != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        monitor.lastError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  // **Above the transfers, because this is the part that is
                  // still being worked out.** A request here has not reached
                  // the server yet, so it appears nowhere else at all, and a
                  // failure here is the one thing on this screen that needs
                  // something doing about it.
                  for (final request in requests) _RequestTile(request: request),

                  ...switch (downloads.valueOrNull) {
                    null => [const _Waiting()],
                    final list when list.isEmpty =>
                      requests.isEmpty ? [const _Nothing()] : const <Widget>[],
                    final list => [
                      for (final job in list) _JobTile(job: job),
                    ],
                  },
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Text(
                      'When a download finishes, Plex is asked to rescan and '
                      'the library syncs on its own. Completed: '
                      '${monitor.completions}.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// One album this app is still trying to find, before any server has it.
///
/// **Where a failure becomes readable.** These used to be snackbars, which on a
/// phone over 5G is a red flash that has gone by the time you look up, cannot
/// be re-read and cannot be acted on. Here the server's own words sit next to a
/// Retry button, which is the right answer for the failure that actually
/// happens: a request that timed out on a flaky mobile link.
class _RequestTile extends ConsumerWidget {
  const _RequestTile({required this.request});

  final AcquireRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final failed = request.stage == AcquireStage.failed;
    final missing = request.stage == AcquireStage.notFound;

    return ListTile(
      leading: switch (request.stage) {
        AcquireStage.searching => const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        AcquireStage.waiting => const Icon(Icons.schedule),
        AcquireStage.handedOver => Icon(
          Icons.playlist_add_check,
          color: theme.colorScheme.primary,
        ),
        AcquireStage.notFound => const Icon(Icons.search_off),
        AcquireStage.failed => Icon(
          Icons.error_outline,
          color: theme.colorScheme.error,
        ),
      },
      title: Text(
        '${request.release.artist} · ${request.release.title}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        switch (request.stage) {
          AcquireStage.waiting => 'Waiting its turn',
          AcquireStage.searching => 'Searching',
          AcquireStage.handedOver =>
            request.detail == null
                ? 'Handed to the download server'
                : 'Queued ${request.detail}',
          // The server's own words, which is the whole point of keeping them.
          AcquireStage.notFound || AcquireStage.failed =>
            request.detail ?? 'Did not work',
        },
        style: failed
            ? theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              )
            : theme.textTheme.bodySmall,
      ),
      isThreeLine: failed || missing,
      trailing: failed || missing
          ? TextButton(
              onPressed: () =>
                  ref.read(acquireQueueProvider).retry(request.id),
              child: const Text('Retry'),
            )
          : null,
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});

  final DownloadJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (job.progress * 100).clamp(0, 100).round();

    return ListTile(
      leading: Icon(
        job.isFailed
            ? Icons.error_outline
            : job.isComplete
            ? Icons.check_circle_outline
            : Icons.downloading,
        color: job.isFailed
            ? theme.colorScheme.error
            : job.isComplete
            ? theme.colorScheme.primary
            : null,
      ),
      title: Text(
        job.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          if (!job.isComplete && !job.isFailed)
            LinearProgressIndicator(value: job.progress),
          const SizedBox(height: 4),
          Text(_status(job, percent)),
        ],
      ),
      isThreeLine: true,
    );
  }

  static String _status(DownloadJob job, int percent) {
    // The source's own words on failure. A generic "it failed" is useless, and
    // the two sources fail for entirely different reasons.
    if (job.isFailed) {
      return job.detail == null ? 'Failed' : 'Failed, ${job.detail}';
    }
    if (job.isComplete) return 'Done · ${formatBytes(job.sizeBytes)}';

    final rate = job.rateBytes > 0 ? ' · ${formatBytes(job.rateBytes)}/s' : '';
    return '$percent% of ${formatBytes(job.sizeBytes)}$rate';
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured({required this.kind});

  final DownloadSourceKind kind;

  @override
  Widget build(BuildContext context) => _Message(
    icon: Icons.cloud_off,
    // Names the source rather than saying "downloads are not set up", because
    // with two of them the generic phrasing sends someone to check the one they
    // already filled in.
    title: '${kind.label} is not set up',
    detail:
        'Add its address and sign-in under Settings, Albums you do not own. '
        'Nothing is downloaded until you ask for something.',
    action: FilledButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DownloadSourceScreen(kind: kind)),
      ),
      child: const Text('Set it up'),
    ),
  );
}

class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) => const _Message(
    icon: Icons.download_done,
    title: 'Nothing downloading',
    detail:
        'Albums you queue from an artist page or from search appear here '
        'while they arrive.',
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(48),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
