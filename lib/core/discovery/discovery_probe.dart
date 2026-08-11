import '../db/app_database.dart';
import '../plex/plex_client.dart';
import '../plex/plex_models.dart';

/// How much of one month's listening the shelf could actually render.
class MonthSample {
  const MonthSample({
    required this.label,
    required this.plays,
    required this.albums,
    required this.inLibrary,
  });

  final String label;

  /// Track plays the server recorded inside the month.
  final int plays;

  /// Distinct albums those plays belong to.
  final int albums;

  /// How many of those albums the local cache holds. The gap between this and
  /// [albums] is albums that were played and have since been removed, or that
  /// belong to a section this app is not syncing.
  final int inLibrary;
}

/// One way of asking for play history, and what came back.
///
/// **Five of these rather than one number, because zero has three causes and
/// they are indistinguishable.** The endpoint needs server-owner access and
/// hands everyone else an empty container rather than a 403; a genuinely quiet
/// library answers the same way; and so does a request narrowed by a parameter
/// the endpoint does not mean what we assume it means. Asking with each
/// narrowing removed in turn is the only thing that separates them: if the
/// unfiltered form returns rows and the filtered one does not, the filter is
/// the answer and nothing was ever wrong with the permissions.
class HistoryAttempt {
  const HistoryAttempt({required this.label, required this.rows, this.error});

  final String label;

  /// Rows returned, or null if the request failed outright.
  final int? rows;

  /// Set when the server refused, which it does *not* do for an empty history,
  /// and which is exactly why the distinction is worth capturing.
  final String? error;

  String get verdict {
    if (error != null) return 'failed: $error';
    return rows == 0 ? 'nothing' : '$rows rows';
  }
}

/// Whether this server can build a sonic station, and from what.
///
/// **The one thing that cannot be inferred from anywhere else.** `/nearest` is
/// undocumented, and a server that has never run library analysis answers it
/// exactly the same way as one that has no music near the seed: politely, with
/// nothing in it. Naming the seed and counting what came back is the only way
/// to tell those apart, and to tell both apart from the endpoint not existing.
class NearestSample {
  const NearestSample({
    required this.seedTitle,
    required this.seedRatingKey,
    required this.rows,
    required this.tracks,
    required this.playable,
    this.error,
  });

  /// What was asked about, so a surprising answer can be checked by ear.
  final String seedTitle;
  final String seedRatingKey;

  /// Rows in the container, whatever their type.
  final int rows;

  /// Of those, rows declaring `type=track` — what the client keeps.
  final int tracks;

  /// Of those, ones with a playable part. A station is built from these.
  final int playable;

  final String? error;

  /// Nothing to seed a station with, which is the state being diagnosed.
  bool get isEmpty => error == null && playable == 0;

  String get verdict {
    if (error != null) return 'failed: $error';
    if (rows == 0) return 'nothing came back';
    return '$rows rows  ·  $tracks tracks  ·  $playable playable';
  }
}

/// What this server actually offers for a fuller Home screen.
class DiscoveryReport {
  const DiscoveryReport({
    required this.hubs,
    required this.historyRows,
    required this.historyAttempts,
    required this.oldestPlay,
    required this.newestPlay,
    required this.months,
    required this.nearest,
  });

  /// Sonic neighbours for one real track from the library. Null when the cache
  /// held no track to ask about, which is a different finding from an empty
  /// answer.
  final NearestSample? nearest;

  /// The hubs `/hubs/sections/{id}` published. Empty means the endpoint
  /// answered with nothing, or refused, which the client does not distinguish
  /// because nothing depends on it.
  final List<PlexHub> hubs;

  /// Rows the history endpoint returned, capped by the request.
  final int historyRows;

  /// The same question asked several ways. See [HistoryAttempt].
  final List<HistoryAttempt> historyAttempts;

  final DateTime? oldestPlay;
  final DateTime? newestPlay;

  final List<MonthSample> months;

  /// Empty history is the one finding worth calling out by name.
  ///
  /// `/status/sessions/history/all` needs server-owner access and returns an
  /// empty container to everyone else rather than a 403, so "no plays" and
  /// "not allowed" arrive looking identical. [historyAttempts] is what tells
  /// those apart, and tells both apart from a query parameter of ours being
  /// wrong.
  bool get historyEmpty => historyRows == 0;

  /// A way of asking that did return something, when the shipping one did not.
  ///
  /// Non-null here means the endpoint is fine, the account is allowed, the
  /// history exists, and [PlexClient.playHistory] is narrowing it to nothing by
  /// itself.
  HistoryAttempt? get workingAttempt =>
      historyAttempts.where((a) => (a.rows ?? 0) > 0).firstOrNull;
}

/// Asks a server what it can offer the Home screen, and counts the answers.
///
/// Written because the question "where do Plexamp's extra rows come from" has
/// three plausible answers that cannot be told apart from the outside: hubs the
/// server publishes, aggregates over the server's play history, or records
/// Plexamp keeps locally and nobody else can see. The first two are measurable
/// from here, and if both come back thin then the third is the answer by
/// elimination.
///
/// Lives in the app next to [DeltaFilterProbe] and [TranscodeProbe] for the
/// same reason they do: the answer belongs to one server at one version, and
/// has to be re-runnable rather than written down.
class DiscoveryProbe {
  DiscoveryProbe({
    required PlexClient client,
    required AppDatabase db,
    DateTime Function()? now,
  }) : _client = client,
       _db = db,
       _now = now ?? DateTime.now;

  final PlexClient _client;
  final AppDatabase _db;
  final DateTime Function() _now;

  Future<DiscoveryReport> run(PlexSection section) async {
    final hubs = await _client.sectionHubs(section.key);

    final plays = await _client.playHistory(section.key);
    final attempts = await _historyAttempts(section);
    final now = _now();

    // Resolved the same way the shelf does it, or the month counts report zero
    // albums against a month with plays in it and read as a second fault. Plex
    // labels a history row with the track and not the album it came from.
    final albumOfTrack = await _db.albumKeysForTracks(
      plays.map((play) => play.trackRatingKey),
    );

    return DiscoveryReport(
      hubs: hubs,
      historyRows: plays.length,
      historyAttempts: attempts,
      oldestPlay: _at(plays.isEmpty ? null : plays.last.viewedAt),
      newestPlay: _at(plays.isEmpty ? null : plays.first.viewedAt),
      nearest: await _nearest(),
      months: [
        await _month(
          plays,
          albumOfTrack,
          DateTime(now.year, now.month),
          'This month',
        ),
        await _month(
          plays,
          albumOfTrack,
          DateTime(now.year, now.month - 1),
          'Last month',
        ),
      ],
    );
  }

  /// Asks for history with each narrowing removed in turn.
  ///
  /// Ordered so the first entry is exactly what the app ships, and each one
  /// after it drops something. The first that returns rows names the culprit.
  Future<List<HistoryAttempt>> _historyAttempts(PlexSection section) async {
    Future<HistoryAttempt> attempt(
      String label, {
      String? sectionKey,
      bool tracksOnly = true,
      String? accountId,
    }) async {
      try {
        final rows = await _client.playHistoryRaw(
          sectionKey: sectionKey,
          tracksOnly: tracksOnly,
          accountId: accountId,
          // Small: this is counting, not collecting, and five requests against
          // a long history should not move a megabyte to answer a yes or no.
          limit: 50,
        );
        return HistoryAttempt(label: label, rows: rows.length);
      } on Object catch (e) {
        return HistoryAttempt(label: label, rows: null, error: '$e');
      }
    }

    return [
      await attempt('As the app asks', sectionKey: section.key),
      await attempt(
        'Without type=10',
        sectionKey: section.key,
        tracksOnly: false,
      ),
      await attempt('Without the section', tracksOnly: true),
      await attempt('Neither narrowing', tracksOnly: false),
      await attempt('Account 1 only', tracksOnly: false, accountId: '1'),
    ];
  }

  /// Asks `/nearest` about a track this library actually holds.
  ///
  /// Seeded from a *played* track where possible. Sonic analysis runs over the
  /// whole library, so any track should do, but one that has been played is one
  /// the user can recognise in the answer, and "these are nothing like it" is
  /// itself a finding the counts cannot show.
  Future<NearestSample?> _nearest() async {
    final seed = await _db.aTrackWorthProbing();
    if (seed == null) return null;

    try {
      // Deliberately the raw container rather than PlexClient.nearest, which
      // filters to tracks and swallows the failure. Both of those are the right
      // call in the app and would destroy the evidence here: a response that is
      // all albums and a response that is empty must not arrive looking the
      // same.
      final rows = await _client.nearestRaw(seed.ratingKey);
      final tracks = [
        for (final row in rows)
          if (row['type'] == 'track') PlexTrack.fromJson(row),
      ];

      return NearestSample(
        seedTitle: '${seed.artistTitle} — ${seed.title}',
        seedRatingKey: seed.ratingKey,
        rows: rows.length,
        tracks: tracks.length,
        playable: tracks.where((t) => t.isPlayable).length,
      );
    } on Object catch (e) {
      return NearestSample(
        seedTitle: '${seed.artistTitle} — ${seed.title}',
        seedRatingKey: seed.ratingKey,
        rows: 0,
        tracks: 0,
        playable: 0,
        error: '$e',
      );
    }
  }

  Future<MonthSample> _month(
    List<PlexPlay> plays,
    Map<String, String> albumOfTrack,
    DateTime month,
    String label,
  ) async {
    final from =
        DateTime(month.year, month.month).millisecondsSinceEpoch ~/ 1000;
    final to =
        DateTime(month.year, month.month + 1).millisecondsSinceEpoch ~/ 1000;

    var count = 0;
    final albums = <String>{};
    for (final play in plays) {
      if (play.viewedAt < from || play.viewedAt >= to) continue;
      count++;
      final key = play.albumRatingKey ?? albumOfTrack[play.trackRatingKey];
      if (key != null) albums.add(key);
    }

    final held = await _db.albumsByKeys(albums);
    return MonthSample(
      label: label,
      plays: count,
      albums: albums.length,
      inLibrary: held.length,
    );
  }

  static DateTime? _at(int? seconds) => seconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          seconds * Duration.millisecondsPerSecond,
        );
}
