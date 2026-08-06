import 'plex_client.dart';
import 'plex_models.dart';

/// One filter spelling, and what the server did with it.
///
/// **Two measurements, because one cannot tell "filters correctly" from
/// "matches nothing".** Asked for a cutoff a minute ago, a working filter and a
/// filter the server silently turns into an empty set both answer zero. The
/// first would make the delta sync cheap; the second would make the app stop
/// noticing new music for ever, which is worse than the bug being fixed and
/// would look exactly like the library having gone quiet.
///
/// So each spelling is also asked for a cutoff ten years ago, where a real
/// filter has to return everything.
class DeltaFilterResult {
  const DeltaFilterResult({
    required this.filter,
    required this.recent,
    required this.ancient,
    this.error,
  });

  /// The raw query parameter name, e.g. `updatedAt>=`.
  final String filter;

  /// Rows changed in the last minute. Null if the request failed.
  final int? recent;

  /// Rows changed in the last ten years, which is the whole library.
  final int? ancient;

  final String? error;

  /// Whether this spelling both narrows *and* widens.
  ///
  /// One clause per failure mode, and nothing else:
  ///
  /// - `recent < baseline` rules out a filter the server dropped, which hands
  ///   back the whole section however it is asked.
  /// - `ancient > recent` rules out one the server turned into an empty set,
  ///   which answers zero to every question.
  ///
  /// **Deliberately not `ancient >= baseline`.** That was the first rule, and
  /// it was wrong: it assumes every row has an `updatedAt` inside the window,
  /// and on James's library 1,504 of 11,492 tracks are older than ten years or
  /// carry no timestamp at all. A perfectly good filter reported 9,988 and was
  /// declared broken. A threshold would have the same problem one library
  /// further along, so there is none.
  bool usableAgainst(int baseline) =>
      recent != null &&
      ancient != null &&
      recent! < baseline &&
      ancient! > recent!;

  /// What happened, in the words of what was measured.
  String verdictAgainst(int baseline) {
    if (error != null) return 'failed: $error';
    if (usableAgainst(baseline)) return '$recent recent / $ancient ever, works';
    if (recent! >= baseline) return '$recent recent, ignored';
    return '$recent recent / $ancient ever, matches nothing, do not use';
  }
}

/// How many rows of one metadata type Plex says changed inside a window.
///
/// The second question the probe has to answer, and the one that matters more.
/// Knowing a filter is applied says nothing about whether Plex ever moves the
/// timestamp it filters on. If rating an album leaves `updatedAt` alone, a
/// delta sync that genuinely filters can never carry that rating, and the app
/// silently stops seeing stars set anywhere else. That was invisible while the
/// filter was being ignored, because every sweep was accidentally a full sync.
class RecentChanges {
  const RecentChanges({
    required this.label,
    required this.type,
    required this.counts,
    this.error,
  });

  final String label;
  final int type;

  /// Window to row count, smallest window first.
  final Map<String, int> counts;

  final String? error;
}

/// What a probe run found.
class DeltaFilterReport {
  const DeltaFilterReport({
    required this.baseline,
    required this.since,
    required this.ancient,
    required this.results,
    required this.changes,
  });

  /// Rows in the section with no filter at all. The number every ignored
  /// filter comes back with.
  final int baseline;

  /// The narrowing cutoff asked for, in epoch seconds.
  final int since;

  /// The widening cutoff, in epoch seconds.
  final int ancient;

  final List<DeltaFilterResult> results;

  /// What Plex says has changed lately, per metadata type. Empty when no
  /// spelling was usable, since there is nothing to ask through.
  final List<RecentChanges> changes;

  /// The spellings that are safe to use.
  ///
  /// A filter Plex does not recognise is dropped rather than rejected, so the
  /// response is a perfectly valid 200 containing the entire library; and one
  /// it turns into an empty set is a perfectly valid 200 containing nothing.
  /// Only asking twice separates those from a filter that works.
  List<DeltaFilterResult> get usable =>
      results.where((r) => r.usableAgainst(baseline)).toList();

  bool get anyUsable => usable.isNotEmpty;

  /// Spellings that narrowed to nothing and stayed at nothing.
  ///
  /// Called out separately because these are the dangerous ones: they look like
  /// the answer on a single measurement, and adopting one would leave the cache
  /// silently frozen.
  List<DeltaFilterResult> get empty => results
      .where(
        (r) =>
            r.error == null &&
            r.recent != null &&
            r.recent! < baseline &&
            !r.usableAgainst(baseline),
      )
      .toList();
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
/// **And then to ask the opposite.** The first run of this probe reported that
/// `updatedAt>` returned zero rows, which reads as a perfect filter and is
/// equally consistent with a filter the server turns into an empty set.
/// Adopting that would have stopped the app noticing new music at all, which is
/// worse than the bug it was fixing and would present as the library having
/// gone quiet rather than as a broken filter. So every spelling is measured
/// twice, once where it must return nothing and once where it must return
/// everything.
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

  /// How far back the narrowing measurement asks.
  ///
  /// A minute, not the real cursor. The cursor is whatever the last sync stored
  /// and a library that genuinely changed since then would muddy the reading;
  /// nothing has been edited in the last sixty seconds, so a filter that works
  /// returns approximately nothing.
  static const window = Duration(minutes: 1);

  /// How far back the widening measurement asks.
  ///
  /// Old enough that every row in any real library is newer, so a filter that
  /// works has to return all of them. This is the half that catches a spelling
  /// the server turns into an empty set, which a single measurement reports as
  /// a spectacular success.
  static const ancientWindow = Duration(days: 3650);

  Future<DeltaFilterReport> run(PlexSection section) async {
    final now = _now();
    final since = _epochSeconds(now.subtract(window));
    final ancient = _epochSeconds(now.subtract(ancientWindow));

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
        results.add(
          DeltaFilterResult(
            filter: filter,
            recent: await _count(section, filter, since),
            ancient: await _count(section, filter, ancient),
          ),
        );
      } on Object catch (e) {
        // A rejected filter is a *result*, not a failure of the run. Some
        // spellings may well 400, and knowing which is part of the answer.
        results.add(
          DeltaFilterResult(
            filter: filter,
            recent: null,
            ancient: null,
            error: '$e',
          ),
        );
      }
    }

    // Only worth asking through a spelling the server acts on. Through an
    // ignored one every window would report the whole library and say nothing.
    final working = results
        .where((r) => r.usableAgainst(baseline))
        .map((r) => r.filter)
        .firstOrNull;

    return DeltaFilterReport(
      baseline: baseline,
      since: since,
      ancient: ancient,
      results: results,
      changes: working == null
          ? const []
          : await _recentChanges(section, working, now),
    );
  }

  /// Windows to look back over, once a working spelling is known.
  ///
  /// Five minutes is the useful one: rate something in Plex, run this, and a
  /// non-zero count for that type proves Plex moved its `updatedAt` and so a
  /// delta sync can carry the change. A zero there with a non-zero day means
  /// the timestamp is not moving for edits of that kind, which is a correctness
  /// problem rather than a cost one.
  static const changeWindows = <String, Duration>{
    '5 min': Duration(minutes: 5),
    '1 hour': Duration(hours: 1),
    '1 day': Duration(days: 1),
    '7 days': Duration(days: 7),
  };

  static const _types = <String, int>{
    'Artists': PlexClient.typeArtist,
    'Albums': PlexClient.typeAlbum,
    'Tracks': PlexClient.typeTrack,
  };

  Future<List<RecentChanges>> _recentChanges(
    PlexSection section,
    String filter,
    DateTime now,
  ) async {
    final out = <RecentChanges>[];
    for (final type in _types.entries) {
      final counts = <String, int>{};
      String? error;
      for (final window in changeWindows.entries) {
        try {
          counts[window.key] = await _client.sectionCount(
            section.key,
            type: type.value,
            filter: filter,
            filterValue: _epochSeconds(now.subtract(window.value)),
          );
        } on Object catch (e) {
          error = '$e';
          break;
        }
      }
      out.add(
        RecentChanges(
          label: type.key,
          type: type.value,
          counts: counts,
          error: error,
        ),
      );
    }
    return out;
  }

  Future<int> _count(PlexSection section, String filter, int value) =>
      _client.sectionCount(
        section.key,
        type: PlexClient.typeTrack,
        filter: filter,
        filterValue: value,
      );

  static int _epochSeconds(DateTime at) =>
      at.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
}
