/// Data models for the Plex API.
///
/// Plex's JSON is loosely typed — the same field can come back as an int or a
/// string depending on endpoint and server version, and optional fields are
/// simply absent rather than null. Every model here parses defensively through
/// the helpers at the bottom of this file rather than casting directly.
library;

/// One way of reaching a Plex server.
///
/// A single server usually advertises several: a LAN address, a public address,
/// and a plex.tv relay. They are not equally good — see [PlexServer] for how we
/// choose between them.
class PlexConnection {
  const PlexConnection({
    required this.uri,
    required this.local,
    required this.relay,
  });

  final String uri;

  /// True for LAN addresses. Preferred: fastest, and lets us direct-play
  /// original files without transcoding.
  final bool local;

  /// True for plex.tv relay connections. These are bandwidth-limited by Plex
  /// and should only ever be a last resort.
  final bool relay;

  factory PlexConnection.fromJson(Map<String, dynamic> json) {
    return PlexConnection(
      uri: _str(json['uri']) ?? '',
      local: _bool(json['local']),
      relay: _bool(json['relay']),
    );
  }
}

/// A server (or other device) returned by plex.tv's resources endpoint.
class PlexResource {
  const PlexResource({
    required this.name,
    required this.clientIdentifier,
    required this.provides,
    required this.owned,
    required this.accessToken,
    required this.connections,
  });

  final String name;
  final String clientIdentifier;

  /// Comma-separated capabilities. We only care about resources providing
  /// "server"; the same account also returns players, controllers etc.
  final String provides;

  final bool owned;

  /// Per-server token. Distinct from the account token — use this one when
  /// talking to this server.
  final String? accessToken;

  final List<PlexConnection> connections;

  bool get isServer => provides.split(',').contains('server');

  factory PlexResource.fromJson(Map<String, dynamic> json) {
    final rawConnections = json['connections'];
    return PlexResource(
      name: _str(json['name']) ?? 'Unknown server',
      clientIdentifier: _str(json['clientIdentifier']) ?? '',
      provides: _str(json['provides']) ?? '',
      owned: _bool(json['owned']),
      accessToken: _str(json['accessToken']),
      connections: rawConnections is List
          ? rawConnections
                .whereType<Map<String, dynamic>>()
                .map(PlexConnection.fromJson)
                .where((c) => c.uri.isNotEmpty)
                .toList()
          : const [],
    );
  }
}

/// A library section. We only ever want the one with [type] == 'artist'.
class PlexSection {
  const PlexSection({
    required this.key,
    required this.type,
    required this.title,
    this.updatedAt,
    this.scannedAt,
  });

  final String key;
  final String type;
  final String title;

  /// Bumped whenever the section's contents change. Polling just these two
  /// fields is the cheap change-detection tier of the sync design — one small
  /// response tells us whether a delta sync is worth doing at all.
  final int? updatedAt;
  final int? scannedAt;

  bool get isMusic => type == 'artist';

  factory PlexSection.fromJson(Map<String, dynamic> json) {
    return PlexSection(
      key: _str(json['key']) ?? '',
      type: _str(json['type']) ?? '',
      title: _str(json['title']) ?? '',
      updatedAt: _int(json['updatedAt']),
      scannedAt: _int(json['scannedAt']),
    );
  }
}

/// An album. Plex calls these type=9 metadata items.
class PlexAlbum {
  const PlexAlbum({
    required this.ratingKey,
    required this.title,
    required this.artist,
    this.thumb,
    this.year,
    this.addedAt,
  });

  final String ratingKey;
  final String title;

  /// Plex exposes the album artist as `parentTitle`.
  final String artist;

  /// Relative path, e.g. `/library/metadata/1234/thumb/1699999999`. Must be run
  /// through the photo transcoder with a token before it can be displayed —
  /// see `PlexClient.artworkUrl`.
  final String? thumb;

  final int? year;
  final int? addedAt;

  factory PlexAlbum.fromJson(Map<String, dynamic> json) {
    return PlexAlbum(
      ratingKey: _str(json['ratingKey']) ?? '',
      title: _str(json['title']) ?? 'Unknown album',
      artist: _str(json['parentTitle']) ?? 'Unknown artist',
      thumb: _str(json['thumb']),
      year: _int(json['year']),
      addedAt: _int(json['addedAt']),
    );
  }
}

/// A track, with the information needed to actually play it.
class PlexTrack {
  const PlexTrack({
    required this.ratingKey,
    required this.title,
    required this.index,
    required this.durationMs,
    required this.album,
    required this.artist,
    this.partKey,
    this.container,
    this.thumb,
  });

  final String ratingKey;
  final String title;

  /// Track number within the album.
  final int index;

  final int durationMs;
  final String album;
  final String artist;

  /// Path to the actual file, e.g. `/library/parts/5678/1699.../file.flac`.
  ///
  /// This is what makes direct play possible: append a token and stream the
  /// original bytes, no transcoding. Null means the track has no playable part,
  /// which shouldn't happen but we degrade rather than crash.
  final String? partKey;

  /// Container format — 'flac', 'mp3', 'm4a'. Used later to decide whether the
  /// current platform can direct-play or needs a transcode.
  final String? container;

  final String? thumb;

  bool get isPlayable => partKey != null && partKey!.isNotEmpty;

  Duration get duration => Duration(milliseconds: durationMs);

  factory PlexTrack.fromJson(Map<String, dynamic> json) {
    // Media -> Part -> key is the path to the file. Both levels are lists and
    // either can be missing; take the first entry of each.
    String? partKey;
    String? container;

    final media = json['Media'];
    if (media is List && media.isNotEmpty) {
      final firstMedia = media.first;
      if (firstMedia is Map<String, dynamic>) {
        container = _str(firstMedia['container']);
        final parts = firstMedia['Part'];
        if (parts is List && parts.isNotEmpty) {
          final firstPart = parts.first;
          if (firstPart is Map<String, dynamic>) {
            partKey = _str(firstPart['key']);
            container ??= _str(firstPart['container']);
          }
        }
      }
    }

    return PlexTrack(
      ratingKey: _str(json['ratingKey']) ?? '',
      title: _str(json['title']) ?? 'Unknown track',
      index: _int(json['index']) ?? 0,
      durationMs: _int(json['duration']) ?? 0,
      album: _str(json['parentTitle']) ?? '',
      artist: _str(json['grandparentTitle']) ?? _str(json['originalTitle']) ?? '',
      partKey: partKey,
      container: container,
      thumb: _str(json['thumb']) ?? _str(json['parentThumb']),
    );
  }
}

// ---------------------------------------------------------------------------
// Tolerant parsing helpers.
//
// Plex is inconsistent about types across endpoints and server versions, so we
// coerce rather than cast. A malformed field should degrade one value, never
// throw and lose the whole response.
// ---------------------------------------------------------------------------

String? _str(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : v;
  return v.toString();
}

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

bool _bool(dynamic v) {
  if (v is bool) return v;
  if (v is int) return v == 1;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}
