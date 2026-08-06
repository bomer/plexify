import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/qbit/qbit_models.dart';
import '../settings/qbittorrent_screen.dart';
import 'download_sheet.dart' show formatBytes;

/// What qBittorrent is downloading into the Music category.
///
/// Read-only on purpose. This is a music player that can ask for a record, not
/// a torrent client: pausing, reprioritising and deleting all exist perfectly
/// well in qBittorrent's own interface, and rebuilding them here would mean
/// keeping a second one in step for no gain.
///
/// What it *is* for is answering the question the flow creates — "I asked for
/// that album twenty minutes ago, where is it?" — which otherwise means opening
/// another app to find out.
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            tooltip: 'qBittorrent settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const QbittorrentScreen(),
              ),
            ),
          ),
        ],
      ),
      body: monitor == null
          ? const _NotConfigured()
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
                  ...switch (downloads.valueOrNull) {
                    null => [const _Waiting()],
                    final list when list.isEmpty => [const _Nothing()],
                    final list => [
                      for (final torrent in list)
                        _TorrentTile(torrent: torrent),
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

class _TorrentTile extends StatelessWidget {
  const _TorrentTile({required this.torrent});

  final QbitTorrent torrent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (torrent.progress * 100).clamp(0, 100).round();

    return ListTile(
      leading: Icon(
        torrent.isFailed
            ? Icons.error_outline
            : torrent.isComplete
            ? Icons.check_circle_outline
            : Icons.downloading,
        color: torrent.isFailed
            ? theme.colorScheme.error
            : torrent.isComplete
            ? theme.colorScheme.primary
            : null,
      ),
      title: Text(
        torrent.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          if (!torrent.isComplete && !torrent.isFailed)
            LinearProgressIndicator(value: torrent.progress),
          const SizedBox(height: 4),
          Text(_status(torrent, percent)),
        ],
      ),
      isThreeLine: true,
    );
  }

  static String _status(QbitTorrent torrent, int percent) {
    if (torrent.isFailed) return 'Failed — ${torrent.state}';
    if (torrent.isComplete) {
      return 'Done · ${formatBytes(torrent.sizeBytes)}';
    }
    final rate = torrent.downloadRateBytes > 0
        ? ' · ${formatBytes(torrent.downloadRateBytes)}/s'
        : '';
    return '$percent% of ${formatBytes(torrent.sizeBytes)}$rate';
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => _Message(
    icon: Icons.cloud_off,
    title: 'qBittorrent is not set up',
    detail:
        'Add the WebUI address and sign-in under Settings, Downloads. Nothing '
        'is downloaded until you ask for something.',
    action: FilledButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const QbittorrentScreen()),
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
