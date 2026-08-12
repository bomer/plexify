/// Orders torrent search hits, and decides whether any of them is good enough
/// to queue without asking.
///
/// This is the only part of qBittorrent acquisition with real judgement in it,
/// so it is a pure function over a list, no client and no futures and no state,
/// and it is tested directly. Everything else in the flow is plumbing whose
/// failure is obvious; this one fails by quietly downloading the wrong thing.
///
/// Deciding whether a name *is* the record lives in `acquire/matching.dart`,
/// shared with the Soulseek ranker, which asks the same questions of a folder
/// rather than of a torrent filename. What stays here is everything specific to
/// torrents: link kinds, seeders, and whole-discography bundles.
library;

import '../acquire/matching.dart';
import 'qbit_models.dart';

export '../acquire/matching.dart' show AudioFormat;

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

/// Ranks [results] for a specific record, best first.
List<RankedTorrent> rankTorrents(
  Iterable<QbitSearchResult> results, {
  required String artist,
  required String album,
  int? year,
}) {
  final wantedArtist = significantTokens(artist);
  final wantedAlbum = significantTokens(album);

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
  final tokens = nameTokens(result.fileName);
  final format = AudioFormat.detect(tokens);

  final named = namesRelease(
    tokens,
    wantedArtist: wantedArtist,
    wantedAlbum: wantedAlbum,
  );

  var score = 0.0;

  // Diminishing, not linear. The gap between 2 and 20 seeders decides whether
  // a download finishes; the gap between 200 and 2000 decides nothing, and
  // scoring it linearly would let a hugely popular loose match outweigh
  // everything else about a result.
  if (result.hasSeeders) {
    score += 10 * log2(result.seeders + 1);
  }

  score += format.weight * 12;

  if (year != null && tokens.contains('$year')) score += 8;

  // A record's own title outranks the penalty, so searching for a live album
  // is not sabotaged by the word "live" being in its name.
  final unwanted = unwantedIn(tokens, album: rawAlbum);
  score -= 40 * unwanted.length;

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
    matchesRelease: named && !isBundle && unwanted.isEmpty,
    format: format,
  );
}
