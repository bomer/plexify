import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/delta_filter_probe.dart';
import '../../core/providers.dart';

/// Runs [DeltaFilterProbe] and shows what came back.
///
/// The instrument for a question that had been open since #18 and was finally
/// answered by reading "Rows in last sync": Plex was ignoring the delta filter
/// entirely, so every launch refetched the whole library. An ignored filter
/// cannot be seen from a response, only counted, which is why this exists as a
/// screen rather than a comment.
///
/// Re-runnable on purpose. The answer belongs to a particular server version
/// and can change under an upgrade.
class DeltaFilterScreen extends ConsumerStatefulWidget {
  const DeltaFilterScreen({super.key});

  @override
  ConsumerState<DeltaFilterScreen> createState() => _DeltaFilterScreenState();
}

class _DeltaFilterScreenState extends ConsumerState<DeltaFilterScreen> {
  DeltaFilterReport? _report;
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

      final report = await DeltaFilterProbe(client: client).run(section);
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
      appBar: AppBar(title: const Text('Delta filter probe')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Asks each filter spelling twice: for tracks changed in the last '
            'minute, where a working filter returns roughly nothing, and for '
            'tracks changed in the last ten years, where it has to return '
            'everything.\n\n'
            'Both, because a spelling the server quietly turns into an empty '
            'set looks identical to a perfect one on the first question alone '
            'and would stop the app noticing new music at all.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.filter_alt_outlined),
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
            _Verdict(report: report),
            const SizedBox(height: 16),
            _Row(
              label: 'Unfiltered',
              value: '${report.baseline} tracks',
              emphasis: true,
            ),
            const Divider(height: 24),
            for (final result in report.results)
              _Row(
                label: result.filter,
                value: result.verdictAgainst(report.baseline),
              ),
            if (report.changes.isNotEmpty) ...[
              const Divider(height: 32),
              Text(
                'What Plex says has changed',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Asked through the working filter. Rate an album in Plex, run '
                'this again, and Albums should gain one in the 5 min column.\n\n'
                'If it does not, Plex is not moving that row\'s updatedAt for a '
                'rating, and no delta sync can ever carry it however well the '
                'filter works.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final change in report.changes)
                _Row(
                  label: change.label,
                  value:
                      change.error ??
                      change.counts.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join('   '),
                ),
            ],
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

  static String _asText(DeltaFilterReport report) {
    final lines = <String>[
      'Delta filter probe',
      'recent=${report.since} ancient=${report.ancient}',
      'unfiltered: ${report.baseline} tracks',
      for (final r in report.results)
        '${r.filter}: ${r.verdictAgainst(report.baseline)}',
      if (report.changes.isNotEmpty) ...[
        '',
        'changed lately:',
        for (final c in report.changes)
          '${c.label}: ${c.error ?? c.counts.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
      ],
    ];
    return lines.join('\n');
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.report});

  final DeltaFilterReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winner = report.usable.firstOrNull;
    final dangerous = report.empty;

    return Card(
      color: winner == null
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          switch ((winner, dangerous.isNotEmpty)) {
            (final w?, _) =>
              'Use ${w.filter}. It returned ${w.recent} of ${report.baseline} '
                  'for the last minute and ${w.ancient} for the last ten '
                  'years, so it narrows and widens.',
            (null, true) =>
              'No filter is safe here. '
                  '${dangerous.map((r) => r.filter).join(', ')} returned '
                  'nothing for both questions, which means matching nothing '
                  'rather than filtering. Adopting one would stop new music '
                  'ever appearing.',
            (null, false) =>
              'No filter works on this server. Every spelling returned the '
                  'whole library, so a delta sync cannot be made cheap by '
                  'filtering and the launch check has to rely on the section '
                  'clocks alone.',
          },
          style: theme.textTheme.bodyMedium?.copyWith(
            color: winner == null
                ? theme.colorScheme.onErrorContainer
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
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
        ? theme.textTheme.bodyMedium
        : theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: SelectableText(
              label,
              style: style?.copyWith(fontFeatures: const []),
            ),
          ),
          Expanded(child: SelectableText(value, style: style)),
        ],
      ),
    );
  }
}
