import 'dart:convert';

import 'package:http/http.dart' as http;

import 'plex_identity.dart';
import 'plex_models.dart';
import 'plex_server.dart';

/// One page of results, with the total the server reports.
///
/// [totalSize] is what makes a real progress indicator possible — without it a
/// first sync of tens of thousands of tracks can only show a spinner.
class PlexPage<T> {
  const PlexPage({required this.items, required this.totalSize});

  final List<T> items;
  final int totalSize;
}

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

  /// One page of a section's contents, for bulk sync.
  ///
  /// Sorted by `addedAt` ascending and paginated by container headers. Ordering
  /// matters: a stable sort means an interrupted sync can resume from an offset
  /// without skipping or repeating rows, which a default (unspecified) order
  /// would not guarantee.
  ///
  /// [minUpdatedAt] restricts the page to rows Plex changed at or after that
  /// timestamp, which is what turns this into a delta sync rather than a full
  /// one.
  Future<PlexPage<T>> sectionPage<T>(
    String sectionKey, {
    required int type,
    required T Function(Map<String, dynamic>) parse,
    int start = 0,
    int size = 200,
    int? minUpdatedAt,
  }) async {
    final container = await _getContainer(
      '/library/sections/$sectionKey/all',
      query: {
        'type': '$type',
        'sort': 'addedAt:asc',
        if (minUpdatedAt != null && minUpdatedAt > 0)
          'updatedAt>=': '$minUpdatedAt',
      },
      extraHeaders: {
        'X-Plex-Container-Start': '$start',
        'X-Plex-Container-Size': '$size',
      },
    );

    return PlexPage<T>(
      items: _listOf(container, 'Metadata').map(parse).toList(),
      // totalSize appears when container headers are used; fall back to size
      // so a server that omits it still terminates the loop correctly.
      totalSize:
          _asInt(container['totalSize']) ?? _asInt(container['size']) ?? 0,
    );
  }

  /// Sets or clears an item's star rating.
  ///
  /// [rating] is Plex's 0–10 scale. Pass [PlexRating.clear] to unrate — Plex
  /// treats -1 as "remove", whereas 0 would store an explicit zero-star rating,
  /// which is a different thing and would then match rating filters.
  ///
  /// Works for tracks, albums and artists; they all share the endpoint.
  Future<void> rate(String ratingKey, int rating) async {
    final uri = Uri.parse('${_server.baseUrl}/:/rate').replace(
      queryParameters: {
        'identifier': 'com.plexapp.plugins.library',
        'key': ratingKey,
        'rating': '$rating',
      },
    );

    final response = await _http.put(
      uri,
      headers: _identity.headers(token: _server.token),
    );

    if (response.statusCode >= 400) {
      throw PlexClientException(
        'Could not save your rating (HTTP ${response.statusCode})',
      );
    }
  }

  /// Raw metadata for a single item, or null if the server no longer has it.
  ///
  /// Push notifications carry a ratingKey and a type, never the metadata, so
  /// this is what turns an event into something storable.
  ///
  /// A 404 becomes null — the item is genuinely gone. Every other failure
  /// throws, and that distinction matters: treating a timeout as "deleted"
  /// would let a network blip silently empty the cache.
  Future<Map<String, dynamic>?> metadataItem(String ratingKey) async {
    try {
      final container = await _getContainer('/library/metadata/$ratingKey');
      final items = _listOf(container, 'Metadata');
      return items.isEmpty ? null : items.first;
    } on PlexClientException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// One artist's albums, via the metadata children endpoint.
  Future<List<PlexAlbum>> albumsForArtist(String artistRatingKey) async {
    final container = await _getContainer(
      '/library/metadata/$artistRatingKey/children',
    );
    return _listOf(container, 'Metadata').map(PlexAlbum.fromJson).toList();
  }

  /// Audio playlists on the server.
  ///
  /// Not scoped to a library section — playlists live at the account level, so
  /// this is a separate sync pass from the section walk.
  Future<List<PlexPlaylist>> playlists() async {
    final container = await _getContainer(
      '/playlists',
      query: {'playlistType': 'audio'},
    );
    return _listOf(container, 'Metadata').map(PlexPlaylist.fromJson).toList();
  }

  /// Tracks in a playlist, in playlist order.
  ///
  /// Order is significant and must be preserved as given: playlists are
  /// arranged, not sorted.
  Future<List<PlexTrack>> playlistItems(String playlistRatingKey) async {
    final container = await _getContainer(
      '/playlists/$playlistRatingKey/items',
    );
    return _listOf(container, 'Metadata').map(PlexTrack.fromJson).toList();
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
    final uri = Uri.parse(
      '${_server.baseUrl}$partKey',
    ).replace(queryParameters: {'X-Plex-Token': _server.token});
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
        statusCode: response.statusCode,
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

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
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
  const PlexClientException(this.message, {this.statusCode});
  final String message;

  /// The HTTP status, when the failure came from a response rather than the
  /// transport. Callers distinguish 404 — the item is genuinely gone — from
  /// everything else, which is a reason to leave the cache alone.
  final int? statusCode;

  @override
  String toString() => message;
}
