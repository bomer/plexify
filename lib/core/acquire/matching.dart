/// Deciding whether a name on somebody else's machine is the record you asked
/// for.
///
/// Shared by both download sources because they ask the same two questions of
/// different things: qBittorrent ranking asks them of a torrent filename, and
/// Soulseek ranking asks them of the folder a peer keeps the album in. The
/// answers must not diverge. Two copies of [unwantedWords] would drift, and the
/// day one of them learned about a new flavour of karaoke release and the other
/// did not would be very hard to spot from the outside.
///
/// **Why matching is done on tokens and not through the library's `normalise`.**
/// That normaliser drops punctuation entirely, which is right for typed queries:
/// "dont look back" should find "Don't Look Back". It is wrong here, where
/// punctuation *is* the word separator. `OK_Computer` would fold to
/// `okcomputer` and stop containing either word, so separators become spaces
/// instead.
library;

/// Formats worth telling apart, best first.
///
/// Only three, because only three change the decision. A lossless rip is worth
/// having over a lossy one; beyond that the difference between two lossy
/// encodings is not worth a tier, and pretending to know a bitrate from a
/// *filename* is how a 128k rip labelled "320" gets preferred.
///
/// A real bitrate reported by the source is a different matter and is ranked
/// where one exists, which on Soulseek it usually does. That happens in
/// `slskd/album_ranking.dart` rather than here, because it breaks ties within
/// [lossy] and never promotes anything across a tier.
enum AudioFormat {
  lossless(3, {'flac', 'alac', 'ape', 'wav', 'dsd', 'lossless'}),
  lossy(1, {'mp3', 'aac', 'm4a', 'ogg', 'opus', 'vbr', 'v0', '320', '256'}),
  unknown(0, {});

  const AudioFormat(this.weight, this.tokens);

  final int weight;
  final Set<String> tokens;

  static AudioFormat detect(Set<String> tokens) {
    for (final format in [lossless, lossy]) {
      if (format.tokens.any(tokens.contains)) return format;
    }
    return unknown;
  }
}

/// Splits a name into lowercase words on anything that is not a letter or a
/// digit, which is what separates them in practice: dots, underscores, hyphens,
/// brackets and spaces all turn up as separators inside a single filename.
Set<String> nameTokens(String input) => input
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.isNotEmpty)
    .toSet();

/// [nameTokens] with the words that carry no matching signal removed, so their
/// absence from a name cannot fail a match.
///
/// `The Beatles` matching a folder called `Beatles - Revolver` is the case this
/// exists for, and it is extremely common.
Set<String> significantTokens(String input) =>
    nameTokens(input).difference(stopWords);

const stopWords = {'the', 'a', 'an', 'and', 'of', 'in', 'on', 'at'};

/// Things that mean "this is not the record you asked for".
///
/// Applied only when the album's own title does not contain the word, so a
/// genuine live album or remix collection is unaffected.
const unwantedWords = {
  'karaoke',
  'tribute',
  'covers',
  'instrumental',
  'instrumentals',
  'sample',
  'samples',
  'ringtone',
  'ringtones',
};

/// Whether [name] names this record well enough to act on without being asked.
///
/// Every significant album word has to be present. The artist needs only one,
/// because names abbreviate performers far more often than titles, `RHCP` for
/// Red Hot Chili Peppers, while the album is the thing actually being named.
bool namesRelease(
  Set<String> tokens, {
  required Set<String> wantedArtist,
  required Set<String> wantedAlbum,
}) {
  final albumMatches =
      wantedAlbum.isNotEmpty && wantedAlbum.every(tokens.contains);
  final artistMatches =
      wantedArtist.isEmpty || wantedArtist.any(tokens.contains);
  return albumMatches && artistMatches;
}

/// Unwanted words present in [tokens] that the record's own title does not
/// explain, so searching for a live album is not sabotaged by "live" being in
/// its name.
Set<String> unwantedIn(Set<String> tokens, {required String album}) {
  final albumTokens = significantTokens(album);
  return {
    for (final word in unwantedWords)
      if (tokens.contains(word) && !albumTokens.contains(word)) word,
  };
}

/// Rough base-2 logarithm, for scores that should grow with diminishing
/// returns.
///
/// The gap between 2 and 20 seeders decides whether a download finishes; the
/// gap between 200 and 2000 decides nothing. The same shape applies to a peer's
/// upload speed.
double log2(int value) {
  var result = 0.0;
  var remaining = value.toDouble();
  while (remaining > 1) {
    remaining /= 2;
    result += 1;
  }
  return result;
}
