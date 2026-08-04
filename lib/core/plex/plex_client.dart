import 'dart:convert';

import 'package:http/http.dart' as http;

import 'plex_identity.dart';
import 'plex_models.dart';
import 'plex_server.dart';

/// Plex Media Server API client.
///
/// Everything here talks to a specific server via [PlexServer.baseUrl]. Account
/// level calls (auth, discovery) live in `plex_auth.dart` / `plex_server.dart`.
class PlexClient {
  PlexClient({
    required PlexServer server,
    required PlexIdentity identity,
    http.Client? httpClient,
  }) : _server = server,
       _identity = identity,
       _http = httpClient ?? http.Client();

  final PlexServer _server;
  final PlexIdentity _identity;
  final http.Client _http;

  PlexServer get server => _server;

  /// Releases the underlying HTTP connections.
  ///
  /// Providers that construct a client must call this on dispose — otherwise
  /// every reconnection leaks a connection pool.
  void close() => _http.close();

  /// Plex metadata type numbers. Used as `?type=` on section listings.
  static const typeArtist = 8;
  static const typeAlbum = 9;
  static const typeTrack = 10;

  /// All library sections. Cheap, and the `updatedAt`/`scannedAt` fields drive
  /// the change-detection tier of the sync design.
  Future<List<PlexSection>> sections() async {
    final container = await _getContainer('/library/sections');
    return _listOf(container, 'Directory').map(PlexSection.fromJson).toList();
  }

  /// The music section, or null if the server has none.
  ///
  /// If there are several, the first wins — v1 assumes a single music library.
  Future<PlexSection?> musicSection() async {
    final all = await sections();
    for (final section in all) {
      if (section.isMusic) return section;
    }
    return null;
  }

  /// Albums in a section, newest first.
  ///
  /// Paginated via Plex's container headers rather than query parameters, which
  /// is what the server actually honours.
  Future<List<PlexAlbum>> albums(
    String sectionKey, {
    int start = 0,
    int size = 100,
  }) async {
    final container = await _getContainer(
      '/library/sections/$sectionKey/all',
      query: {'type': '$typeAlbum', 'sort': 'addedAt:desc'},
      extraHeaders: {
        'X-Plex-Container-Start': '$start',
        'X-Plex-Container-Size': '$size',
      },
    );
    return _listOf(container, 'Metadata').map(PlexAlbum.fromJson).toList();
  }

  /// Tracks on an album, in disc/track order as Plex returns them.
  Future<List<PlexTrack>> tracks(String albumRatingKey) async {
    final container = await _getContainer(
      '/library/metadata/$albumRatingKey/children',
    );
    return _listOf(container, 'Metadata').map(PlexTrack.fromJson).toList();
  }

  /// A displayable artwork URL for a `thumb` path.
  ///
  /// Plex's thumb paths aren't directly fetchable — they must go through the
  /// photo transcoder, which also lets us request a sensible size instead of
  /// pulling full-resolution art into a list cell.
  String? artworkUrl(String? thumb, {int width = 300, int height = 300}) {
    if (thumb == null || thumb.isEmpty) return null;
    final inner = '${_server.baseUrl}$thumb';
    final uri = Uri.parse('${_server.baseUrl}/photo/:/transcode').replace(
      queryParameters: {
        'width': '$width',
        'height': '$height',
        'minSize': '1',
        'upscale': '1',
        'url': inner,
        'X-Plex-Token': _server.token,
      },
    );
    return uri.toString();
  }

  /// Direct-play URL for [track] — the original file, untouched.
  ///
  /// The token goes in the query string rather than a header because this URL
  /// is handed to the audio engine (ExoPlayer / libmpv), which does its own
  /// HTTP and won't carry our headers.
  ///
  /// Returns null for tracks with no playable part.
  String? directPlayUrl(PlexTrack track) {
    final partKey = track.partKey;
    if (partKey == null || partKey.isEmpty) return null;
    final uri = Uri.parse('${_server.baseUrl}$partKey').replace(
      queryParameters: {'X-Plex-Token': _server.token},
    );
    return uri.toString();
  }

  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> _getContainer(
    String path, {
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse(
      '${_server.baseUrl}$path',
    ).replace(queryParameters: query);

    final response = await _http.get(
      uri,
      headers: {
        ..._identity.headers(token: _server.token),
        ...?extraHeaders,
      },
    );

    if (response.statusCode == 401) {
      throw const PlexClientException(
        'Plex rejected the token. You may need to sign in again.',
      );
    }
    if (response.statusCode != 200) {
      throw PlexClientException(
        'Plex request failed: $path (HTTP ${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw PlexClientException('Unexpected response shape from $path');
    }
    final container = decoded['MediaContainer'];
    if (container is! Map<String, dynamic>) {
      throw PlexClientException('No MediaContainer in response from $path');
    }
    return container;
  }

  /// Plex omits list keys entirely when empty rather than returning `[]`, so an
  /// absent key is a normal empty result, not an error.
  static List<Map<String, dynamic>> _listOf(
    Map<String, dynamic> container,
    String key,
  ) {
    final raw = container[key];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }
}

class PlexClientException implements Exception {
  const PlexClientException(this.message);
  final String message;

  @override
  String toString() => message;
}
