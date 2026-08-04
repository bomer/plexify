/// Normalises text for matching and search.
///
/// Stored alongside the display value in its own column so search can compare
/// against it directly — normalising at query time would prevent any index from
/// being used, which is the whole point of keeping a local copy.
///
/// Deliberately aggressive: people type "aint no" looking for "Ain't No…", and
/// "dont look back" for "Don't Look Back". Folding punctuation away entirely
/// makes those match.
///
/// This same function is what [Phase 5] uses to match MusicBrainz releases
/// against the library when Plex has no MBID, so changing it changes
/// de-duplication behaviour too.
String normalise(String input) {
  final lowered = input.toLowerCase();

  final buffer = StringBuffer();
  var lastWasSpace = true; // leading whitespace is dropped

  for (final rune in lowered.runes) {
    final char = String.fromCharCode(rune);
    if (_isAlphanumeric(rune)) {
      buffer.write(_foldAccent(char));
      lastWasSpace = false;
    } else if (rune == 0x20 || rune == 0x09 || rune == 0x0A) {
      // Collapse runs of whitespace rather than emitting several spaces.
      if (!lastWasSpace) {
        buffer.write(' ');
        lastWasSpace = true;
      }
    }
    // Everything else — apostrophes, hyphens, brackets, punctuation — is
    // dropped entirely rather than becoming a space, so "don't" normalises to
    // "dont" and not "don t".
  }

  return buffer.toString().trimRight();
}

bool _isAlphanumeric(int rune) {
  return (rune >= 0x30 && rune <= 0x39) || // 0-9
      (rune >= 0x61 && rune <= 0x7A) || // a-z (already lowercased)
      rune > 0x7F; // keep non-ASCII for the accent folding below
}

/// Folds common accented Latin characters to their base letter, so "Björk"
/// matches a search for "bjork" and "Sigur Rós" for "sigur ros".
String _foldAccent(String char) => _accents[char] ?? char;

const _accents = <String, String>{
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', 'ō': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
  'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y',
  'æ': 'ae', 'œ': 'oe', 'ß': 'ss', 'đ': 'd', 'þ': 'th',
};
