import 'plex_client.dart';
import 'plex_models.dart';

/// One filter spelling, and what the server did with it.
class DeltaFilterResult {
  const DeltaFilterResult({
    required this.filter,
    required this.count,
    this.error,
  });

  /// The raw query parameter name, e.g. `updatedAt>=`.
  final String filter;

  /// Rows the server reported through it, or null if the request failed.
  final int? count;

  final String? error;
}

/// What a probe run found.
class DeltaFilterReport {
  const DeltaFilterReport({
    required this.baseline,
    required this.since,
    required this.results,
  });

  /// Rows in the section with no filter at all. The number every ignored
  /// filter comes back with.
  final int baseline;

  /// The cutoff asked for, in epoch seconds.
  final int since;

  final List<DeltaFilterResult> results;

  /// The spellings the server acted on, cheapest first.
  ///
  /// "Acted on" means fewer rows than unfiltered. A filter Plex does not
  /// recognise is silently dropped rather than rejected, so the response is a
  /// perfectly valid 200 containing the entire library, and the only way to
  /// tell the two apart is to count.
  List<DeltaFilterResult> get honoured =>
      results.where((r) => r.count != null && r.count! < baseline).toList()
        ..sort((a, b) => a.count!.compareTo(b.count!));

  bool get anyHonoured => honoured.isNotEmpty;
}

/// Finds out which delta filter, if any, this server actually applies.
///
/// The delta sync's entire economy rests on `updatedAt>=`: with it a quiet
/// launch is a handful of requests, without it every launch refetches the
/// library. Measured on James's server on 6 August 2026, a delta asking for
/// rows newer than the stored cursor returned **all 13,704 of them** — so the
/// filter this app had been sending since #18 was doing nothing at all, and had
/// been doing nothing invisibly, because an ignored filter looks exactly like a
/// library where everything changed.
///
/// That is what makes this worth an instrument rather than a guess. Plex
/// accepts unknown filter parameters, answers 200, and drops them. There is no
/// error to read and no documentation to trust, so the only honest test is to
/// ask for something that *must* narrow the result and count what comes back.
///
/// Lives in the app, next to [TranscodeProbe], for the same reason: it has to
/// be re-runnable against the real server after an upgrade changes the answer.
class DeltaFilterProbe {
  DeltaFilterProbe({required PlexClient client, DateTime Function()? now})
    : _client = client,
      _now = now ?? DateTime.now;

  final PlexClient _client;
  final DateTime Function() _now;

  /// The spellings worth trying, in the order they are reported.
  ///
  /// `updatedAt>=` is what the app has been sending. The doubled operators are
  /// Plex's own convention in the filter syntax its web client builds (`>>=`
  /// for at-or-after), which is the leading suspect for why the single form is
  /// dropped.
  static const candidates = <String>[
    'updatedAt>=',
    'updatedAt>>=',
    'updatedAt>',
    'updatedAt>>',
  ];

  /// How far back to ask for.
  ///
  /// A minute, not the real cursor. The cursor is whatever the last sync stored
  /// and a library that genuinely changed since then would muddy the reading;
  /// nothing has been edited in the last sixty seconds, so a filter that works
  /// returns approximately nothing and a filter that is ignored returns the
  /// whole section. There is no ambiguous middle.
  static const window = Duration(minutes: 1);

  Future<DeltaFilterReport> run(PlexSection section) async {
    final since =
        _now().subtract(window).millisecondsSinceEpoch ~/
        Duration.millisecondsPerSecond;

    // Tracks rather than albums or artists: it is the biggest of the three, so
    // the gap between "filtered" and "ignored" is the widest, and it is where
    // the cost actually lands.
    final baseline = await _client.sectionCount(
      section.key,
      type: PlexClient.typeTrack,
    );

    final results = <DeltaFilterResult>[];
    for (final filter in candidates) {
      try {
        final count = await _client.sectionCount(
          section.key,
          type: PlexClient.typeTrack,
          filter: filter,
          filterValue: since,
        );
        results.add(DeltaFilterResult(filter: filter, count: count));
      } on Object catch (e) {
        // A rejected filter is a *result*, not a failure of the run. Some
        // spellings may well 400, and knowing which is part of the answer.
        results.add(
          DeltaFilterResult(filter: filter, count: null, error: '$e'),
        );
      }
    }

    return DeltaFilterReport(
      baseline: baseline,
      since: since,
      results: results,
    );
  }
}
