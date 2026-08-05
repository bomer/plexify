import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../../core/settings/app_settings.dart';
import 'account_controller.dart';

/// Every server on the account, so one can be chosen deliberately.
///
/// Without a choice the app takes whichever answers first, which is right for
/// the single-server case and arbitrary for any other. Choosing is binding:
/// once a server is picked the app will wait for it rather than quietly
/// connecting to a different one, because the two libraries share ratingKeys
/// and swapping between them means a full resync each way.
class ServerPickerScreen extends ConsumerWidget {
  const ServerPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(accountServersProvider);
    final connected = ref.watch(plexServerProvider);
    final preferred = ref.watch(
      settingsProvider.select((s) => s.preferredServerId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server'),
        actions: [
          IconButton(
            tooltip: 'Re-read',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(accountServersProvider),
          ),
        ],
      ),
      body: servers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Listing servers goes to plex.tv, so this fails whenever the internet
        // does — including on a LAN where the current server works perfectly.
        error: (error, _) => _Message(
          text: 'Could not reach plex.tv to list your servers.\n\n$error',
          onRetry: () => ref.invalidate(accountServersProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const _Message(text: 'No servers on this account.');
          }

          return ListView(
            children: [
              for (final server in list)
                _ServerTile(
                  server: server,
                  isConnected:
                      server.clientIdentifier == connected?.clientIdentifier,
                  isPreferred: server.clientIdentifier == preferred,
                  onTap: () => _choose(context, ref, server),
                ),

              if (preferred != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: OutlinedButton(
                    onPressed: () => _choose(context, ref, null),
                    child: const Text('Use whichever answers first'),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Text(
                  'Changing server clears the local library. Plex numbers its '
                  'items per server, so a cache from one is meaningless '
                  'against another — everything is fetched again.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Confirms, then switches. A null [server] releases the preference.
  static Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    PlexResource? server,
  ) async {
    final current = ref.read(settingsProvider).preferredServerId;
    if (server?.clientIdentifier == current) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          server == null ? 'Use any server?' : 'Switch to ${server.name}?',
        ),
        content: const Text(
          'The local library will be cleared and synced again. Nothing on '
          'Plex is changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(accountControllerProvider)
        .switchTo(server?.clientIdentifier);
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.isConnected,
    required this.isPreferred,
    required this.onTap,
  });

  final PlexResource server;
  final bool isConnected;
  final bool isPreferred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // "Connected" and "chosen" are different facts and both are worth showing:
    // a chosen server that is not connected is the state you need to see when
    // the library has gone quiet.
    final notes = [
      if (isConnected) 'Connected',
      if (isPreferred) 'Chosen',
      if (!server.owned) 'Shared with you',
    ];

    return ListTile(
      leading: Icon(
        isPreferred ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text(server.name),
      subtitle: notes.isEmpty ? null : Text(notes.join(' · ')),
      onTap: onTap,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
