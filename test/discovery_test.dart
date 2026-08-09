import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/db/normalise.dart';
import 'package:plexify/core/discovery/discovery.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';

/// The rows on Home that are worked out rather than looked up.
///
/// Everything here is the part that can be wrong quietly: a shelf that ranks
/// the wrong album, that reshuffles under the reader's hand, or that vanishes
/// because a server said no in a way nothing checked. None of it shows an
/// error when it breaks, which is exactly why it needs tests.
void main() {
  PlexAlbum album(String key, {String artist = 'Radiohead'}) =>
      PlexAlbum(ratingKey: key, title: 'Album $key', artist: artist);

  PlexPlay play(String albumKey, DateTime at) => PlexPlay(
    trackRatingKey: 't',
    albumRatingKey: albumKey,
    artistRatingKey: 'a',
    viewedAt: at.millisecondsSinceEpoch ~/ 1000,
  );

  group('most played in a month', () {
    final now = DateTime(2026, 8, 9);

    test('ranks by how often each album was played inside the month', () {
      final shelf = mostPlayedShelf(
        plays: [
          for (var i = 0; i < 2; i++) play('quiet', DateTime(2026, 8, 2)),
          for (var i = 0; i < 9; i++) play('loud', DateTime(2026, 8, 3)),
          for (var i = 0; i < 5; i++) play('middling', DateTime(2026, 8, 4)),
          play('fourth', DateTime(2026, 8, 5)),
        ],
        owned: {
          for (final key in ['quiet', 'loud', 'middling', 'fourth'])
            key: album(key),
        },
        now: now,
      );

      expect(shelf!.title, 'Most played in August');
      expect(shelf.albums.map((a) => a.ratingKey), [
        'loud',
        'middling',
        'quiet',
        'fourth',
      ]);
    });

    test('ignores plays outside the month, in either direction', () {
      final shelf = mostPlayedShelf(
        plays: [
          // Enormously played in July, which must not colour August.
          for (var i = 0; i < 50; i++) play('july', DateTime(2026, 7, 20)),
          for (var i = 0; i < 2; i++) play('a', DateTime(2026, 8, 1)),
          play('b', DateTime(2026, 8, 2)),
          play('c', DateTime(2026, 8, 3)),
          play('d', DateTime(2026, 8, 4)),
        ],
        owned: {
          for (final key in ['july', 'a', 'b', 'c', 'd']) key: album(key),
        },
        now: now,
      );

      expect(shelf!.albums.map((a) => a.ratingKey), isNot(contains('july')));
      expect(shelf.albums.first.ratingKey, 'a');
    });

    test('falls back to last month, and says so', () {
      // Two days into the month there is nothing to show. A row that appears
      // with two albums in it and slowly grows over four weeks reads as broken,
      // so the title moves rather than the shelf staying thin.
      final shelf = mostPlayedShelf(
        plays: [
          play('new', DateTime(2026, 8, 1)),
          for (var i = 0; i < 3; i++) play('w', DateTime(2026, 7, 4)),
          for (var i = 0; i < 2; i++) play('x', DateTime(2026, 7, 5)),
          play('y', DateTime(2026, 7, 6)),
          play('z', DateTime(2026, 7, 7)),
        ],
        owned: {
          for (final key in ['new', 'w', 'x', 'y', 'z']) key: album(key),
        },
        now: now,
      );

      expect(shelf!.title, 'Most played in July');
      expect(shelf.albums.first.ratingKey, 'w');
    });

    test('January looks back to last December', () {
      final shelf = mostPlayedShelf(
        plays: [
          for (var i = 0; i < 4; i++) play('a', DateTime(2025, 12, 20)),
          for (var i = 0; i < 3; i++) play('b', DateTime(2025, 12, 21)),
          play('c', DateTime(2025, 12, 22)),
          play('d', DateTime(2025, 12, 23)),
        ],
        owned: {for (final key in ['a', 'b', 'c', 'd']) key: album(key)},
        now: DateTime(2026, 1, 2),
      );

      expect(shelf!.title, 'Most played in December');
      expect(shelf.albums, hasLength(4));
    });

    test('drops albums the library no longer holds', () {
      // The history goes back years and outlives what is on disk. An album
      // played fifty times and since deleted has no title and no artwork here,
      // so it cannot be a tile whatever its count says.
      final shelf = mostPlayedShelf(
        plays: [
          for (var i = 0; i < 50; i++) play('gone', DateTime(2026, 8, 2)),
          for (var i = 0; i < 4; i++) play('here', DateTime(2026, 8, 3)),
          play('also', DateTime(2026, 8, 4)),
          play('third', DateTime(2026, 8, 5)),
          play('fourth', DateTime(2026, 8, 6)),
        ],
        owned: {
          for (final key in ['here', 'also', 'third', 'fourth'])
            key: album(key),
        },
        now: now,
      );

      expect(shelf!.albums.map((a) => a.ratingKey), isNot(contains('gone')));
      expect(shelf.albums.first.ratingKey, 'here');
    });

    test('is absent rather than thin when neither month has enough', () {
      expect(
        mostPlayedShelf(
          plays: [play('a', DateTime(2026, 8, 2))],
          owned: {'a': album('a')},
          now: now,
        ),
        isNull,
      );
    });

    test('albums on equal counts stay in most-recent-first order', () {
      // **Forty of them on purpose.** `List.sort` switches from insertion sort
      // to an unstable quicksort somewhere above thirty-two elements, so a
      // handful of albums would pass this by accident however the comparator
      // was written, and the bug would only ever show up on a month with a lot
      // of listening in it.
      final keys = [for (var i = 0; i < 40; i++) 'k${i.toString().padLeft(2, '0')}'];
      final shelf = mostPlayedShelf(
        plays: [
          // Newest first, which is the order the history endpoint returns.
          for (final (index, key) in keys.indexed)
            play(key, DateTime(2026, 8, 20).subtract(Duration(hours: index))),
        ],
        owned: {for (final key in keys) key: album(key)},
        now: now,
        limit: 40,
      );

      // One play each, so nothing but the tie-break decides the order. Without
      // it the row arrives shuffled, and reshuffles again next month.
      expect(shelf!.albums.map((a) => a.ratingKey), keys);
    });
  });

  group('buried treasure', () {
    List<PlexAlbum> pool() => [for (var i = 0; i < 60; i++) album('$i')];

    test('holds still all day and moves tomorrow', () {
      final today = buriedTreasureShelf(pool(), seed: 20310)!.albums;
      final again = buriedTreasureShelf(pool(), seed: 20310)!.albums;
      final tomorrow = buriedTreasureShelf(pool(), seed: 20311)!.albums;

      // Twice in one day must match exactly. Home rebuilds several times a
      // second on a screen backed by live database streams, and a fresh
      // Random() would reshuffle the row under the reader's finger.
      expect(today.map((a) => a.ratingKey), again.map((a) => a.ratingKey));
      expect(
        today.map((a) => a.ratingKey),
        isNot(tomorrow.map((a) => a.ratingKey)),
      );
    });

    test('does not mutate the list it was given', () {
      final input = pool();
      final before = [for (final a in input) a.ratingKey];
      buriedTreasureShelf(input, seed: 1);
      expect([for (final a in input) a.ratingKey], before);
    });

    test('is absent when nothing qualifies', () {
      expect(buriedTreasureShelf(const [], seed: 1), isNull);
    });
  });

  test('the day seed advances once per day', () {
    expect(daySeed(DateTime.utc(2026, 8, 9, 1)), daySeed(DateTime.utc(2026, 8, 9, 23)));
    expect(
      daySeed(DateTime.utc(2026, 8, 10)),
      daySeed(DateTime.utc(2026, 8, 9)) + 1,
    );
  });

  group('more by artist', () {
    test('leaves out the album that seeded it', () {
      // It is already the first tile of "Jump back in" two rows up, and a row
      // called "More by X" that opens with the album you just heard is not
      // more of anything.
      final seed = album('1', artist: 'The Beths');
      final shelf = moreByArtistShelf(
        seed: seed,
        discography: [seed, album('2'), album('3')],
      );

      expect(shelf!.title, 'More by The Beths');
      expect(shelf.albums.map((a) => a.ratingKey), ['2', '3']);
    });

    test('is absent for an artist with one album', () {
      final seed = album('1');
      expect(moreByArtistShelf(seed: seed, discography: [seed]), isNull);
    });

    test('is absent when nothing has been played', () {
      expect(moreByArtistShelf(seed: null, discography: [album('1')]), isNull);
    });
  });

  group('genre window', () {
    test('never reads past the end of the results', () {
      // Plex answers a container past the end with an empty page, which would
      // hide a shelf that has hundreds of albums behind it.
      for (var seed = 0; seed < 200; seed++) {
        final offset = genreOffset(totalSize: 25, windowSize: 20, seed: seed);
        expect(offset, inInclusiveRange(0, 5));
      }
    });

    test('is zero when the genre barely fills one window', () {
      expect(genreOffset(totalSize: 12, windowSize: 20, seed: 7), 0);
    });

    test('the genre order is stable within a day and different the next', () {
      final genres = [
        for (var i = 0; i < 30; i++) PlexGenre(key: '$i', title: 'g$i'),
      ];
      String order(int seed) =>
          genresInTasteOrder(genres, seed: seed).map((g) => g.key).join(',');

      expect(order(20310), order(20310));
      expect(order(20310), isNot(order(20311)));
    });
  });

  group('never played, in the database', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> insert(
      String key, {
      int? lastViewedAt,
      int addedAt = 0,
    }) => db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            ratingKey: key,
            title: key,
            normalisedTitle: normalise(key),
            artistTitle: 'Artist',
            normalisedArtist: normalise('Artist'),
            addedAt: Value(addedAt),
            lastViewedAt: Value(lastViewedAt),
          ),
        );

    test('excludes anything Plex has ever recorded a view for', () async {
      await insert('untouched');
      await insert('played', lastViewedAt: 1700000000);

      final rows = await db.watchNeverPlayedAlbums().first;
      expect(rows.map((a) => a.ratingKey), ['untouched']);
    });

    test('excludes anything this app has played', () async {
      // The local history table is the other half, and it is needed: this app
      // deliberately never writes lastViewedAt, so checking Plex's column alone
      // would call an album buried the day after listening to it here.
      await insert('untouched');
      await insert('played here');
      await db
          .into(db.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              kind: 'album',
              ratingKey: 'played here',
              startedAt: 1700000000,
            ),
          );

      final rows = await db.watchNeverPlayedAlbums().first;
      expect(rows.map((a) => a.ratingKey), ['untouched']);
    });

    test('a playlist in the history does not exclude an album', () async {
      // Both kinds share the table and ratingKeys are only unique per type, so
      // an unfiltered subquery would blank out whichever album happened to
      // carry the same key as a playlist you put on.
      await insert('7');
      await db
          .into(db.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              kind: 'playlist',
              ratingKey: '7',
              startedAt: 1700000000,
            ),
          );

      final rows = await db.watchNeverPlayedAlbums().first;
      expect(rows.map((a) => a.ratingKey), ['7']);
    });

    test('excludes recent arrivals but keeps albums with no added date', () async {
      await insert('old', addedAt: 1000);
      await insert('new', addedAt: 9000);
      await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              ratingKey: 'undated',
              title: 'undated',
              normalisedTitle: 'undated',
              artistTitle: 'Artist',
              normalisedArtist: 'artist',
            ),
          );

      final rows = await db.watchNeverPlayedAlbums(addedBefore: 5000).first;
      // An album with no addedAt at all is old enough by any reading; dropping
      // it would quietly shrink the pool on libraries scanned by older agents.
      expect(rows.map((a) => a.ratingKey), containsAll(['old', 'undated']));
      expect(rows.map((a) => a.ratingKey), isNot(contains('new')));
    });

    test('albumsByKeys returns only what is held, and nothing for none', () async {
      await insert('here');
      expect(
        (await db.albumsByKeys(['here', 'gone'])).map((a) => a.ratingKey),
        ['here'],
      );
      expect(await db.albumsByKeys(const []), isEmpty);
    });
  });

  group('the endpoints behind the shelves', () {
    final server = PlexServer(
      name: 'Tower',
      baseUrl: 'https://tower.example:32400',
      token: 'servertoken',
      isLocal: true,
      isRelay: false,
    );

    PlexClient clientReturning(
      String body, {
      int status = 200,
      void Function(http.Request request)? onRequest,
    }) => PlexClient(
      server: server,
      identity: PlexIdentity.forTesting(),
      httpClient: MockClient((request) async {
        onRequest?.call(request);
        return http.Response(
          body,
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    test('play history asks for tracks only, newest first', () async {
      // History carries album and artist rollups on some server versions, and
      // counting those alongside the tracks would double every total.
      late Uri asked;
      late Map<String, String> headers;
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Metadata': [
              {
                'ratingKey': '101',
                'parentRatingKey': '50',
                'grandparentRatingKey': '9',
                'viewedAt': 1786000000,
              },
            ],
          },
        }),
        onRequest: (request) {
          asked = request.url;
          headers = request.headers;
        },
      );

      final plays = await client.playHistory('3', limit: 500);

      expect(asked.path, '/status/sessions/history/all');
      expect(asked.queryParameters['librarySectionID'], '3');
      expect(asked.queryParameters['sort'], 'viewedAt:desc');
      expect(asked.queryParameters['type'], '10');
      // The window is a bounded page rather than a date filter, because Plex
      // drops filter parameters it does not recognise and an ignored one here
      // would return everything and make every month look the same.
      expect(asked.queryParameters, isNot(contains('viewedAt>')));
      expect(headers['X-Plex-Container-Size'], '500');

      expect(plays.single.albumRatingKey, '50');
      expect(plays.single.artistRatingKey, '9');
    });

    test('play history is empty rather than an error when refused', () async {
      // Not the owner. Plex answers this with an empty container rather than a
      // 403 on some versions, so both paths have to end in the same place: a
      // Home row that is simply not there.
      final client = clientReturning('{}', status: 403);
      expect(await client.playHistory('3'), isEmpty);
    });

    test('rows with no viewedAt are dropped', () async {
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Metadata': [
              {'ratingKey': '1', 'parentRatingKey': '50'},
              {'ratingKey': '2', 'parentRatingKey': '50', 'viewedAt': 1786000000},
            ],
          },
        }),
      );
      expect(await client.playHistory('3'), hasLength(1));
    });

    test('genre keys are reduced to an id whichever shape they arrive in', () async {
      // Two spellings in the wild depending on server version, and `?genre=`
      // wants the bare id in both cases.
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Directory': [
              {'key': '/library/sections/3/genre/13', 'title': 'Rock'},
              {'key': '27', 'title': 'Jazz'},
              {'fastKey': '/library/sections/3/all?genre=41', 'title': 'Folk'},
            ],
          },
        }),
      );

      final genres = await client.genres('3');
      expect(genres.map((g) => g.key), ['13', '27', '41']);
      expect(genres.map((g) => g.title), ['Rock', 'Jazz', 'Folk']);
    });

    test('genres are empty rather than an error when the server will not say', () async {
      final client = clientReturning('nope', status: 500);
      expect(await client.genres('3'), isEmpty);
    });

    test('a genre page reports the total so a window can be picked', () async {
      late Map<String, String> headers;
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'totalSize': 412,
            'Metadata': [
              {'ratingKey': '1', 'title': 'Kid A', 'parentTitle': 'Radiohead'},
            ],
          },
        }),
        onRequest: (request) => headers = request.headers,
      );

      final page = await client.genreAlbums('3', '13', start: 40, size: 20);
      expect(page.totalSize, 412);
      expect(page.items.single.title, 'Kid A');
      expect(headers['X-Plex-Container-Start'], '40');
      expect(headers['X-Plex-Container-Size'], '20');
    });

    test('hubs are empty rather than an error on a server that has none', () async {
      final client = clientReturning('{}', status: 404);
      expect(await client.sectionHubs('3'), isEmpty);
    });

    test('hubs report their identifier, type and size', () async {
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Hub': [
              {
                'hubIdentifier': 'home.music.recent',
                'title': 'Recently Played',
                'type': 'album',
                'size': 12,
                'context': 'hub.music.recent',
              },
            ],
          },
        }),
      );

      final hub = (await client.sectionHubs('3')).single;
      expect(hub.hubIdentifier, 'home.music.recent');
      expect(hub.title, 'Recently Played');
      expect(hub.size, 12);
      expect(hub.context, 'hub.music.recent');
    });
  });
}
