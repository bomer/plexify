/// Orders search hits, and decides whether any of them is good enough to queue
/// without asking.
///
/// This is the only part of acquisition with real judgement in it, so it is a
/// pure function over a list — no client, no futures, no state — and it is
/// tested directly. Everything else in the flow is plumbing whose failure is
/// obvious; this one fails by quietly downloading the wrong thing.
///
/// **Why matching is done on tokens and not through `normalise`.** The library's
/// normaliser drops punctuation entirely, which is right for typed queries:
/// "dont look back" should find "Don't Look Back". It is wrong for filenames,
/// where punctuation *is* the word separator — `OK_Computer` would fold to
/// `okcomputer` and stop containing either word. Here separators become spaces
/// instead.
library;

import 'qbit_models.dart';

/// A search hit with a score and a verdict.
class RankedTorrent {
  const RankedTorrent({
    required this.result,
    required this.score,
    required this.matchesRelease,
    required this.format,
  });

  final QbitSearchResult result;

  /// How much this link is worth being offered, before anything about the
  /// record itself is considered.
  ///
  /// A tier rather than a score bonus, because the difference is categorical:
  /// a magnet needs no fetch and cannot fail on the way in, a `.torrent` URL
  /// can be refused by its host, and a web page **always** fails — qBittorrent
  /// answers `Ok.`, tries to decode a page of HTML and gives up in its own log
  /// where this app can never see it.
  ///
  /// A magnet with nobody seeding it is demoted to the middle: it will not fail
  /// to add and it will never finish either, so it has no business outranking a
  /// well-seeded torrent file.
  int get linkRank => switch (result.link) {
    TorrentLink.webPage => 0,
    TorrentLink.unknown => 1,
    TorrentLink.torrentFile => 2,
    TorrentLink.magnet => result.hasSeeders && result.seeders < 1 ? 2 : 3,
  };

  /// Whether handing this to qBittorrent stands a chance of working.
  bool get addable => result.link.addable;

  /// Higher is better. Only meaningful within one ranking.
  final double score;

  /// Whether the filename actually names this record.
  ///
  /// The gate for queueing something without the user looking at it. Torrent
  /// search plugins return loose matches by design — searching for one album
  /// returns the artist's other records, tribute albums and unrelated releases
  /// that share a word — so seeder count alone is not evidence of anything.
  final bool matchesRelease;

  final AudioFormat format;
}

/// Formats worth telling apart, best first.
///
/// Only three, because only three change the decision. A lossless rip is worth
/// having over a lossy one; beyond that the difference between two lossy
/// encodings is not worth ranking, and pretending to know a bitrate from a
/// filename is how a 128k rip labelled "320" gets preferred.
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

/// Ranks [results] for a specific record, best first.
List<RankedTorrent> rankTorrents(
  Iterable<QbitSearchResult> results, {
  required String artist,
  required String album,
  int? year,
}) {
  final wantedArtist = _significantTokens(artist);
  final wantedAlbum = _significantTokens(album);

  final ranked = <RankedTorrent>[
    for (final result in results)
      _rank(result, wantedArtist, wantedAlbum, year, album),
  ];

  ranked.sort((a, b) {
    // Three keys, in this order, and each one dominates the next completely.
    //
    // A confident match always outranks a loose one, however well seeded the
    // loose one is. Seeders measure popularity, not correctness, and the most
    // popular torrent matching one word of an album title is routinely a
    // different album entirely.
    if (a.matchesRelease != b.matchesRelease) return a.matchesRelease ? -1 : 1;

    // Then the kind of link, because a result that cannot be added is worth
    // nothing however good the record is. This is a tier and not a weighting
    // on purpose: no number of seeders should be able to lift a web page above
    // a magnet, since the web page will not download at all.
    if (a.linkRank != b.linkRank) return b.linkRank.compareTo(a.linkRank);

    return b.score.compareTo(a.score);
  });
  return ranked;
}

/// The one result worth queueing without asking, or null.
///
/// Deliberately strict, because the cost of the two mistakes is not
/// symmetrical. Refusing to auto-queue costs one extra tap on a list that is
/// already open. Auto-queueing the wrong thing puts a file on the server, into
/// the folder Plex watches, under the album's name — and the first anyone knows
/// of it is a tribute-band record appearing in the library.
RankedTorrent? bestAutomaticChoice(List<RankedTorrent> ranked) {
  if (ranked.isEmpty) return null;
  final best = ranked.first;
  if (!best.matchesRelease) return null;
  // Never queue something that will not download. A page URL is accepted by
  // qBittorrent, reported as `Ok.`, and then fails where only its own log can
  // see it — so a snackbar saying "Queued" would be a lie the app has no way of
  // discovering it had told.
  if (!best.addable) return null;

  // Zero seeders is a torrent that will never finish. Unknown (-1) is allowed:
  // several plugins simply do not report the figure, and treating "not stated"
  // as "nobody has it" rules out whole trackers.
  if (best.result.hasSeeders && best.result.seeders < 1) return null;
  return best;
}

RankedTorrent _rank(
  QbitSearchResult result,
  Set<String> wantedArtist,
  Set<String> wantedAlbum,
  int? year,
  String rawAlbum,
) {
  final tokens = torrentTokens(result.fileName);
  final format = AudioFormat.detect(tokens);

  // Every significant album word has to be present. The artist needs only one,
  // because filenames abbreviate performers far more often than titles — "RHCP"
  // for Red Hot Chili Peppers — while the album name is the thing being named.
  final albumMatches =
      wantedAlbum.isNotEmpty && wantedAlbum.every(tokens.contains);
  final artistMatches =
      wantedArtist.isEmpty || wantedArtist.any(tokens.contains);

  var score = 0.0;

  // Diminishing, not linear. The gap between 2 and 20 seeders decides whether
  // a download finishes; the gap between 200 and 2000 decides nothing, and
  // scoring it linearly would let a hugely popular loose match outweigh
  // everything else about a result.
  if (result.hasSeeders) {
    score += 10 * _log2(result.seeders + 1);
  }

  score += format.weight * 12;

  if (year != null && tokens.contains('$year')) score += 8;

  // A record's own title outranks the penalty, so searching for a live album
  // is not sabotaged by the word "live" being in its name.
  final albumTokens = _significantTokens(rawAlbum);
  var unwanted = false;
  for (final word in _unwantedWords) {
    if (tokens.contains(word) && !albumTokens.contains(word)) {
      score -= 40;
      unwanted = true;
    }
  }

  // Whole-discography torrents match everything and are usually tens of
  // gigabytes. Not excluded — sometimes it is exactly what you want — but never
  // the automatic choice for one album.
  final isBundle =
      tokens.contains('discography') || tokens.contains('anthology');
  if (isBundle) score -= 25;

  return RankedTorrent(
    result: result,
    score: score,
    // An unwanted word disqualifies rather than merely penalising. "Karaoke -
    // OK Computer by Radiohead" contains every word of both the artist and the
    // album, so it matches on tokens alone — and a well-seeded one outscored a
    // sparsely-seeded real rip until this was a gate rather than a subtraction.
    // It is still in the list; it is just never the automatic choice.
    matchesRelease: albumMatches && artistMatches && !isBundle && !unwanted,
    format: format,
  );
}

/// Splits a filename into lowercase words on anything that is not a letter or
/// digit, which is what separates them in practice: dots, underscores, hyphens,
/// brackets and spaces all appear as separators in the same filename.
Set<String> torrentTokens(String input) => input
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.isNotEmpty)
    .toSet();

/// Words that carry no matching signal, dropped so their absence from a
/// filename cannot fail a match.
///
/// `The Beatles` matching a file named `Beatles - Revolver` is the case this
/// exists for, and it is extremely common.
Set<String> _significantTokens(String input) =>
    torrentTokens(input).difference(_stopWords);

const _stopWords = {'the', 'a', 'an', 'and', 'of', 'in', 'on', 'at'};

/// Things that mean "this is not the record you asked for".
///
/// Applied only when the album's own title does not contain the word, so a
/// genuine live album or remix collection is unaffected.
const _unwantedWords = {
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

double _log2(int value) {
  var result = 0.0;
  var remaining = value.toDouble();
  while (remaining > 1) {
    remaining /= 2;
    result += 1;
  }
  return result;
}
