import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_identity.dart';
import '../../core/providers.dart';
import '../../core/settings/app_settings.dart';
import 'account_controller.dart';
import 'server_picker_screen.dart';
import 'sync_status_screen.dart';

/// The Settings destination.
///
/// A shell, deliberately. Most of what will eventually live here — quality
/// policy, cache sizes, data saver — belongs to tasks that have not happened
/// yet, and a screen full of controls that change nothing is worse than a short
/// one: it looks finished, so nobody notices the wiring is missing.
///
/// So this ships only what something already reads today, and gives the
/// features that follow somewhere obvious to land. Sections appear as their
/// contents do.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: const [
          _AccountSection(),
          _AppearanceSection(),
          _SyncSection(),
          _AboutSection(),
        ],
      ),
    );
  }
}

/// Which Plex account and server this is, how it is being reached, and the two
/// ways to leave.
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(plexServerProvider);

    return _Section(
      title: 'Account',
      children: [
        _Fact('Server', server?.name ?? 'Not connected'),
        _Fact('Route', server?.routeLabel ?? '—'),
        _Fact('Address', server?.baseUrl ?? '—'),
        const SizedBox(height: 4),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Server'),
          subtitle: const Text('Choose which server on your account to use.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ServerPickerScreen()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          subtitle: const Text('Clears the local library and the saved token.'),
          onTap: () => _confirmSignOut(context, ref),
        ),
      ],
    );
  }

  /// Signing out discards the whole local cache and forces a full resync, which
  /// on a large library is minutes of work. Worth one tap to confirm.
  static Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Plex?'),
        content: const Text(
          'The local library will be cleared and you will need to link the '
          'app again. Nothing on Plex is changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(accountControllerProvider).signOut();
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));

    return _Section(
      title: 'Appearance',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => ref
                .read(settingsProvider.notifier)
                .setThemeMode(selection.first),
          ),
        ),
      ],
    );
  }
}

/// Sync lives here now rather than behind an app-bar icon.
///
/// It was reachable only from an `info` button next to Refresh, which is where
/// nobody looks for it. It is diagnostic, not something to check routinely, so
/// one level down inside Settings is the right depth.
class _SyncSection extends StatelessWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Sync',
      children: [
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Sync status'),
          subtitle: const Text(
            'What each delivery mechanism is doing, and what the cache holds.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SyncStatusScreen()),
          ),
        ),
      ],
    );
  }
}

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(plexIdentityProvider);

    return _Section(
      title: 'About',
      children: [
        _Fact(PlexIdentity.product, PlexIdentity.version),
        _Fact('Platform', identity.platform),
        _Fact('Device', identity.deviceName),
        // Worth surfacing: this is what Plex ties the login to, and it is the
        // value to quote when a server lists a device you do not recognise.
        _Fact('Client identifier', identity.clientIdentifier),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// A label and a value that cannot be changed from here.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
