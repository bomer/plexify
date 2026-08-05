import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// What the sync layer is actually doing.
///
/// Exists because "it didn't show up" is impossible to act on. Three separate
/// mechanisms can deliver a change — the notification socket, the cheap poll,
/// and the slower delta sweep — and when nothing arrives, the screen looks
/// identical whichever one is broken. This says which.
class SyncStatusScreen extends ConsumerWidget {
  const SyncStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(syncDiagnosticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync status'),
        actions: [
          IconButton(
            tooltip: 'Re-read',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(syncDiagnosticsProvider),
          ),
        ],
      ),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('$error', textAlign: TextAlign.center),
          ),
        ),
        data: (d) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _Section(
              title: 'Server',
              subtitle:
                  'The address is chosen once by racing the local network '
                  'against the remote one, and re-chosen when it stops '
                  'answering.',
              rows: [
                ('Name', d.serverName ?? 'Not connected'),
                ('Address', d.serverUrl ?? '—'),
                ('Route', d.route),
                // Non-zero while everything else looks healthy is the
                // signature of an address that has gone stale — usually the
                // LAN one, after the phone has left the house.
                ('Failed requests in a row', '${d.failedRequests}'),
                ('Reconnects', '${d.reconnects}'),
                ('Last reconnect', _ago(d.lastReconnectAt)),
                if (d.lastReconnectReason != null)
                  ('Reconnect reason', d.lastReconnectReason!),
              ],
            ),

            _Section(
              title: 'Push notifications',
              subtitle:
                  'The fastest path. Delivers changes the moment Plex '
                  'finishes scanning them.',
              rows: [
                ('Connected', d.socketConnected ? 'Yes' : 'No'),
                ('Frames received', '${d.framesReceived}'),
                ('Library changes seen', '${d.changesSeen}'),
                ('Changes applied', '${d.changesApplied}'),
                ('Last frame', _ago(d.lastFrameAt)),
                if (d.socketError != null) ('Last error', d.socketError!),
              ],
            ),

            _Section(
              title: 'Polling',
              subtitle:
                  'Asks whether the library changed every 30 seconds, and '
                  'sweeps for edits every 5 minutes. Stops while the app is '
                  'off screen.',
              rows: [
                ('Last check', _ago(d.lastPollAt)),
                ('Last sync', _ago(d.lastSyncAt)),
                ('Sync passes', '${d.passes}'),
                // Near zero on a routine sweep means the delta filter is
                // working. Anything near the library size means Plex is
                // ignoring it and every sweep refetches everything.
                ('Rows in last sync', '${d.lastSyncRowCount}'),
                ('Currently syncing', d.isSyncing ? 'Yes' : 'No'),
                if (d.syncError != null) ('Last error', d.syncError!),
              ],
            ),

            _Section(
              title: 'Change detection',
              subtitle:
                  'A sync is triggered when the server clocks differ from '
                  'the stored ones.',
              rows: [
                ('Section updatedAt (stored)', '${d.storedUpdatedAt ?? '—'}'),
                ('Section updatedAt (server)', '${d.serverUpdatedAt ?? '—'}'),
                ('Section scannedAt (stored)', '${d.storedScannedAt ?? '—'}'),
                ('Section scannedAt (server)', '${d.serverScannedAt ?? '—'}'),
                ('Delta cursor', '${d.cursor ?? '—'}'),
                ('Initial sync complete', d.initialSyncComplete ? 'Yes' : 'No'),
              ],
            ),

            _Section(
              title: 'Cached',
              rows: [
                ('Artists', '${d.artists}'),
                ('Albums', '${d.albums}'),
                ('Tracks', '${d.tracks}'),
                ('Playlists', '${d.playlists}'),
                ('Albums with a rating', '${d.ratedAlbums}'),
              ],
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now'),
                    onPressed: () async {
                      await ref.read(syncSchedulerProvider)?.refreshNow();
                      ref.invalidate(syncDiagnosticsProvider);
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.wifi_find),
                    label: const Text('Reconnect'),
                    onPressed: () async {
                      await ref
                          .read(connectionMonitorProvider)
                          .reconnectNow();
                      ref.invalidate(syncDiagnosticsProvider);
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Full resync'),
                    onPressed: () async {
                      await ref.read(syncSchedulerProvider)?.fullResync();
                      ref.invalidate(syncDiagnosticsProvider);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reconnect picks the best route again — use it after '
                    'moving between wifi and mobile data.\n\n'
                    'A full resync re-reads the whole library. Nothing is '
                    'deleted and browsing keeps working while it runs.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  static String _ago(DateTime? at) {
    if (at == null) return 'Never';
    final d = DateTime.now().difference(at);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows, this.subtitle});

  final String title;
  final String? subtitle;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 200,
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      value,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}
