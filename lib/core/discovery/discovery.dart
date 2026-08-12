import 'dart:math';

import 'package:flutter/foundation.dart';

import '../db/shelf_item.dart';
import '../plex/plex_models.dart';

/// A Home row whose title is worked out at runtime rather than written down.
///
/// "Recently added" is a fixed shelf: the title says what it is and the query
/// never changes. These are the other kind, where the title *is* part of the
/// answer, and where an empty result means the row should not exist at all
/// rather than that it should render blank.
@immutable
class DiscoveryShelf {
  const DiscoveryShelf({required this.title, required this.items});

  final String title;

  /// Already in tile form, because a shelf may hold albums or artists and the
  /// row does not care which.
  final List<ShelfItem> items;

  /// Built only when there is something to show, so `null` and "an empty shelf"
  /// are the same thing everywhere and the Home screen never has to test both.
  static DiscoveryShelf? of(String title, List<ShelfItem> items) =>
      items.isEmpty ? null : DiscoveryShelf(title: title, items: items);

  /// The albums of a hub, as tiles. Zero for the timestamp: these rows have
  /// their own order and never sort on it.
  static List<ShelfItem> albums(List<PlexAlbum> albums) => [
    for (final album in albums) ShelfItem.album(album, 0),
  ];

  static List<ShelfItem> artists(List<PlexArtist> artists) => [
    for (final artist in artists) ShelfItem.artist(artist, 0),
  ];

  static List<ShelfItem> stations(List<PlexStation> stations) => [
    for (final station in stations) ShelfItem.station(station, 0),
  ];
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

/// What was listened to, from this device and from every other one.
///
/// **A union rather than a choice, and each side covers the other's gap.**
///
/// The local table is stamped the moment playback *starts*, so putting an album
/// on and wandering off after two minutes still counts. It is also the only
/// record of playlists, which the server never learns about. But it is
/// client-owned and unsynced, so it is empty on a new phone and was wiped
/// entirely by a keystore change that forced a reinstall.
///
/// The server's history covers every client going back years and survives any
/// reinstall. But it is stamped at the 90% scrobble mark, so it misses exactly
/// the case the local table was built for, and its rows name tracks with no
/// album on them and no playlist at all.
///
/// Taking either alone reintroduces a bug that has already been fixed once, so
/// this takes the later timestamp of the two per album, and keeps every local
/// playlist.
///
/// [serverPlays] is newest-first, as the history endpoint returns it, and maps
/// through [albumOfTrack] because Plex's rows carry no `parentRatingKey`.
List<ShelfItem> jumpBackIn({
  required List<ShelfItem> local,
  required List<PlexPlay> serverPlays,
  required Map<String, String> albumOfTrack,
  required Map<String, PlexAlbum> owned,
  int limit = 20,
}) {
  final startedAt = <String, int>{};
  final byKey = <String, ShelfItem>{};

  for (final item in local) {
    // Playlists are keyed apart from albums: the two share a ratingKey space
    // only by accident, and an album lending its timestamp to a playlist that
    // happens to carry the same number is a bug nobody would look for.
    final key = '${item.isPlaylist ? 'playlist' : 'album'}:${item.ratingKey}';
    startedAt[key] = item.startedAt;
    byKey[key] = item;
  }

  for (final play in serverPlays) {
    final album = play.albumRatingKey ?? albumOfTrack[play.trackRatingKey];
    if (album == null) continue;

    // Anything the cache does not hold has no title and no artwork, so it
    // cannot be a tile whatever the server remembers about it.
    final match = owned[album];
    if (match == null) continue;

    final key = 'album:$album';
    if (play.viewedAt <= (startedAt[key] ?? 0)) continue;
    startedAt[key] = play.viewedAt;
    byKey[key] = ShelfItem.album(match, play.viewedAt);
  }

  final ordered = byKey.keys.toList()
    ..sort((a, b) => startedAt[b]!.compareTo(startedAt[a]!));

  return [for (final key in ordered.take(limit)) byKey[key]!];
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
  return DiscoveryShelf.of(
    'Buried treasure',
    DiscoveryShelf.albums(pool.take(limit).toList()),
  );
}
