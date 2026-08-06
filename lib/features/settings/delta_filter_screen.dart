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
            'Asks the server for tracks changed in the last minute, once per '
            'filter spelling, and counts what comes back. Nothing has been '
            'edited in the last minute, so a filter that works returns roughly '
            'nothing and a filter the server ignores returns the whole '
            'library.',
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
                value: switch (result) {
                  DeltaFilterResult(error: final e?) => 'failed: $e',
                  DeltaFilterResult(count: final c?) =>
                    c < report.baseline
                        ? '$c tracks — honoured'
                        : '$c tracks — ignored',
                  _ => 'no answer',
                },
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

  static String _asText(DeltaFilterReport report) {
    final lines = <String>[
      'Delta filter probe',
      'since=${report.since}',
      'unfiltered: ${report.baseline} tracks',
      for (final r in report.results)
        '${r.filter}: ${r.error ?? '${r.count} tracks'}',
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
    final winner = report.honoured.firstOrNull;

    return Card(
      color: winner == null
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          winner == null
              ? 'No filter works on this server. Every spelling returned the '
                    'whole library, so a delta sync cannot be made cheap by '
                    'filtering and the launch check has to rely on the section '
                    'clocks alone.'
              : 'Use ${winner.filter} — it returned ${winner.count} of '
                    '${report.baseline}.',
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
