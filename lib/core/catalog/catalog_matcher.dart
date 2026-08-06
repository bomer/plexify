import '../db/normalise.dart';
import 'catalog_models.dart';

/// One album the library already holds, reduced to what matching needs.
///
/// A plain value rather than a drift row, so the matching rules can be tested
/// without a database and so the rules do not quietly acquire a dependency on
/// the schema.
class OwnedAlbum {
  const OwnedAlbum({required this.title, required this.artist, this.mbid});

  final String title;
  final String artist;

  /// MusicBrainz release-group id, when Plex knows one. Usually it does not:
  /// it depends on which agent scanned the library and what the file tags
  /// carried, so this is the good path and not the expected one.
  final String? mbid;
}

/// Decides whether a catalog release is already in the library.
///
/// This is the whole of #30, and the reason it is a class rather than a
/// function is that it is asked the same question a hundred times per screen:
/// building the two sets once and probing them is the difference between a
/// discography rendering instantly and one that walks the library per row.
///
/// **Two keys, in order of trust.**
///
/// The MBID is exact when both sides have one, and neither side usually does —
/// Plex only records it for some agents and some tags. Where it is present it
/// is believed outright.
///
/// Otherwise the normalised artist and title are compared. That is where the
/// real work is: file tags say *OK Computer (Collector's Edition)* and
/// MusicBrainz says *OK Computer*, and treating those as different records puts
/// an album you own at the top of a list of albums you do not.
class OwnedIndex {
  OwnedIndex(Iterable<OwnedAlbum> albums, {this.requireArtist = true}) {
    for (final album in albums) {
      final mbid = album.mbid;
      if (mbid != null && mbid.isNotEmpty) _mbids.add(mbid.toLowerCase());
      _titles.add(_key(album.artist, album.title));
    }
  }

  /// Whether the artist has to match as well as the title.
  ///
  /// True for search, where the whole catalog is in play and two records called
  /// *Greatest Hits* are routinely different records. False on an artist page,
  /// where every album passed in already belongs to that artist and the
  /// library's spelling of the name ("Beatles, The") need not agree with
  /// MusicBrainz's for the album itself to be the same album.
  final bool requireArtist;

  final _mbids = <String>{};
  final _titles = <String>{};

  bool owns(CatalogRelease release) {
    if (_mbids.contains(release.mbid.toLowerCase())) return true;
    return _titles.contains(_key(release.artist, release.title));
  }

  /// Releases from [candidates] that the library does not hold, in the order
  /// they were given.
  List<CatalogRelease> missingFrom(Iterable<CatalogRelease> candidates) {
    // Deduplicated on the way out as well as filtered. MusicBrainz can list the
    // same record under two release groups (a reissue catalogued separately),
    // and one of those slipping through shows the same missing album twice.
    final seen = <String>{};
    return [
      for (final release in candidates)
        if (!owns(release) && seen.add(_key(release.artist, release.title)))
          release,
    ];
  }

  String _key(String artist, String title) {
    final titleKey = normalise(stripEditionQualifiers(title));
    return requireArtist ? '${normalise(artist)}|$titleKey' : titleKey;
  }
}

/// Removes bracketed qualifiers that describe an *edition* rather than a work.
///
/// The problem this solves is one-sided: MusicBrainz release-group titles are
/// clean, and library titles come from file tags, which are not. *Abbey Road
/// (2019 Mix)*, *Nevermind [Deluxe Edition]* and *Kid A (Remastered)* are all
/// the same record as their bare form, and matching them literally reports
/// albums you are listening to as albums you are missing.
///
/// **Only recognised qualifiers are dropped, never every bracket.** Stripping
/// all of them is one line shorter and wrong in both directions: it turns
/// *(What's the Story) Morning Glory?* into a different album from itself, and
/// it collapses *Greatest Hits (Volume 1)* and *(Volume 2)* into one record, so
/// owning the first hides the second. A bracket whose contents are not
/// recognised is left exactly where it is.
String stripEditionQualifiers(String title) {
  final buffer = StringBuffer();
  var depth = 0;
  var group = StringBuffer();
  var groupStart = 0;

  for (var i = 0; i < title.length; i++) {
    final char = title[i];
    if (char == '(' || char == '[') {
      if (depth == 0) {
        group = StringBuffer();
        groupStart = i;
      } else {
        group.write(char);
      }
      depth++;
      continue;
    }
    if ((char == ')' || char == ']') && depth > 0) {
      depth--;
      if (depth == 0) {
        // Kept verbatim, brackets and all, when it is not an edition note —
        // otherwise the two sides stop being comparable at all.
        if (!_isEditionNote(group.toString())) {
          buffer.write(title.substring(groupStart, i + 1));
        }
      } else {
        group.write(char);
      }
      continue;
    }
    if (depth > 0) {
      group.write(char);
    } else {
      buffer.write(char);
    }
  }

  // An unclosed bracket means the title is malformed; keep what was there
  // rather than silently truncating at the bracket.
  if (depth > 0) buffer.write(title.substring(groupStart));

  final stripped = buffer.toString().trim();
  // Never reduce a title to nothing. *(Remastered)* as a whole title is
  // nonsense, but returning '' would match every other empty-keyed album.
  return stripped.isEmpty ? title.trim() : stripped;
}

/// True when a bracketed group says nothing except which pressing this is.
///
/// Every word has to be recognised. *(Deluxe Edition)* goes; *(Live at Leeds)*
/// stays, because "at" and "leeds" are not edition words and a live album is a
/// different record from the studio one.
bool _isEditionNote(String group) {
  final words = normalise(group).split(' ').where((w) => w.isNotEmpty);
  if (words.isEmpty) return false;
  for (final word in words) {
    // A bare number or an ordinal — "2011 Remaster", "20th Anniversary" —
    // carries no information about *which record* this is.
    if (_isNumberLike(word)) continue;
    if (!_editionWords.contains(word)) return false;
  }
  return true;
}

/// `2011`, `20th`, `1st`. Ordinals matter because anniversary editions are one
/// of the most common qualifiers in a tagged library and are the reason a
/// digits-only check is not enough.
bool _isNumberLike(String word) =>
    int.tryParse(word) != null || RegExp(r'^\d+(st|nd|rd|th)$').hasMatch(word);

/// Words that describe a pressing rather than a record.
///
/// Deliberately conservative. Adding a word here silently merges albums, and
/// the failure it causes — an album you do not own never appearing in the list
/// of albums you do not own — is invisible, unlike the noise it removes.
const _editionWords = <String>{
  'remaster',
  'remastered',
  'remasters',
  'deluxe',
  'expanded',
  'edition',
  'anniversary',
  'reissue',
  'collectors',
  'collector',
  'legacy',
  'super',
  'ultimate',
  'box',
  'set',
  'import',
  'promo',
  'vinyl',
  'cd',
  'lp',
  'explicit',
  'clean',
  'bonus',
  'track',
  'tracks',
  'special',
  'version',
  'mono',
  'stereo',
  'digital',
  'japanese',
  'japan',
  'uk',
  'us',
  'international',
  'mix',
  'the',
  'and',
  'with',
  'st',
  'nd',
  'rd',
  'th',
};
