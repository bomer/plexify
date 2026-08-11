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
                        'refused the request, which look the same from here. '
                        'Home falls back to its local rows.'
                  : 'Every one of these with albums in it is a row on Home, '
                        'under the title the server gave it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final hub in report.hubs)
              _Row(
                label: hub.title.isEmpty ? hub.hubIdentifier : hub.title,
                // Declared size *and* albums actually parsed. They are
                // different questions: the first is what the hub says it
                // holds, the second is what arrived in the response and is
                // therefore what Home can render. A hub that declares six and
                // parses none means the items are not inline, and every album
                // row would be silently absent.
                value:
                    '${hub.type}  ·  declares ${hub.size}  ·  '
                    'parsed ${hub.albums.length}',
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
            // The same question asked five ways. Zero has three causes that
            // arrive identical, and the only thing that separates them is
            // which of these answers.
            for (final attempt in report.historyAttempts)
              _Row(label: attempt.label, value: attempt.verdict),
            if (report.workingAttempt case final working?)
              _Row(
                label: 'Verdict',
                value:
                    'History exists and is readable. "${working.label}" '
                    'returns rows, so the app is narrowing it away itself.',
                emphasis: true,
              )
            else if (report.historyEmpty)
              const _Row(
                label: 'Verdict',
                value:
                    'No way of asking returns anything. Either this account '
                    'is not the owner, or Plex is not recording history at '
                    'all: check Settings, then Privacy, for whether play '
                    'history is being stored.',
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
            Text('Sonic neighbours', style: theme.textTheme.titleSmall),
            Text(
              'What radio is built from. Empty here and empty everywhere: an '
              'unanalysed library answers exactly like a track with nothing '
              'near it, so the seed is named to make the answer checkable.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (report.nearest case final sample?) ...[
              _Row(label: 'Seed', value: sample.seedTitle),
              _Row(
                label: '/nearest',
                value: sample.verdict,
                emphasis: sample.isEmpty || sample.error != null,
              ),
              if (sample.isEmpty)
                const _Row(
                  label: '',
                  value:
                      'Radio cannot work until Plex has analysed the library: '
                      'Settings, Manage, Libraries, then Analyze. It takes '
                      'hours to days and only has to run once.',
                  emphasis: true,
                ),
            ] else
              const _Row(
                label: '/nearest',
                value: 'no track in the cache to ask about',
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
        '  ${hub.hubIdentifier}  "${hub.title}"  type=${hub.type} '
            'size=${hub.size} parsed=${hub.albums.length}',
      '',
      'History: ${report.historyRows} rows, '
          '${_date(report.oldestPlay)} to ${_date(report.newestPlay)}',
      for (final attempt in report.historyAttempts)
        '  ${attempt.label}: ${attempt.verdict}',
      for (final month in report.months)
        '  ${month.label}: ${month.plays} plays, ${month.albums} albums, '
            '${month.inLibrary} in library',
      '',
      if (report.nearest case final sample?) ...[
        'Nearest, seeded from ${sample.seedTitle} (${sample.seedRatingKey}):',
        '  ${sample.verdict}',
      ] else
        'Nearest: no track in the cache to ask about',
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
