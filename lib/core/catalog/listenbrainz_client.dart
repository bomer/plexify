import 'dart:convert';

import 'package:http/http.dart' as http;

import '../http/bounded_client.dart';
import '../plex/plex_identity.dart';

/// How much a record is actually listened to.
class ReleasePopularity {
  const ReleasePopularity({required this.listens, required this.listeners});

  /// Total plays across everyone who reports to ListenBrainz.
  final int listens;

  /// How many distinct people. Worth carrying separately: a thousand plays by
  /// four people is a different fact from a thousand plays by four hundred.
  final int listeners;

  bool get isKnown => listens > 0 || listeners > 0;
}

/// ListenBrainz, which knows what people actually play.
///
/// **Why this and not a star rating.** MusicBrainz has its own rating system
/// and it is far too sparsely populated to show: most release groups have no
/// votes at all, so a discography would render as a column of blanks with two
/// numbers in it. Listen counts exist for essentially everything.
///
/// Same foundation as MusicBrainz, free, and needs no API key, which is why it
/// is here rather than Last.fm or Discogs. The `User-Agent` requirement is the
/// same and is honoured for the same reason.
///
/// **Nothing here throws.** Popularity is decoration on pages that already work
/// without it, and the rule the whole catalog tier is built under is that the
/// lower tier must never be able to make the upper one worse. A failure is an
/// empty map and a page that looks like it did yesterday.
class ListenBrainzClient {
  ListenBrainzClient({
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 10),
  }) : _http = BoundedClient(httpClient ?? http.Client(), requestTimeout);

  final http.Client _http;

  static const _base = 'https://api.listenbrainz.org/1';

  /// Named, for the same reason MusicBrainz insists on it. They are run by the
  /// same people.
  static const userAgent =
      'Plexify/${PlexIdentity.version} '
      '( https://github.com/bomer/plexify )';

  void close() => _http.close();

  String? get lastError => _lastError;
  String? _lastError;

  /// Listen counts for a set of release groups, keyed by MBID.
  ///
  /// **Batched, and that is the point.** A discography is one request rather
  /// than one per record, using the exact ids already on screen. The per-artist
  /// endpoint exists and would need the artist resolved first and then filtered
  /// back down to what is being shown.
  ///
  /// An id absent from the answer is **absent from the result**, not zero.
  /// "Nobody has heard it" and "we were not told" are different claims, and
  /// only one of them should draw an empty bar.
  Future<Map<String, ReleasePopularity>> popularityFor(
    Iterable<String> releaseGroupMbids,
  ) async {
    final ids = {
      for (final mbid in releaseGroupMbids)
        if (mbid.trim().isNotEmpty) mbid.trim(),
    };
    if (ids.isEmpty) return const {};

    try {
      final response = await _http.post(
        Uri.parse('$_base/popularity/release-group'),
        headers: const {
          'User-Agent': userAgent,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'release_group_mbids': ids.toList()}),
      );

      if (response.statusCode != 200) {
        _lastError = 'ListenBrainz answered HTTP ${response.statusCode}';
        return const {};
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        _lastError = 'ListenBrainz returned an unexpected shape';
        return const {};
      }

      _lastError = null;
      return {
        for (final row in decoded.whereType<Map<String, dynamic>>())
          ?_str(row['release_group_mbid']): ReleasePopularity(
            listens: _int(row['total_listen_count']) ?? 0,
            listeners: _int(row['total_user_count']) ?? 0,
          ),
      };
    } on Object catch (e) {
      // Swallowed on purpose. See the class comment: this must never be able to
      // take a working page down with it.
      _lastError = '$e';
      return const {};
    }
  }
}

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v is String ? v : v.toString();
  return s.isEmpty ? null : s;
}

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
