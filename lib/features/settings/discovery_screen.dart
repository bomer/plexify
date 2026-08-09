import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_probe.dart';
import '../../core/providers.dart';

/// Runs [DiscoveryProbe] and shows what came back.
///
/// The instrument for "Plexamp has rows Plex Web does not, where do they come
/// from". Three candidate sources, and this measures the two that are visible
/// from outside Plexamp: hubs the server publishes, and the server's own play
/// history. What it finds decides which Home rows are worth building and which
/// would only ever be empty.
class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  DiscoveryReport? _report;
  String? _error;
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _report = null;
    });

    try {
      final client = ref.read(plexClientProvider);
      if (client == null) throw StateError('Not connected to a server.');
      final section = await ref.read(musicSectionProvider.future);
      if (section == null) throw StateError('No music section on this server.');

      final report = await DiscoveryProbe(
        client: client,
        db: ref.read(databaseProvider),
      ).run(section);
      if (mounted) setState(() => _report = report);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = _report;

    return Scaffold(
      appBar: AppBar(title: const Text('Discovery probe')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Asks this server for the three things a fuller Home screen could '
            'be built from: the hubs it publishes, the genres it has tagged, '
            'and its own play history.\n\n'
            'Plexamp shows rows Plex Web does not. If the hubs here are thin '
            'and the history is not, its extra rows are aggregates somebody '
            'computes rather than lists the server hands out, which is also '
            'why Plexamp and Plex disagree with each other.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.explore_outlined),
            label: Text(_running ? 'Running…' : 'Run probe'),
            onPressed: _running ? null : _run,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (report != null) ...[
            const SizedBox(height: 24),
            Text('Hubs', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              report.hubs.isEmpty
                  ? 'None. Either this server publishes no music hubs or it '
                        'refused the request, which look the same from here.'
                  : 'What /hubs/sections publishes for this library.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final hub in report.hubs)
              _Row(
                label: hub.title.isEmpty ? hub.hubIdentifier : hub.title,
                value: '${hub.type}  ·  ${hub.size}  ·  ${hub.hubIdentifier}',
              ),

            const Divider(height: 32),
            Text('Genres', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '${report.genreCount} tagged. The counts are what decide whether '
              'a "More in …" row can be filled: a library usually has a long '
              'tail of genres on one album each.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final genre in report.genreSamples)
              _Row(
                label: genre.title,
                value: genre.albums < 0 ? 'failed' : '${genre.albums} albums',
              ),

            const Divider(height: 32),
            Text('Play history', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              report.historyEmpty
                  ? 'Empty. This endpoint needs server-owner access and hands '
                        'everyone else an empty container rather than a 403, so '
                        'if this library plainly has plays in it then this '
                        'account is not the owner.'
                  : 'Every client you have ever used, as the server recorded '
                        'it. This is what "most played in a month" is counted '
                        'from.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _Row(
              label: 'Rows returned',
              value: '${report.historyRows}',
              emphasis: true,
            ),
            _Row(label: 'Oldest', value: _date(report.oldestPlay)),
            _Row(label: 'Newest', value: _date(report.newestPlay)),
            for (final month in report.months)
              _Row(
                label: month.label,
                value:
                    '${month.plays} plays  ·  ${month.albums} albums  ·  '
                    '${month.inLibrary} in library',
              ),

            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_all),
              label: const Text('Copy report'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _asText(report)));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Copied')));
              },
            ),
          ],
        ],
      ),
    );
  }

  static String _date(DateTime? at) =>
      at == null ? '—' : '${at.year}-${_two(at.month)}-${_two(at.day)}';

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _asText(DiscoveryReport report) {
    final lines = <String>[
      'Discovery probe',
      '',
      'Hubs (${report.hubs.length}):',
      if (report.hubs.isEmpty) '  none',
      for (final hub in report.hubs)
        '  ${hub.hubIdentifier}  "${hub.title}"  type=${hub.type} size=${hub.size} context=${hub.context ?? '-'}',
      '',
      'Genres: ${report.genreCount} tagged',
      for (final genre in report.genreSamples)
        '  ${genre.title}: ${genre.albums < 0 ? 'failed' : '${genre.albums} albums'}',
      '',
      'History: ${report.historyRows} rows, '
          '${_date(report.oldestPlay)} to ${_date(report.newestPlay)}',
      for (final month in report.months)
        '  ${month.label}: ${month.plays} plays, ${month.albums} albums, '
            '${month.inLibrary} in library',
    ];
    return lines.join('\n');
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasis
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: style)),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: style?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
