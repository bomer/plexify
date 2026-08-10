import 'package:flutter/foundation.dart' show visibleForTesting;

import '../plex/plex_client.dart';
import '../plex/plex_models.dart';

/// Picks what to play next from Plex's sonic model.
///
/// Two jobs that look like one. **Starting a station** turns a song into a
/// queue, and **continuing one** refills that queue before it runs out. Both
/// come from the same endpoint and differ only in whether the seed itself is
/// wanted, which is why they are one class.
///
/// **Deliberately holds nothing.** The obvious design gives a station a memory
/// of what it has played, so it does not circle: sonic similarity is close to
/// symmetric, the nearest track to A is usually B and the nearest to B is
/// usually A, and without a memory that is the entire station. But the queue
/// already remembers every track it was given and survives everything this
/// object would not — a reconnect, a new server address, a provider rebuild.
/// Passing the queue in as the exclusion set is the same memory without a
/// second copy of it that can disagree.
///
/// The client is passed per call for the same reason. Holding one would tie a
/// running station to the connection it started on, and stations run for hours.
class SonicRadio {
  const SonicRadio({this.batch = 20});

  /// How many tracks one refill adds.
  ///
  /// Enough to be an hour or so of listening, so refills are rare and a failed
  /// one is not immediately audible; small enough that what gets queued was
  /// chosen against something played recently rather than an hour ago.
  final int batch;

  /// A station built from [seed], with the seed itself first.
  ///
  /// First because "start radio from this song" that opens with a different
  /// song has misread the request.
  Future<List<PlexTrack>> start(PlexClient client, PlexTrack seed) async {
    final rest = await _fetch(client, seed.ratingKey, {seed.ratingKey});
    return [seed, ...rest];
  }

  /// More music like [seedRatingKey], excluding everything in [exclude].
  ///
  /// [seedRatingKey] should be the *last* track in the queue rather than the
  /// one that started it. Reseeding on where the queue has reached is what
  /// makes a station drift: an hour in it plays music like the music it found,
  /// not like where it began.
  ///
  /// Empty is a real answer and means the station has run out — a small library,
  /// or a seed whose neighbourhood has already been played. Callers should let
  /// playback end rather than trying again with something else.
  Future<List<PlexTrack>> extend(
    PlexClient client, {
    required String seedRatingKey,
    required Set<String> exclude,
  }) => _fetch(client, seedRatingKey, exclude);

  Future<List<PlexTrack>> _fetch(
    PlexClient client,
    String seedRatingKey,
    Set<String> exclude,
  ) async {
    // Asked for wider than needed because the filtering below is lossy, and a
    // seed's own neighbourhood is exactly where the overlap with what has
    // already been played is worst. A refill that returned four tracks would be
    // followed by another one almost immediately.
    final candidates = await client.nearest(seedRatingKey, limit: batch * 3);

    return chooseRadioTracks(
      candidates: candidates,
      exclude: exclude,
      want: batch,
    );
  }
}

/// Which of [candidates] a station should actually queue.
///
/// Separated from the fetch because it is the part with rules in it, and rules
/// are worth testing without a server. Plex's order is closest-first and is
/// preserved as given: the ranking is the whole value of the endpoint, and
/// nothing here knows better than the model does.
///
/// Three exclusions, each with a visible symptom if dropped. A track already in
/// [exclude] would make the station circle between two songs, or replay the
/// album that was playing a moment ago. A track with no playable part would sit
/// in the queue as a gap that stalls it, since the engine is handed the whole
/// list up front and does not skip. And [want] caps a refill, so one station
/// cannot queue two hundred tracks nobody will reach.
@visibleForTesting
List<PlexTrack> chooseRadioTracks({
  required List<PlexTrack> candidates,
  required Set<String> exclude,
  required int want,
}) {
  final picked = <PlexTrack>[];
  // Guards against one response listing the same track twice, which [exclude]
  // cannot catch because it is the caller's set and this does not add to it.
  final seen = <String>{};

  for (final track in candidates) {
    if (picked.length >= want) break;
    if (exclude.contains(track.ratingKey)) continue;
    if (!seen.add(track.ratingKey)) continue;
    if (!track.isPlayable) continue;
    picked.add(track);
  }
  return picked;
}
