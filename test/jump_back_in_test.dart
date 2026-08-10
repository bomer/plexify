import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/shelf_item.dart';
import 'package:plexify/core/discovery/discovery.dart';
import 'package:plexify/core/plex/plex_models.dart';

/// "Jump back in", merged from this device and from every other one.
///
/// Both halves are load-bearing and each covers a gap the other has. Taking
/// either alone reintroduces a bug that has already been fixed once, which is
/// what most of these assert.
void main() {
  PlexAlbum album(String key) =>
      PlexAlbum(ratingKey: key, title: 'Album $key', artist: 'Someone');

  PlexPlaylist playlist(String key) =>
      PlexPlaylist(ratingKey: key, title: 'Playlist $key');

  PlexPlay play(String track, int at) => PlexPlay(
    trackRatingKey: track,
    albumRatingKey: null,
    artistRatingKey: null,
    viewedAt: at,
  );

  List<ShelfItem> merge({
    List<ShelfItem> local = const [],
    List<PlexPlay> server = const [],
    Map<String, String> albumOfTrack = const {},
    List<String> ownedKeys = const ['a', 'b', 'c'],
    int limit = 20,
  }) => jumpBackIn(
    local: local,
    serverPlays: server,
    albumOfTrack: albumOfTrack,
    owned: {for (final key in ownedKeys) key: album(key)},
    limit: limit,
  );

  test('a fresh install still has a shelf', () {
    // The whole point. A new phone, or a reinstall forced by a keystore
    // change, has an empty local table and this row was simply blank.
    final items = merge(
      server: [play('t1', 500), play('t2', 400)],
      albumOfTrack: const {'t1': 'a', 't2': 'b'},
    );

    expect(items.map((i) => i.ratingKey), ['a', 'b']);
  });

  test('local wins when it is more recent, because it is stamped earlier', () {
    // The server stamps at the 90% scrobble mark. Putting an album on and
    // wandering off after two minutes records nothing there and is exactly
    // what the local table was added for.
    final items = merge(
      local: [ShelfItem.album(album('a'), 900)],
      server: [play('t1', 100)],
      albumOfTrack: const {'t1': 'a'},
    );

    expect(items.single.startedAt, 900);
  });

  test('the server wins when it is more recent, which is another device', () {
    final items = merge(
      local: [ShelfItem.album(album('a'), 100)],
      server: [play('t1', 900)],
      albumOfTrack: const {'t1': 'a'},
    );

    expect(items.single.startedAt, 900);
  });

  test('an album is one tile however many of its tracks were played', () {
    final items = merge(
      server: [play('t1', 500), play('t2', 400), play('t3', 300)],
      albumOfTrack: const {'t1': 'a', 't2': 'a', 't3': 'a'},
    );

    expect(items, hasLength(1));
    expect(items.single.startedAt, 500, reason: 'the most recent play wins');
  });

  test('playlists survive, since the server never hears about them', () {
    // Playback is reported against the track, so Plex never learns a playlist
    // was involved. The local table is the only record there is.
    final items = merge(
      local: [ShelfItem.playlist(playlist('p1'), 800)],
      server: [play('t1', 500)],
      albumOfTrack: const {'t1': 'a'},
    );

    expect(items.map((i) => i.title), ['Playlist p1', 'Album a']);
  });

  test('an album never takes a playlist timestamp, or the reverse', () {
    // The two share a ratingKey space only by accident. Keying them together
    // would be a bug nobody would think to look for.
    final items = merge(
      local: [
        ShelfItem.playlist(playlist('a'), 100),
        ShelfItem.album(album('a'), 200),
      ],
    );

    expect(items, hasLength(2));
    expect(items.first.isPlaylist, isFalse);
  });

  test('an album the library no longer holds is not a tile', () {
    // The history goes back years and outlives what is on disk. Without a
    // title or artwork there is nothing to draw.
    final items = merge(
      server: [play('t1', 900), play('t2', 500)],
      albumOfTrack: const {'t1': 'gone', 't2': 'a'},
      ownedKeys: const ['a'],
    );

    expect(items.map((i) => i.ratingKey), ['a']);
  });

  test('a play whose track the cache has never seen is skipped', () {
    expect(merge(server: [play('unknown', 900)]), isEmpty);
  });

  test('newest first, and no longer than asked for', () {
    final items = merge(
      server: [play('t1', 100), play('t2', 900), play('t3', 500)],
      albumOfTrack: const {'t1': 'a', 't2': 'b', 't3': 'c'},
      limit: 2,
    );

    expect(items.map((i) => i.ratingKey), ['b', 'c']);
  });

  test('nothing anywhere is an empty shelf rather than a crash', () {
    expect(merge(), isEmpty);
  });
}
