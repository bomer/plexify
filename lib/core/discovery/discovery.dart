import 'dart:math';

import 'package:flutter/foundation.dart';

import '../plex/plex_models.dart';

/// A Home row whose title is worked out at runtime rather than written down.
///
/// "Recently added" is a fixed shelf: the title says what it is and the query
/// never changes. These are the other kind, where the title *is* part of the
/// answer, and where an empty result means the row should not exist at all
/// rather than that it should render blank.
@immutable
class DiscoveryShelf {
  const DiscoveryShelf({required this.title, required this.albums});

  final String title;
  final List<PlexAlbum> albums;

  /// Built only when there is something to show, so `null` and "an empty shelf"
  /// are the same thing everywhere and the Home screen never has to test both.
  static DiscoveryShelf? of(String title, List<PlexAlbum> albums) =>
      albums.isEmpty ? null : DiscoveryShelf(title: title, albums: albums);
}

/// The seed that makes a rotating shelf rotate once a day.
///
/// Days since the epoch, not `Random()`. A fresh random each build would
/// reshuffle the row on every rebuild, which on a screen backed by four live
/// database streams is several times a second, and the shelf would be
/// unusable: you would never get back to the album you just saw. Seeding on
/// the date gives a row that is stable all day and different tomorrow.
int daySeed(DateTime now) => now.toUtc().difference(_epoch).inDays;

final DateTime _epoch = DateTime.utc(1970);

/// Albums that have never been played, in a different order each day.
///
/// The point of the row is a library big enough that most of it is invisible:
/// browsing surfaces what you already know is there, and everything else may as
/// well not exist. Shuffled rather than sorted because any stable ordering
/// (oldest, alphabetical) shows the same twenty albums for ever, which is the
/// problem rather than a way of solving it.
DiscoveryShelf? buriedTreasureShelf(
  List<PlexAlbum> neverPlayed, {
  required int seed,
  int limit = 20,
}) {
  final pool = [...neverPlayed]..shuffle(Random(seed));
  return DiscoveryShelf.of('Buried treasure', pool.take(limit).toList());
}
