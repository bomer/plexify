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

/// One way of asking for sonic neighbours, and what came back.
///
/// **The `_historyAttempts` pattern, for the same reason.** A single shaped
/// guess cannot say which part of a request is wrong: the path, the seed's
/// type, or a parameter. Asking several ways and reporting each separates them,
/// and the first form that returns rows is the answer.
///
/// Measured on James's server, 12 August 2026, and the answer was **none of
/// them**. `/nearest` answers 200 with an empty container for a track, its
/// album and its artist, with and without `type`; `/similar`, `/station/8` and
/// `/sections/{id}/stations` all 404. An endpoint that exists and holds nothing
/// is a data problem, not a request problem: sonic analysis is a Plex Pass
/// feature run separately from the ordinary "Analyze", and this library has not
/// had it.
///
/// **The inference that wasted three attempts is recorded in [StationRow].**
class NearestAttempt {
  const NearestAttempt({
    required this.label,
    required this.path,
    required this.rows,
    required this.tracks,
    this.error,
  });

  final String label;

  /// The exact path asked, so a working one can be read straight off.
  final String path;

  /// Rows in the container, or null when the request failed outright.
  final int? rows;

  /// Of those, rows declaring `type=track`.
  final int tracks;

  /// Set when the server refused, which it does *not* do for an empty result.
  /// A 404 means the path does not exist; an empty 200 means it does and had
  /// nothing to say. Those are different findings and must not be merged.
  final String? error;

  bool get worked => (rows ?? 0) > 0;

  String get verdict {
    if (error != null) return 'failed: $error';
    if (rows == 0) return 'nothing';
    return '$rows rows, $tracks tracks';
  }
}

/// A station this server publishes, and what its key actually returns.
///
/// **Naming the key was not enough.** `/nearest` proved that an endpoint can
/// exist, answer 200 and hold nothing at all, so a key is a lead until it has
/// been fetched. These are the one part of the station API this server
/// demonstrably has, and whether they can be played is the difference between a
/// feature and another dead end.
///
/// Worth being clear about what they are *not*. "Library Radio", "Deep Cuts",
/// "Time Travel" and "Random Album" are rule-based — everything, rarely played,
/// by era, by album — and none of them needs a sonic fingerprint. This hub
/// being full is therefore no evidence that sonic analysis has run, which is
/// exactly the inference that sent the first three attempts at radio looking
/// for a fault in the request.
class StationRow {
  const StationRow({
    required this.title,
    required this.key,
    required this.type,
    this.rows,
    this.tracks,
    this.error,
  });

  final String title;
  final String key;
  final String type;

  /// What fetching [key] returned, or null if it was not fetched.
  final int? rows;

  /// Of those, rows declaring `type=track` — what could actually be played.
  final int? tracks;

  final String? error;

  bool get playable => (tracks ?? 0) > 0;

  String get verdict {
    if (error != null) return 'failed: $error';
    if (rows == null) return 'not fetched';
    if (rows == 0) return 'empty';
    return '$rows rows, $tracks tracks';
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
    required this.nearestAttempts,
    required this.stations,
    required this.nearestSeed,
  });

  /// Every way of asking for sonic neighbours that was tried.
  final List<NearestAttempt> nearestAttempts;

  /// What the Stations hub actually contains, unparsed.
  final List<StationRow> stations;

  /// The track the attempts were seeded from, named so a surprising answer can
  /// be checked by ear. Null when the cache held nothing to ask about.
  final String? nearestSeed;

  /// A way of asking that returned something. Non-null means the endpoint
  /// exists, the analysis has run, and only the request was wrong.
  NearestAttempt? get workingNearest =>
      nearestAttempts.where((a) => a.worked).firstOrNull;

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
      nearestAttempts: await _nearestAttempts(section),
      stations: await _stations(hubs),
      nearestSeed: await _seedName(),
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

  /// The rows of the Stations hub, which name the endpoint Plex itself uses.
  /// Every station the hub names, each one fetched. See [StationRow].
  Future<List<StationRow>> _stations(List<PlexHub> hubs) async {
    final named = [
      for (final hub in hubs)
        if (hub.kind == 'music.stations')
          for (final row in hub.items)
            (
              title: '${row['title']}',
              key: '${row['key']}',
              type: '${row['type']}',
            ),
    ];

    final fetched = <StationRow>[];
    for (final row in named) {
      try {
        final items = await _client.rawRows(row.key);
        fetched.add(
          StationRow(
            title: row.title,
            key: row.key,
            type: row.type,
            rows: items.length,
            tracks: items.where((i) => i['type'] == 'track').length,
          ),
        );
      } on Object catch (e) {
        fetched.add(
          StationRow(
            title: row.title,
            key: row.key,
            type: row.type,
            error: '$e',
          ),
        );
      }
    }
    return fetched;
  }

  Future<String?> _seedName() async {
    final seed = await _db.aTrackWorthProbing();
    if (seed == null) return null;
    return '${seed.artistTitle} — ${seed.title}  (${seed.ratingKey})';
  }

  /// Asks for sonic neighbours several ways, and reports each.
  ///
  /// Ordered so the first entry is exactly what the app ships and each one
  /// after it changes one thing. **Including `type=10`**, which the shipping
  /// client deliberately does not send: refusing to send a parameter the server
  /// might ignore is the right call in the app and the wrong call here, where
  /// the question is precisely which parameters this endpoint honours.
  ///
  /// Seeded from a track, its album and its artist in turn, because "similarity
  /// is measured per track" is an assumption of mine and not a measurement.
  Future<List<NearestAttempt>> _nearestAttempts(PlexSection section) async {
    final seed = await _db.aTrackWorthProbing();
    if (seed == null) return const [];

    Future<NearestAttempt> attempt(
      String label,
      String path, {
      Map<String, String>? query,
    }) async {
      try {
        final rows = await _client.rawRows(path, query: query);
        return NearestAttempt(
          label: label,
          path: path,
          rows: rows.length,
          tracks: rows.where((r) => r['type'] == 'track').length,
        );
      } on Object catch (e) {
        return NearestAttempt(
          label: label,
          path: path,
          rows: null,
          tracks: 0,
          error: '$e',
        );
      }
    }

    final track = seed.ratingKey;
    final album = seed.albumRatingKey;
    // **The seed type Plexamp actually offers.** It greys sonic radio out on a
    // song and enables it on an artist, which says the model is per artist and
    // not per track. Every attempt below it was seeded from a track because
    // "similarity is measured per track" was my assumption, asserted in three
    // doc comments and never once tested.
    final artist = album == null ? null : await _artistOf(album);

    return [
      await attempt(
        'As the app asks',
        '/library/metadata/$track/nearest',
        query: {'limit': '60'},
      ),
      await attempt('Without the limit', '/library/metadata/$track/nearest'),
      await attempt(
        'With type=10',
        '/library/metadata/$track/nearest',
        query: {'type': '10', 'limit': '60'},
      ),
      await attempt('Similar, not nearest', '/library/metadata/$track/similar'),
      if (album != null)
        await attempt(
          'Seeded from the album',
          '/library/metadata/$album/nearest',
        ),
      // The shape Plexamp's station URIs use, which the Stations rows above
      // should confirm or contradict.
      await attempt('As a station', '/library/metadata/$track/station/8'),
      await attempt(
        'The section stations endpoint',
        '/library/sections/${section.key}/stations',
      ),

      // Artist-seeded, which is the only form Plexamp offers. The station
      // numbers mirror the section stations, whose keys end in 1, 2, 3 and 8.
      if (artist != null) ...[
        await attempt(
          'Seeded from the artist',
          '/library/metadata/$artist/nearest',
        ),
        await attempt(
          'Artist as a station',
          '/library/metadata/$artist/station/8',
        ),
        await attempt(
          'Artist station 1',
          '/library/metadata/$artist/station/1',
        ),
        await attempt('Artist similar', '/library/metadata/$artist/similar'),
      ],
    ];
  }

  /// The artist a given album belongs to, for an artist-seeded attempt.
  Future<String?> _artistOf(String albumRatingKey) async {
    final rows = await _db.albumsByKeys([albumRatingKey]);
    return rows.firstOrNull?.artistRatingKey;
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
