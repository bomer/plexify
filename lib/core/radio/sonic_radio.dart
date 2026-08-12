import 'dart:math';

import '../plex/plex_models.dart';

/// Builds a station from an artist and the artists Plex thinks resemble them.
///
/// **Per artist, not per track, and that is the server's decision rather than a
/// preference.** This library holds no track-to-track similarity —
/// `/library/metadata/{key}/nearest` answers 200 with an empty container for a
/// track, its album and its artist alike — but
/// `/library/metadata/{artist}/similar` returns neighbours. Plexamp shows the
/// same shape from the other side: its sonic radio is greyed out on a song and
/// offered on an artist.
///
/// **The tracks come from the local cache, not from Plex.** A station draws a
/// couple of dozen tracks from half a dozen artists, which is six round trips
/// to assemble from the server against one query on a library that is already
/// fully synced. It also means a station starts instantly and works offline.
///
/// Holds nothing itself. The queue already remembers every track it was given,
/// so passing that in as the exclusion set is the same memory without a second
/// copy that can disagree.
class SonicRadio {
  const SonicRadio({this.batch = 24});

  /// How many tracks one station or one refill adds.
  ///
  /// Enough to be an hour or so of listening, so refills are rare and a failed
  /// one is not immediately audible.
  final int batch;

  /// Interleaves [byArtist] into a station.
  ///
  /// [byArtist] holds one list of tracks per artist, and **the first entry must
  /// be the seed artist**: a station built from "more like this" that opens
  /// with somebody else has answered a different question.
  ///
  /// Round-robin rather than concatenation, so it alternates between artists
  /// instead of playing each discography in turn. Concatenating would be a
  /// station in name only — forty minutes of the seed, then forty of whoever
  /// happened to come second.
  ///
  /// Shuffled *within* each artist, so two stations from one seed are not the
  /// same two dozen tracks in the same order. Deterministic when given a seeded
  /// [random], which is what makes it testable.
  List<PlexTrack> build({
    required List<List<PlexTrack>> byArtist,
    Set<String> exclude = const {},
    Random? random,
  }) {
    final rng = random ?? Random();
    final pools = [
      for (final tracks in byArtist)
        [
          for (final track in tracks)
            if (track.isPlayable && !exclude.contains(track.ratingKey)) track,
        ]..shuffle(rng),
    ];

    final picked = <PlexTrack>[];
    final seen = <String>{};
    var cursor = 0;

    // Ends when a full pass adds nothing, which is the only condition that
    // cannot spin: the cursor only ever advances and the pools never grow.
    while (picked.length < batch) {
      var addedSomething = false;
      for (final pool in pools) {
        if (picked.length >= batch) break;
        if (cursor >= pool.length) continue;
        if (seen.add(pool[cursor].ratingKey)) {
          picked.add(pool[cursor]);
          addedSomething = true;
        }
      }
      if (!addedSomething) break;
      cursor++;
    }
    return picked;
  }
}
