import '../../core/db/normalise.dart';
import '../../core/plex/plex_models.dart';

/// Sorting and bucketing for the A–Z artist list.
///
/// Kept apart from the widget because the rules are the interesting part and
/// they are worth testing directly.

/// Leading words that should not decide where an artist files.
///
/// Plex does the same through `titleSort`, so honouring them keeps this list in
/// agreement with the server rather than inventing a second alphabet. Without
/// it, a music library piles most of its bands under T.
const _articles = ['the ', 'a ', 'an '];

/// The key an artist actually sorts under.
///
/// Takes the already-normalised title — lowercased, accent-folded, punctuation
/// dropped — and removes a leading article.
String artistSortKey(String normalisedTitle) {
  for (final article in _articles) {
    if (normalisedTitle.startsWith(article)) {
      final rest = normalisedTitle.substring(article.length);
      // "The The" must not become nothing at all.
      if (rest.isNotEmpty) return rest;
    }
  }
  return normalisedTitle;
}

/// The index letter an artist files under.
///
/// Everything that does not begin with a letter — numbers, symbols, scripts
/// with no Latin form — shares a single `#` bucket. Splitting those further
/// would produce a rail too long to hit accurately with a thumb.
String artistBucket(String normalisedTitle) {
  final key = artistSortKey(normalisedTitle);
  if (key.isEmpty) return '#';
  final first = key.codeUnitAt(0);
  if (first >= 0x61 && first <= 0x7A) {
    return String.fromCharCode(first).toUpperCase();
  }
  return '#';
}

/// An artist list ordered for browsing, with its letter buckets worked out.
class ArtistIndex {
  ArtistIndex._(this.artists, this.buckets, this.bucketStart, this._starts);

  /// Artists in display order.
  final List<PlexArtist> artists;

  /// Letters present, in rail order — `#` last, where it is out of the way of
  /// the letters people actually reach for.
  final List<String> buckets;

  /// First index in [artists] for each bucket.
  final Map<String, int> bucketStart;

  /// The same starts as a set, so the list builder can ask "is this a section
  /// boundary?" without scanning the map for every row it draws.
  final Set<int> _starts;

  factory ArtistIndex.from(List<PlexArtist> input) {
    final keys = {
      for (final artist in input) artist.ratingKey: normalise(artist.title),
    };
    String keyOf(PlexArtist a) => keys[a.ratingKey] ?? normalise(a.title);

    final sorted = [...input]
      ..sort((a, b) {
        // Numbers sort before letters in ASCII, which would put the # bucket at
        // the top of the list while the rail shows it at the bottom — so
        // tapping # would scroll somewhere it does not point. The list and the
        // rail have to agree on where # lives.
        final aHash = artistBucket(keyOf(a)) == '#' ? 1 : 0;
        final bHash = artistBucket(keyOf(b)) == '#' ? 1 : 0;
        if (aHash != bHash) return aHash - bHash;

        final byKey = artistSortKey(
          keyOf(a),
        ).compareTo(artistSortKey(keyOf(b)));
        // Fall back to the raw title so the order is stable when two artists
        // share a sort key, rather than depending on the input order.
        return byKey != 0 ? byKey : a.title.compareTo(b.title);
      });

    final starts = <String, int>{};
    for (var i = 0; i < sorted.length; i++) {
      starts.putIfAbsent(artistBucket(keyOf(sorted[i])), () => i);
    }

    final letters = starts.keys.where((b) => b != '#').toList()..sort();
    if (starts.containsKey('#')) letters.add('#');

    return ArtistIndex._(sorted, letters, starts, starts.values.toSet());
  }

  bool get isEmpty => artists.isEmpty;

  /// Whether a letter header belongs above [index].
  bool startsBucket(int index) => _starts.contains(index);

  String bucketAt(int index) => artistBucket(normalise(artists[index].title));
}
