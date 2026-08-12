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

/// An audio playlist.
///
/// Playlists sit outside the library section hierarchy — they come from
/// `/playlists`, not `/library/sections/{id}/all`, and so are synced separately.
class PlexPlaylist {
  const PlexPlaylist({
    required this.ratingKey,
    required this.title,
    this.thumb,
    this.itemCount = 0,
    this.durationMs,
    this.updatedAt,
    this.lastViewedAt,
    this.smart = false,
  });

  /// True for Plex smart playlists, whose contents are generated from rules
  /// rather than fixed.
  final bool smart;

  final String ratingKey;
  final String title;

  /// Plex exposes playlist art as `composite` — a generated mosaic — rather
  /// than `thumb`. Using `thumb` here silently yields no artwork.
  final String? thumb;

  final int itemCount;
  final int? durationMs;
  final int? updatedAt;

  /// Drives the "recent playlists" list in the sidebar.
  final int? lastViewedAt;

  factory PlexPlaylist.fromJson(Map<String, dynamic> json) {
    return PlexPlaylist(
      ratingKey: _str(json['ratingKey']) ?? '',
      title: _str(json['title']) ?? 'Untitled playlist',
      thumb: _str(json['composite']) ?? _str(json['thumb']),
      itemCount: _int(json['leafCount']) ?? 0,
      durationMs: _int(json['duration']),
      updatedAt: _int(json['updatedAt']),
      lastViewedAt: _int(json['lastViewedAt']),
      smart: _bool(json['smart']),
    );
  }
}

/// A hub, which is Plex's own word for a titled row of things.
///
/// **The server publishes these and this app used to reimplement them.** A hand
/// rolled "More by {artist}", "More in {genre}" and "Most played in {month}"
/// were all built here, complete with two bugs, while `/hubs/sections` was
/// already offering the same three by name along with several nobody had
/// thought of: top albums from a decade, artists not played in five years,
/// sonic stations. The probe that was meant to prove hubs were useless proved
/// the opposite.
///
/// Nothing keys on an identifier. What a section offers varies by server
/// version and by whether sonic analysis has run, so a row is rendered because
/// it arrived with a title and some albums in it, not because it was
/// recognised.
class PlexHub {
  const PlexHub({
    required this.hubIdentifier,
    required this.title,
    required this.type,
    required this.size,
    this.context,
    this.albums = const [],
    this.artists = const [],
    this.items = const [],
  });

  /// The hub's rows exactly as sent, before anything was made of them.
  ///
  /// **Kept for [DiscoveryProbe] and nothing else.** Every typed field here
  /// throws away whatever it did not recognise, and for `music.stations` that
  /// is the entire row — including the `key` naming the endpoint Plex's own
  /// client calls to play one. That key is the only documentation of the sonic
  /// API that exists, and parsing it away is how it stayed unknown.
  final List<Map<String, dynamic>> items;

  /// The hub's items, when they are albums.
  final List<PlexAlbum> albums;

  /// The hub's items, when they are artists.
  ///
  /// `music.recent.played` is the server's own recently-played row and it is
  /// artists rather than albums, which is the entire reason this exists: it is
  /// a cross-device "jump back in" that Plex has already computed, and it was
  /// being dropped on the floor for want of a tile.
  final List<PlexArtist> artists;

  /// The hub's items, when they are stations. See [PlexStation].
  List<PlexStation> get stations => [
    for (final row in items)
      if (row['type'] == 'station') ?PlexStation.fromJson(row),
  ];

  /// Whether there is anything here this app knows how to draw.
  ///
  /// Stations and music videos parse to nothing. A heading with nothing under
  /// it is worse than an absent row.
  bool get hasItems =>
      albums.isNotEmpty || artists.isNotEmpty || stations.isNotEmpty;

  /// e.g. `home.music.recent`. Stable enough to key on, if it is there at all.
  final String hubIdentifier;

  final String title;

  /// `album`, `artist`, `track`, `playlist`, or `mixed`.
  final String type;

  /// How many items the hub carried.
  final int size;

  /// Plex's own hint at why the hub exists, e.g. `hub.music.recentlyAdded`.
  final String? context;

  /// The identifier with the section id taken off the end.
  ///
  /// **Plex suffixes every hub identifier with the section it belongs to**, so
  /// `music.recent.added` arrives as `music.recent.added.3`. Comparing the raw
  /// value against a known identifier therefore never matches, which is exactly
  /// how "Recently added" and "Recently Added in Music" ended up side by side
  /// on Home: the skip list was right and could not fire.
  ///
  /// Anything comparing against a known hub must use this rather than
  /// [hubIdentifier], which is only worth showing in the probe.
  String get kind => hubIdentifier.replaceFirst(RegExp(r'\.\d+$'), '');

  factory PlexHub.fromJson(Map<String, dynamic> json) {
    final items = json['Metadata'];
    final rows = items is List
        ? items.whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];
    final type = _str(json['type']) ?? '';

    return PlexHub(
      hubIdentifier: _str(json['hubIdentifier']) ?? '',
      title: _str(json['title']) ?? '',
      type: type,
      // `size` is what the hub says it holds and `rows` is what it sent, and
      // they disagree when the server pages a hub. The declared figure is the
      // honest one for the probe to report; the parsed rows are what can
      // actually be shown.
      size: _int(json['size']) ?? rows.length,
      context: _str(json['context']),
      items: rows,
      albums: type == 'album'
          ? rows.map(PlexAlbum.fromJson).toList()
          : const [],
      artists: type == 'artist'
          ? rows.map(PlexArtist.fromJson).toList()
          : const [],
    );
  }
}

/// One play, as the *server* recorded it.
///
/// This is what makes "most played in January" possible at all. Nothing local
/// can answer it: `PlaybackHistory` keeps one row per thing so it has no
/// counts, and it only knows about this device and only since it was written.
/// The server has every play from every client, going back years.
class PlexPlay {
  const PlexPlay({
    required this.trackRatingKey,
    required this.albumRatingKey,
    required this.artistRatingKey,
    required this.viewedAt,
    this.type,
  });

  /// `track`, `album`, and so on.
  ///
  /// **Filtered on here rather than in the request, which is what went wrong.**
  /// Asking the server for `type=10` seemed obvious, matches how a section
  /// listing is narrowed, and returns *nothing at all* from this endpoint: it
  /// answers 200 with an empty container, so the history looked empty on a
  /// server holding years of it. Measured by the discovery probe on 10 August
  /// 2026, which asked the same question with each narrowing removed: without
  /// `type` it returned rows immediately.
  ///
  /// Null keeps the row. A server that does not label its history is a reason
  /// to include everything, not to discard everything, which is the mistake
  /// this comment exists to stop being made twice.
  final String? type;

  bool get isTrack => type == null || type == 'track';

  final String trackRatingKey;

  /// `parentRatingKey`. Null on rows that are not tracks.
  final String? albumRatingKey;

  /// `grandparentRatingKey`.
  final String? artistRatingKey;

  /// Epoch seconds.
  final int viewedAt;

  factory PlexPlay.fromJson(Map<String, dynamic> json) {
    return PlexPlay(
      trackRatingKey: _str(json['ratingKey']) ?? '',
      albumRatingKey: _str(json['parentRatingKey']),
      artistRatingKey: _str(json['grandparentRatingKey']),
      viewedAt: _int(json['viewedAt']) ?? 0,
      type: _str(json['type']),
    );
  }
}

/// One of the server's own radio stations.
///
/// **Not a container you can fetch.** The `key` looks like an ordinary path —
/// `/library/sections/3/stations/1` — and every one of them 404s on a GET. It is
/// a *play queue source*: the only way to hear a station is to POST it to
/// `/playQueues` and play the tracks that come back. Reading it as a path is
/// what made the Stations hub look broken.
///
/// Rule-based rather than sonic, whatever the hub's name suggests. The four
/// this server publishes are everything, rarely played, by era and by album,
/// and none of them needs sonic analysis to exist.
class PlexStation {
  const PlexStation({required this.key, required this.title, this.thumb});

  /// The play queue source, e.g. `/library/sections/3/stations/1`.
  final String key;

  final String title;
  final String? thumb;

  static PlexStation? fromJson(Map<String, dynamic> json) {
    final key = _str(json['key']);
    if (key == null || key.isEmpty) return null;
    return PlexStation(
      key: key,
      title: _str(json['title']) ?? 'Radio',
      thumb: _str(json['thumb']) ?? _str(json['composite']),
    );
  }
}

/// An artist. Plex calls these type=8 metadata items.
class PlexArtist {
  const PlexArtist({
    required this.ratingKey,
    required this.title,
    this.thumb,
    this.updatedAt,
    this.addedAt,
    this.userRating,
  });

  final String ratingKey;
  final String title;
  final String? thumb;
  final int? updatedAt;
  final int? addedAt;

  /// Plex `userRating`, 0-10, null when unrated.
  final int? userRating;

  factory PlexArtist.fromJson(Map<String, dynamic> json) {
    return PlexArtist(
      ratingKey: _str(json['ratingKey']) ?? '',
      title: _str(json['title']) ?? 'Unknown artist',
      thumb: _str(json['thumb']),
      updatedAt: _int(json['updatedAt']),
      addedAt: _int(json['addedAt']),
      userRating: _int(json['userRating']),
    );
  }
}

/// An album. Plex calls these type=9 metadata items.
class PlexAlbum {
  const PlexAlbum({
    required this.ratingKey,
    required this.title,
    required this.artist,
    this.artistRatingKey,
    this.thumb,
    this.year,
    this.addedAt,
    this.updatedAt,
    this.lastViewedAt,
    this.userRating,
    this.mbid,
  });

  final String ratingKey;
  final String title;

  /// MusicBrainz release-group id, when Plex happens to know one.
  ///
  /// Usually it does not. Whether this is populated depends entirely on which
  /// agent scanned the library and what the file tags carried, so catalog
  /// matching treats it as the good path rather than the expected one and falls
  /// back to comparing normalised artist and title. See [OwnedIndex].
  final String? mbid;

  /// 0–10, or null when unrated. See [PlexRating].
  final int? userRating;

  /// Plex exposes the album artist as `parentTitle`.
  final String artist;

  /// `parentRatingKey` — links the album to its artist row.
  final String? artistRatingKey;

  /// Bumped whenever Plex changes the item. Delta sync asks only for rows at
  /// or after the last value we stored.
  final int? updatedAt;

  /// Drives "recently played".
  final int? lastViewedAt;

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
      artistRatingKey: _str(json['parentRatingKey']),
      thumb: _str(json['thumb']),
      year: _int(json['year']),
      addedAt: _int(json['addedAt']),
      updatedAt: _int(json['updatedAt']),
      lastViewedAt: _int(json['lastViewedAt']),
      userRating: _int(json['userRating']),
      mbid: _mbid(json),
    );
  }

  /// Digs a MusicBrainz id out of whichever shape this server uses.
  ///
  /// Three of them exist in the wild and which one appears depends on the
  /// agent. The modern music agent puts a `Guid` array on the item, one entry
  /// per external source, of which `mbid://` is one among Discogs and others.
  /// The legacy agent puts a single `guid` string on the item instead. And most
  /// libraries have neither, which is not an error — it is the common case, and
  /// why matching never depends on this.
  static String? _mbid(Map<String, dynamic> json) {
    final list = json['Guid'];
    if (list is List) {
      for (final entry in list) {
        if (entry is! Map) continue;
        final id = _str(entry['id']);
        if (id != null && id.startsWith('mbid://')) {
          return id.substring('mbid://'.length);
        }
      }
    }

    final guid = _str(json['guid']);
    if (guid != null && guid.startsWith('mbid://')) {
      return guid.substring('mbid://'.length);
    }
    return null;
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
    this.albumRatingKey,
    this.discIndex,
    this.partKey,
    this.container,
    this.partSizeBytes,
    this.thumb,
    this.updatedAt,
    this.addedAt,
    this.lastViewedAt,
    this.userRating,
  });

  /// `parentRatingKey` — links the track to its album row.
  final String? albumRatingKey;

  /// `parentIndex` — disc number on multi-disc releases.
  final int? discIndex;

  final int? updatedAt;
  final int? addedAt;
  final int? lastViewedAt;

  /// 0–10, or null when unrated. See [PlexRating].
  final int? userRating;

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

  /// Media > Part's own `size`, in bytes. Declared by Plex for a static file,
  /// unlike a live transcode's (see `TranscodeProbe`'s "declares the total
  /// size" check). Null means unknown, never zero.
  final int? partSizeBytes;

  final String? thumb;

  bool get isPlayable => partKey != null && partKey!.isNotEmpty;

  Duration get duration => Duration(milliseconds: durationMs);

  /// The source file's own bitrate, implied by its size and duration rather
  /// than declared anywhere — Plex does not send one directly. Null when
  /// either input is unknown, which `QualityPolicy` treats as "nothing
  /// measured yet", not as a reason to transcode.
  int? get sourceKbps {
    final bytes = partSizeBytes;
    if (bytes == null || bytes <= 0 || durationMs <= 0) return null;
    return (bytes * 8 / (durationMs / 1000) / 1000).round();
  }

  factory PlexTrack.fromJson(Map<String, dynamic> json) {
    // Media -> Part -> key is the path to the file. Both levels are lists and
    // either can be missing; take the first entry of each.
    String? partKey;
    String? container;
    int? partSizeBytes;

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
            partSizeBytes = _int(firstPart['size']);
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
      artist:
          _str(json['grandparentTitle']) ?? _str(json['originalTitle']) ?? '',
      albumRatingKey: _str(json['parentRatingKey']),
      discIndex: _int(json['parentIndex']),
      partKey: partKey,
      container: container,
      partSizeBytes: partSizeBytes,
      thumb: _str(json['thumb']) ?? _str(json['parentThumb']),
      updatedAt: _int(json['updatedAt']),
      addedAt: _int(json['addedAt']),
      lastViewedAt: _int(json['lastViewedAt']),
      userRating: _int(json['userRating']),
    );
  }
}

/// Star ratings.
///
/// Plex stores `userRating` on a 0–10 scale where 10 is five stars, and omits
/// the field entirely when nothing has been set. There is no separate
/// "favourite" concept for music — a favourite is simply a highly rated item.
abstract final class PlexRating {
  /// Plex's raw value for one star.
  static const perStar = 2;

  static const maxStars = 5;

  /// At or above this, an item counts as a favourite. Four stars.
  static const favouriteThreshold = 8;

  /// Sent to Plex to remove a rating.
  ///
  /// Not 0 — that stores an explicit zero-star rating, which is a distinct
  /// state and would still match rating filters.
  static const clear = -1;

  static int fromStars(int stars) => stars.clamp(0, maxStars) * perStar;

  /// Rounds to the nearest whole star. Plex permits half-star values, and
  /// ratings set by other clients may use them, so they must not be discarded.
  static int toStars(int? rating) =>
      rating == null ? 0 : (rating / perStar).round().clamp(0, maxStars);

  static bool isFavourite(int? rating) =>
      rating != null && rating >= favouriteThreshold;
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
