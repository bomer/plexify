import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../../core/plex/transcode_probe.dart';
import '../../core/providers.dart';

/// Runs the transcode probe and shows what came back.
///
/// This is the instrument for task #8. It lives in the app rather than in a
/// script because the endpoint behaves differently over LAN, remote and relay,
/// and the only way to test the relay path honestly is to carry the app out of
/// the house — which a script on the desktop cannot do.
///
/// The report is copyable on purpose: the deliverable of the spike is the
/// written-down parameter set, and the run that matters happens away from a
/// keyboard.
class TranscodeSpikeScreen extends ConsumerStatefulWidget {
  const TranscodeSpikeScreen({super.key});

  @override
  ConsumerState<TranscodeSpikeScreen> createState() =>
      _TranscodeSpikeScreenState();
}

class _TranscodeSpikeScreenState extends ConsumerState<TranscodeSpikeScreen> {
  TranscodeProbeReport? _report;
  String? _error;
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _report = null;
    });

    try {
      final track = await ref.read(probeTrackProvider.future);
      if (track == null) {
        throw StateError(
          'No track to probe. Play something, or wait for the library sync.',
        );
      }
      final probe = ref.read(transcodeProbeProvider);
      if (probe == null) throw StateError('Not connected to a server.');

      final report = await probe.run(track);
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
      appBar: AppBar(
        title: const Text('Transcode probe'),
        actions: [
          if (report != null)
            IconButton(
              tooltip: 'Copy report',
              icon: const Icon(Icons.copy_all),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report.toText()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Report copied')),
                  );
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Measures how this server answers a music transcode request over '
            'whatever route is currently in use. Run it once on the LAN and '
            'again on mobile data — the answers are allowed to differ, and '
            'that difference is the point.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          const _TargetTrack(),

          const SizedBox(height: 16),
          FilledButton.icon(
            icon: _running
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_running ? 'Probing…' : 'Run probe'),
            onPressed: _running ? null : _run,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Tries several parameter sets to find which the server accepts. '
              'Downloads under half a megabyte and stops every transcode '
              'session it opens.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 24),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],

          if (report != null) ...[
            const Divider(height: 40),
            _ReportHeader(report: report),
            const SizedBox(height: 16),
            for (final check in report.checks) _CheckTile(check: check),
          ],
        ],
      ),
    );
  }
}

/// Names the track the probe will use, so a surprising result can be blamed on
/// the right thing — a 64 kbps MP3 cannot be transcoded up to 320.
class _TargetTrack extends ConsumerWidget {
  const _TargetTrack();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final track = ref.watch(probeTrackProvider);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: track.when(
          loading: () => const Text('Choosing a track…'),
          error: (e, _) => Text('$e'),
          data: (t) => t == null
              ? const Text('No track available to probe.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Probing', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text(
                      '${t.artist} — ${t.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      '${t.container ?? 'unknown container'} · '
                      '${(t.durationMs / 1000).round()}s',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Play a track to probe that one instead.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.report});

  final TranscodeProbeReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Route: ${report.route}', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        SelectableText(
          report.exampleUrl,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check});

  final ProbeCheck check;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, colour) = switch (check.outcome) {
      ProbeOutcome.pass => (Icons.check_circle, theme.colorScheme.primary),
      ProbeOutcome.fail => (Icons.cancel, theme.colorScheme.error),
      ProbeOutcome.unknown => (
        Icons.help_outline,
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Icon(icon, size: 18, color: colour),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.question, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                SelectableText(
                  check.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The track the probe runs against.
///
/// Prefers whatever is playing — it is the track the user was thinking about,
/// and letting them choose by pressing play beats building a picker. Falls back
/// to the first playable track in the cache so the screen is useful before any
/// playback has happened.
final probeTrackProvider = FutureProvider<PlexTrack?>((ref) async {
  final client = ref.watch(plexClientProvider);
  if (client == null) return null;

  final playing =
      ref
              .watch(audioHandlerProvider)
              .mediaItem
              .valueOrNull
              ?.extras?['ratingKey']
          as String?;

  if (playing != null) {
    final json = await client.metadataItem(playing);
    if (json != null) return PlexTrack.fromJson(json);
  }

  // Asked of the server rather than the cache: the probe is about what this
  // route does right now, and a cached row proves nothing about reachability.
  final section = await client.musicSection();
  if (section == null) return null;

  for (final album in await client.albums(section.key, size: 5)) {
    for (final track in await client.tracks(album.ratingKey)) {
      if (track.isPlayable) return track;
    }
  }
  return null;
});

/// Null until a server connection exists.
final transcodeProbeProvider = Provider<TranscodeProbe?>((ref) {
  final client = ref.watch(plexClientProvider);
  if (client == null) return null;
  return TranscodeProbe(client: client);
});
