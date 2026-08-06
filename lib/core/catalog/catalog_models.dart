/// Albums that exist in the world, as opposed to albums you own.
///
/// The library models in `plex_models.dart` describe what Plex holds. These
/// describe what MusicBrainz knows about, which is a different question with a
/// different key: a release group has an MBID and no `ratingKey`, and it may
/// well never become a row in the local cache.
///
/// Kept deliberately separate rather than reusing [PlexAlbum] with null fields.
/// Two things that look alike and behave differently are worth two types: a
/// catalog release cannot be played, cannot be rated, and its identifier means
/// nothing to the server. Folding them together would put those distinctions
/// into null checks scattered across the UI.
library;

/// What MusicBrainz calls a release group's primary type.
///
/// Only the ones worth showing are named. Everything else — broadcasts, "other"
/// — falls into [ReleaseKind.other] and is filtered out by default, because a
/// well-catalogued artist has far more of those than actual albums and they
/// bury the records someone is looking for.
enum ReleaseKind {
  album,
  ep,
  single,
  other;

  static ReleaseKind parse(String? raw) => switch (raw?.toLowerCase()) {
    'album' => ReleaseKind.album,
    'ep' => ReleaseKind.ep,
    'single' => ReleaseKind.single,
    _ => ReleaseKind.other,
  };
}

/// One release group: a record, independent of which pressing you have.
///
/// Release *group* rather than release, deliberately. A release is a specific
/// issue — the 1997 UK CD, the 2008 Japanese reissue, the vinyl — and a
/// popular album has dozens. Nobody browsing a discography wants to see the
/// same album twenty times, and Plex's own `mbid`, where it has one, is a
/// release-group id too, so grouping is also what makes de-duplication line up.
class CatalogRelease {
  const CatalogRelease({
    required this.mbid,
    required this.title,
    required this.artist,
    this.artistMbid,
    this.year,
    this.kind = ReleaseKind.album,
    this.secondaryTypes = const [],
  });

  /// The MusicBrainz release-group id. Stable, and the primary key everywhere.
  final String mbid;

  final String title;
  final String artist;
  final String? artistMbid;

  /// From `first-release-date`, which may be a bare year, a year-month, or a
  /// full date depending on how well catalogued the record is.
  final int? year;

  final ReleaseKind kind;

  /// `Compilation`, `Live`, `Remix`, `Soundtrack` and friends.
  ///
  /// Held as given rather than parsed into an enum: they are only ever used to
  /// decide whether to *exclude* something, and an unrecognised one should be
  /// treated as a reason to hide, not silently dropped.
  final List<String> secondaryTypes;

  /// Whether this is the kind of record a discography should lead with.
  ///
  /// Studio albums and EPs with no secondary type. A greatest-hits package and
  /// a live bootleg are both legitimately release groups and both are noise on
  /// a "what am I missing" list — an artist with fifteen albums routinely has
  /// sixty compilations, and showing them makes the list unusable rather than
  /// more complete. They are still reachable through search.
  bool get isPrimaryWork =>
      (kind == ReleaseKind.album || kind == ReleaseKind.ep) &&
      secondaryTypes.isEmpty;

  /// Parses one release group from the MusicBrainz web service.
  ///
  /// Tolerant in the same way [PlexAlbum] is, and for the same reason: fields
  /// are absent rather than null, and `artist-credit` is missing entirely
  /// unless the request asked for it.
  factory CatalogRelease.fromJson(Map<String, dynamic> json) {
    final credit = json['artist-credit'];
    var artistName = '';
    String? artistMbid;
    if (credit is List && credit.isNotEmpty) {
      final first = credit.first;
      if (first is Map<String, dynamic>) {
        artistName = _str(first['name']) ?? '';
        final artist = first['artist'];
        if (artist is Map<String, dynamic>) {
          artistName = artistName.isEmpty
              ? _str(artist['name']) ?? ''
              : artistName;
          artistMbid = _str(artist['id']);
        }
      }
    }

    final secondary = json['secondary-types'];

    return CatalogRelease(
      mbid: _str(json['id']) ?? '',
      title: _str(json['title']) ?? 'Untitled',
      artist: artistName.isEmpty ? 'Unknown artist' : artistName,
      artistMbid: artistMbid,
      year: _year(_str(json['first-release-date'])),
      kind: ReleaseKind.parse(_str(json['primary-type'])),
      secondaryTypes: secondary is List
          ? secondary.map((t) => '$t').where((t) => t.isNotEmpty).toList()
          : const [],
    );
  }

  /// `1997`, `1997-05`, `1997-05-21` — all yield 1997. A malformed or absent
  /// date yields null rather than a zero that would sort before everything.
  static int? _year(String? date) {
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }
}

/// An artist as MusicBrainz knows them, used only to resolve a name to an MBID.
///
/// [score] is MusicBrainz's own 0–100 match confidence. It matters because
/// resolving "Genesis" or "Nirvana" returns several real artists, and taking
/// the first without looking at the score picks an obscure one often enough to
/// be a bug rather than an edge case.
class CatalogArtist {
  const CatalogArtist({
    required this.mbid,
    required this.name,
    required this.score,
    this.disambiguation,
  });

  final String mbid;
  final String name;
  final int score;

  /// MusicBrainz's own note distinguishing same-named artists — "UK punk band",
  /// "90s trance producer". Shown when a choice has to be offered.
  final String? disambiguation;

  factory CatalogArtist.fromJson(Map<String, dynamic> json) => CatalogArtist(
    mbid: _str(json['id']) ?? '',
    name: _str(json['name']) ?? '',
    score: _int(json['score']) ?? 0,
    disambiguation: _str(json['disambiguation']),
  );
}

String? _str(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : v;
  return v.toString();
}

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is String) return int.tryParse(v);
  return null;
}
