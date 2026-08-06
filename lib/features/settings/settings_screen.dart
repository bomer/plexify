import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/artwork/artwork_cache.dart';
import '../../core/audio/audio_cache.dart';
import '../../core/audio/quality_policy.dart';
import '../../core/plex/plex_identity.dart';
import '../../core/providers.dart';
import '../../core/settings/app_settings.dart';
import '../acquire/downloads_screen.dart';
import 'account_controller.dart';
import 'qbittorrent_screen.dart';
import 'server_picker_screen.dart';
import 'sync_status_screen.dart';

/// The Settings destination.
///
/// The rule this screen was built under, and still keeps: **nothing here is
/// shown unless something already reads it.** A screen full of controls that
/// change nothing is worse than a short one, because it looks finished and
/// nobody notices the wiring is missing. Sections appeared as their contents
/// did, which is why Playback and Storage arrived two tasks after the rest.
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
          _PlaybackSection(),
          _StorageSection(),
          _CatalogSection(),
          _AppearanceSection(),
          _SyncSection(),
          _AboutSection(),
        ],
      ),
    );
  }
}

/// Streaming quality, per kind of connection.
///
/// **There is no bitrate here, and that is a finding rather than an omission.**
/// #8 asked Plex's music transcoder for 128kbps three different documented
/// ways and got the natural rate back byte for byte each time. So the only
/// lever that exists is whether transcoding happens at all, which makes this
/// two choices rather than a quality ladder.
///
/// It also makes a separate "data saver" toggle pointless: forcing a transcode
/// on mobile data *is* data saver, and a second control that set the same field
/// under a friendlier name would be a second thing to keep in step for no gain.
class _PlaybackSection extends ConsumerWidget {
  const _PlaybackSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return _Section(
      title: 'Playback',
      children: [
        _QualityTile(
          label: 'On wifi and ethernet',
          value: settings.qualityUnmetered,
          onChanged: controller.setQualityUnmetered,
        ),
        _QualityTile(
          label: 'On mobile data',
          value: settings.qualityMetered,
          onChanged: controller.setQualityMetered,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            'Automatic streams the original file at home and on wifi, and asks '
            'Plex to transcode over mobile data or a relay. It already skips '
            'transcoding a file too small to be worth it.\n\n'
            'A change applies to the next thing you play, not to what is '
            'playing now.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// One connection's quality choice.
class _QualityTile extends StatelessWidget {
  const _QualityTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final QualityDecision? value;
  final ValueChanged<QualityDecision?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: DropdownButton<String>(
        value: value?.name ?? _auto,
        underline: const SizedBox.shrink(),
        onChanged: (choice) => onChanged(
          choice == _auto
              ? null
              : QualityDecision.values.firstWhere((d) => d.name == choice),
        ),
        items: const [
          DropdownMenuItem(value: _auto, child: Text('Automatic')),
          DropdownMenuItem(value: 'directPlay', child: Text('Original file')),
          DropdownMenuItem(value: 'transcode', child: Text('Transcoded')),
        ],
      ),
    );
  }

  /// Null is a real value here, and `DropdownButton` treats null as "nothing
  /// selected" and shows a blank. Hence a sentinel string rather than a
  /// `DropdownButton<QualityDecision?>`.
  static const _auto = 'auto';
}

/// How much disk the two caches may take, and how to get it back.
class _StorageSection extends ConsumerWidget {
  const _StorageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final usage = ref.watch(cacheUsageProvider);

    return _Section(
      title: 'Storage',
      children: [
        if (AudioCache.supported) ...[
          _BudgetTile(
            label: 'Music',
            value: settings.audioCacheMaxBytes,
            options: const [512, 1024, 2048, 5120, 10240],
            fallback: AudioCache.defaultMaxBytes,
            onChanged: controller.setAudioCacheMaxBytes,
          ),
          _UsageLine(
            usage: usage,
            describe: (u) =>
                '${u.audioFiles} ${u.audioFiles == 1 ? "track" : "tracks"}, '
                '${_mb(u.audioBytes)} of ${_mb(u.audioBudget)}',
          ),
        ] else
          const ListTile(
            title: Text('Music'),
            // Stated rather than hidden: an empty music cache on the desktop
            // otherwise reads as a bug, and the reason is not guessable.
            subtitle: Text(
              'Not cached on this platform. Desktop listening is on the LAN '
              'and streams the original, so a second copy on the same machine '
              'buys nothing.',
            ),
          ),
        _BudgetTile(
          label: 'Artwork',
          value: settings.artworkCacheMaxBytes,
          options: const [64, 128, 256, 512],
          fallback: ArtworkCache.defaultMaxBytes,
          onChanged: controller.setArtworkCacheMaxBytes,
        ),
        _UsageLine(
          usage: usage,
          describe: (u) =>
              '${u.artworkFiles} ${u.artworkFiles == 1 ? "image" : "images"}, '
              '${_mb(u.artworkBytes)} of ${_mb(u.artworkBudget)}',
        ),
        ListTile(
          leading: const Icon(Icons.delete_sweep_outlined),
          title: const Text('Clear cached files'),
          subtitle: const Text(
            'Music and artwork only. Your library, ratings and sign-in are '
            'untouched.',
          ),
          onTap: () => _clear(context, ref),
        ),
      ],
    );
  }

  static Future<void> _clear(BuildContext context, WidgetRef ref) async {
    // No confirmation dialog: everything this deletes is re-downloadable, and
    // the button already says what it removes. Confirming a reversible action
    // trains people to dismiss the dialogs that matter.
    await ref.read(artworkCacheProvider).clear();
    await ref.read(audioCacheProvider).clear();
    ref.invalidate(cacheUsageProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cached files cleared')));
    }
  }

  static String _mb(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).round()} MB';
  }
}

/// A cache budget, chosen in megabytes.
class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.label,
    required this.value,
    required this.options,
    required this.fallback,
    required this.onChanged,
  });

  final String label;
  final int? value;

  /// Offered sizes, in megabytes.
  final List<int> options;

  /// What "Default" means on this platform. Shown so the default is a number
  /// rather than a mystery, since it differs by an order of magnitude between
  /// a phone and a desktop.
  final int fallback;

  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    // A stored budget that is not one of the offered sizes (an older build's
    // list, or a hand-edited preference) would make DropdownButton assert on a
    // value with no item, so it is folded into the list rather than dropped.
    final sizes = {
      ...options,
      if (value != null) value! ~/ (1024 * 1024),
    }.toList()..sort();

    return ListTile(
      title: Text(label),
      trailing: DropdownButton<int>(
        value: value == null ? _default : value! ~/ (1024 * 1024),
        underline: const SizedBox.shrink(),
        onChanged: (mb) => onChanged(mb == _default ? null : mb! * 1024 * 1024),
        items: [
          DropdownMenuItem(
            value: _default,
            child: Text('Default (${_label(fallback ~/ (1024 * 1024))})'),
          ),
          for (final mb in sizes)
            DropdownMenuItem(value: mb, child: Text(_label(mb))),
        ],
      ),
    );
  }

  /// -1 rather than null, for the same reason [_QualityTile] uses a sentinel:
  /// a null value makes `DropdownButton` render nothing at all.
  static const _default = -1;

  static String _label(int mb) => mb >= 1024
      ? '${(mb / 1024).toStringAsFixed(mb % 1024 == 0 ? 0 : 1)} GB'
      : '$mb MB';
}

/// The measured line under a budget, or a placeholder while it is measured.
class _UsageLine extends StatelessWidget {
  const _UsageLine({required this.usage, required this.describe});

  final AsyncValue<CacheUsage> usage;
  final String Function(CacheUsage) describe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        // Scanning a directory is quick but not instant, and an em-space keeps
        // the row from collapsing and shifting everything below it.
        usage.valueOrNull == null ? ' ' : describe(usage.value!),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Albums you do not own, and where to get them.
///
/// **One switch for both halves, and that is the design rather than a
/// shortcut.** Looking up records the library does not hold is either something
/// you want or something you do not, and the two places it shows — the lower
/// tier of search and the missing-albums grid on an artist page — are the same
/// question asked from two directions. A build where one appeared without the
/// other would be harder to explain than either.
///
/// Off by default. Settings are per device, which is exactly the granularity
/// wanted here: on a phone this is noise, and on the desktop, where downloads
/// actually happen, it is the point.
///
/// The qBittorrent rows sit inside the same section but stay visible when the
/// switch is off, so an address typed in once is not hidden by turning the
/// feature off and mysteriously absent when it goes back on.
class _CatalogSection extends ConsumerWidget {
  const _CatalogSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final enabled = settings.catalogEnabled;

    return _Section(
      title: 'Albums you do not own',
      children: [
        SwitchListTile(
          value: enabled,
          onChanged: ref.read(settingsProvider.notifier).setCatalogEnabled,
          title: const Text('Search and show missing albums'),
          subtitle: const Text(
            'Adds a "Not in your library" section to search, and lists what an '
            'artist released that you do not have. Uses MusicBrainz.',
          ),
        ),
        ListTile(
          enabled: enabled,
          leading: const Icon(Icons.downloading),
          title: const Text('qBittorrent'),
          subtitle: Text(
            settings.qbitUrl == null
                ? 'Not set up. Needed only to download something.'
                : settings.qbitUrl!,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const QbittorrentScreen()),
          ),
        ),
        ListTile(
          enabled: enabled,
          leading: const Icon(Icons.download_outlined),
          title: const Text('Downloads'),
          subtitle: const Text('What is arriving, and what has landed.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
          ),
        ),
        if (enabled)
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Forget catalog lookups'),
            subtitle: const Text(
              'Throws away what MusicBrainz told us, including any artist '
              'matched to the wrong person. Your library is untouched.',
            ),
            onTap: () async {
              await ref.read(databaseProvider).clearCatalog();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Catalog lookups forgotten')),
                );
              }
            },
          ),
      ],
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
