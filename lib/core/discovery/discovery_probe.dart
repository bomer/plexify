import '../db/app_database.dart';
import '../plex/plex_client.dart';
import '../plex/plex_models.dart';

/// One genre, and how many albums are actually behind it.
class GenreSample {
  const GenreSample({required this.title, required this.albums});
  final String title;
  final int albums;
}

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

/// What this server actually offers for a fuller Home screen.
class DiscoveryReport {
  const DiscoveryReport({
    required this.hubs,
    required this.genreCount,
    required this.genreSamples,
    required this.historyRows,
    required this.historyAttempts,
    required this.oldestPlay,
    required this.newestPlay,
    required this.months,
  });

  /// The hubs `/hubs/sections/{id}` published. Empty means the endpoint
  /// answered with nothing, or refused, which the client does not distinguish
  /// because nothing depends on it.
  final List<PlexHub> hubs;

  final int genreCount;

  /// The first few genres with their album counts, which is what says whether
  /// a genre row can be filled at all.
  final List<GenreSample> genreSamples;

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

  /// How many genres to price. Each costs one small request, and the point is
  /// a sense of the distribution rather than a full census.
  static const genresSampled = 8;

  Future<DiscoveryReport> run(PlexSection section) async {
    final hubs = await _client.sectionHubs(section.key);

    final genres = await _client.genres(section.key);
    final samples = <GenreSample>[];
    for (final genre in genres.take(genresSampled)) {
      try {
        final counted = await _client.genreAlbums(
          section.key,
          genre.key,
          size: 0,
        );
        samples.add(GenreSample(title: genre.title, albums: counted.totalSize));
      } on Object {
        samples.add(GenreSample(title: genre.title, albums: -1));
      }
    }

    final plays = await _client.playHistory(section.key);
    final attempts = await _historyAttempts(section);
    final now = _now();

    return DiscoveryReport(
      hubs: hubs,
      genreCount: genres.length,
      genreSamples: samples,
      historyRows: plays.length,
      historyAttempts: attempts,
      oldestPlay: _at(plays.isEmpty ? null : plays.last.viewedAt),
      newestPlay: _at(plays.isEmpty ? null : plays.first.viewedAt),
      months: [
        await _month(plays, DateTime(now.year, now.month), 'This month'),
        await _month(plays, DateTime(now.year, now.month - 1), 'Last month'),
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

  Future<MonthSample> _month(
    List<PlexPlay> plays,
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
      final key = play.albumRatingKey;
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
