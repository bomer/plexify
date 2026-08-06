import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../plex/plex_identity.dart';
import 'catalog_models.dart';

/// The MusicBrainz web service — the catalog of records that exist.
///
/// Free and needs no API key, which is why it is here rather than Discogs or
/// Last.fm, and it is what Lidarr, Picard and beets all use, so its ids line up
/// with whatever else touches this library.
///
/// **Two things about it are not optional and both cost a round of debugging if
/// missed.**
///
/// It rate-limits to roughly one request per second per source address, and it
/// answers **503** rather than 429 when you exceed that, which reads as the
/// service being down. Every request here goes through one serialised queue
/// with [minimumGap] between them, so the limit is respected by construction
/// rather than by callers remembering to.
///
/// And it refuses generic `User-Agent` strings, again with a 503. The agent
/// must name the application and carry a way to contact whoever runs it. A
/// default Dart HTTP agent gets nothing back at all.
///
/// Nothing here throws for an empty result. This is the *lower* tier of search:
/// local results are already on screen by the time it answers, and MusicBrainz
/// being slow, rate-limited or down must never be able to degrade searching the
/// library you already own.
class MusicBrainzClient {
  MusicBrainzClient({
    http.Client? httpClient,
    this.minimumGap = const Duration(milliseconds: 1100),
    Future<void> Function(Duration)? sleep,
  }) : _http = httpClient ?? http.Client(),
       _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  final http.Client _http;
  final Future<void> Function(Duration) _sleep;

  /// Slightly over a second, deliberately.
  ///
  /// The documented limit is one request per second averaged, and pacing at
  /// exactly one second means clock jitter puts a request over the line every
  /// so often. The hundred milliseconds buy a limit that is never argued about
  /// for a delay nobody perceives — the local half of search has already
  /// rendered.
  final Duration minimumGap;

  static const _base = 'https://musicbrainz.org/ws/2';

  /// Names the application and how to reach its author.
  ///
  /// MusicBrainz's policy requires this and enforces it with a 503. The URL is
  /// the project itself rather than a personal address, which is what the
  /// policy asks for.
  static const userAgent =
      'Plexify/${PlexIdentity.version} '
      '( https://github.com/bomer/plexify )';

  /// Requests still to be made, drained one at a time.
  ///
  /// A queue rather than a semaphore because the ordering matters: typing
  /// "radiohead" fires several searches and the last one is the one the user is
  /// waiting for, but each earlier one still has to be paced. Callers debounce
  /// on top of this; this guarantees the limit even when they forget.
  Future<void> _chain = Future<void>.value();
  DateTime? _lastRequestAt;

  /// One in-flight request per URL, so two screens asking the same question at
  /// once cost one round trip rather than two paced ones.
  final _inFlight = <String, Future<Map<String, dynamic>?>>{};

  int get requests => _requests;
  int _requests = 0;

  String? get lastError => _lastError;
  String? _lastError;

  void close() => _http.close();

  /// Release groups matching a free-text query.
  ///
  /// The query is sent as a Lucene expression, which is what the endpoint
  /// speaks, so anything the user typed is escaped before it goes in — an
  /// unbalanced quote or a bare `:` would otherwise turn a search into a 400.
  Future<List<CatalogRelease>> searchReleaseGroups(
    String query, {
    int limit = 25,
  }) async {
    final cleaned = _escapeLucene(query.trim());
    if (cleaned.isEmpty) return const [];

    final json = await _get('$_base/release-group', {
      'query': cleaned,
      'fmt': 'json',
      'limit': '$limit',
    });
    return _releases(json);
  }

  /// Everything an artist has released, by their MusicBrainz id.
  ///
  /// Paginated, because a long career runs past the 100-item page limit and a
  /// discography that silently stops at 100 looks like a complete one. Bounded
  /// at [maxPages] all the same: this is paced at one request per second, so an
  /// artist with a thousand release groups would otherwise hold the queue for
  /// ten seconds while nothing else could be asked.
  Future<List<CatalogRelease>> releaseGroupsForArtist(
    String artistMbid, {
    int maxPages = 4,
  }) async {
    const pageSize = 100;
    final all = <CatalogRelease>[];

    for (var page = 0; page < maxPages; page++) {
      final json = await _get('$_base/release-group', {
        'artist': artistMbid,
        // Without this the artist credit is absent from every row, and the
        // results come back attributed to "Unknown artist" — which then fails
        // to match anything in the library and reports the whole discography
        // as missing.
        'inc': 'artist-credits',
        'fmt': 'json',
        'limit': '$pageSize',
        'offset': '${page * pageSize}',
      });
      if (json == null) break;

      final batch = _releases(json);
      all.addAll(batch);

      final total = json['release-group-count'];
      if (batch.length < pageSize) break;
      if (total is int && all.length >= total) break;
    }

    return all;
  }

  /// Resolves an artist name to a MusicBrainz id.
  ///
  /// Returns candidates rather than a single answer, because a name is not a
  /// key: "Genesis", "Nirvana" and "Alice" each match several real artists, and
  /// picking the first would attach one artist's discography to another's page
  /// often enough to be a bug. The caller decides how much confidence it wants.
  Future<List<CatalogArtist>> searchArtists(
    String name, {
    int limit = 5,
  }) async {
    final cleaned = _escapeLucene(name.trim());
    if (cleaned.isEmpty) return const [];

    final json = await _get('$_base/artist', {
      'query': cleaned,
      'fmt': 'json',
      'limit': '$limit',
    });
    if (json == null) return const [];

    final raw = json['artists'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(CatalogArtist.fromJson)
        .where((a) => a.mbid.isNotEmpty)
        .toList();
  }

  List<CatalogRelease> _releases(Map<String, dynamic>? json) {
    final raw = json?['release-groups'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(CatalogRelease.fromJson)
        .where((r) => r.mbid.isNotEmpty)
        .toList();
  }

  /// One paced request. Null on any failure, never an exception.
  Future<Map<String, dynamic>?> _get(String path, Map<String, String> query) {
    final uri = Uri.parse(path).replace(queryParameters: query);
    final key = uri.toString();

    final existing = _inFlight[key];
    if (existing != null) return existing;

    // Chained rather than fired: each request waits for the one before it to
    // finish *and* for the gap to elapse. Appending to `_chain` is what makes
    // that ordering total rather than best-effort.
    final pending = _chain.then((_) => _paced(uri));
    _chain = pending.then((_) {}, onError: (_) {});
    _inFlight[key] = pending;
    return pending.whenComplete(() => _inFlight.remove(key));
  }

  Future<Map<String, dynamic>?> _paced(Uri uri) async {
    final last = _lastRequestAt;
    if (last != null) {
      final since = DateTime.now().difference(last);
      if (since < minimumGap) await _sleep(minimumGap - since);
    }
    _lastRequestAt = DateTime.now();
    _requests++;

    // Retried once, and only once. A 503 here means either the rate limit or a
    // rejected user agent; the first is worth waiting out, and the second will
    // never succeed however many times it is asked. A loop would turn a
    // configuration mistake into a hammering.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _http.get(
          uri,
          headers: const {
            'User-Agent': userAgent,
            'Accept': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            _lastError = null;
            return decoded;
          }
          _lastError = 'MusicBrainz returned an unexpected shape';
          return null;
        }

        _lastError = response.statusCode == 503
            ? 'MusicBrainz is rate limiting or refused the user agent (503)'
            : 'MusicBrainz answered HTTP ${response.statusCode}';

        if (response.statusCode != 503) return null;
        if (attempt == 0) await _sleep(minimumGap);
      } on Object catch (e) {
        _lastError = '$e';
        return null;
      }
    }
    return null;
  }

  /// Escapes the characters Lucene treats as syntax.
  ///
  /// An apostrophe is fine; a bare `:` or an unbalanced `"` is a 400, and album
  /// titles contain both. Escaped rather than stripped so "Where Are We Now?"
  /// still searches for the words it contains.
  static String _escapeLucene(String input) {
    const special = r'+-&|!(){}[]^"~*?:\/';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (special.contains(char)) buffer.write(r'\');
      buffer.write(char);
    }
    return buffer.toString();
  }
}
