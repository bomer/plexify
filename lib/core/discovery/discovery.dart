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

/// Month names, because `intl` is not a dependency and this is the only place
/// that wants one.
const _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Albums played most often inside a calendar month, as the *server* counted.
///
/// [plays] is the server's history, newest first. [owned] maps album ratingKey
/// to the cached album, and is what supplies the title and the artwork: the
/// history rows carry counts but no art, and joining locally means this costs
/// no extra requests and silently drops anything no longer in the library.
///
/// **Falls back to the previous month.** On the third of the month the current
/// one holds a handful of plays, and a shelf that appears with two albums in it
/// and grows over four weeks reads as broken. If this month cannot fill
/// [minimumAlbums], last month is offered instead, and the title says which,
/// which is the whole reason the title is computed rather than fixed.
/// [albumOfTrack] maps a track's ratingKey to its album's, for the servers
/// that leave `parentRatingKey` off their history rows. Consulted only when the
/// row does not carry one itself, so a server that does say keeps being
/// believed.
DiscoveryShelf? mostPlayedShelf({
  required List<PlexPlay> plays,
  required Map<String, PlexAlbum> owned,
  required DateTime now,
  Map<String, String> albumOfTrack = const {},
  int minimumAlbums = 4,
  int limit = 20,
}) {
  // Month zero is last December as far as DateTime is concerned, so January
  // needs no special case.
  for (final month in [
    DateTime(now.year, now.month),
    DateTime(now.year, now.month - 1),
  ]) {
    final shelf = _mostPlayedIn(
      plays: plays,
      owned: owned,
      albumOfTrack: albumOfTrack,
      month: month,
      limit: limit,
    );
    if (shelf != null && shelf.albums.length >= minimumAlbums) return shelf;
  }
  return null;
}

DiscoveryShelf? _mostPlayedIn({
  required List<PlexPlay> plays,
  required Map<String, PlexAlbum> owned,
  required Map<String, String> albumOfTrack,
  required DateTime month,
  required int limit,
}) {
  final from = DateTime(month.year, month.month).millisecondsSinceEpoch ~/ 1000;
  final to =
      DateTime(month.year, month.month + 1).millisecondsSinceEpoch ~/ 1000;

  final counts = <String, int>{};
  final firstSeen = <String, int>{};
  for (final (index, play) in plays.indexed) {
    if (play.viewedAt < from || play.viewedAt >= to) continue;
    final key = play.albumRatingKey ?? albumOfTrack[play.trackRatingKey];
    if (key == null || !owned.containsKey(key)) continue;
    counts[key] = (counts[key] ?? 0) + 1;
    firstSeen.putIfAbsent(key, () => index);
  }

  // Ties broken by position in the history, which arrives newest first, so two
  // albums on four plays each put the one played more recently on the left.
  // **The second clause is not decoration.** `List.sort` is not stable in Dart,
  // so comparing on the count alone leaves equal counts in whatever order the
  // sort happened to leave them, and the row would reshuffle itself between
  // refreshes for no reason a user could see.
  final ranked = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : firstSeen[a]!.compareTo(firstSeen[b]!);
    });

  return DiscoveryShelf.of('Most played in ${_months[month.month - 1]}', [
    for (final key in ranked.take(limit)) owned[key]!,
  ]);
}

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

/// The artist's other albums, given the album most recently played.
///
/// Excludes the one that was played: it is already sitting at the front of
/// "Jump back in", and a row called "More by The Beths" whose first tile is the
/// album you just heard is not more of anything.
DiscoveryShelf? moreByArtistShelf({
  required PlexAlbum? seed,
  required List<PlexAlbum> discography,
}) {
  if (seed == null) return null;
  return DiscoveryShelf.of('More by ${seed.artist}', [
    for (final album in discography)
      if (album.ratingKey != seed.ratingKey) album,
  ]);
}

/// Genres in a stable per-day order, best guess first.
///
/// The caller walks this until it finds one with enough albums to fill a row.
/// Plex's genre list carries no counts, so "enough" cannot be known without
/// asking, and a library will have a dozen genres tagged onto one album each.
List<PlexGenre> genresInTasteOrder(
  List<PlexGenre> genres, {
  required int seed,
}) => [...genres]..shuffle(Random(seed));

/// Where to start reading inside a genre, so the row is not always the same
/// alphabetical head of it.
///
/// Clamped so the window always lands inside the result set: asking Plex for a
/// container past the end returns an empty page, and an empty page here would
/// hide a shelf that has hundreds of albums behind it.
int genreOffset({
  required int totalSize,
  required int windowSize,
  required int seed,
}) {
  final room = totalSize - windowSize;
  if (room <= 0) return 0;
  return Random(seed).nextInt(room + 1);
}
