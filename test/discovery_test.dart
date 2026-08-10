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
/// Everything here is the part that can be wrong quietly: a row that reshuffles
/// under the reader's hand, or that vanishes because a server said no in a way
/// nothing checked. None of it shows an error when it breaks, which is exactly
/// why it needs tests.
///
/// Much smaller than it was. Three of these rows are now the server's own hubs
/// rather than reimplementations of them, so the tests for ranking plays by
/// month, picking a genre and windowing into it went with the code.
void main() {
  PlexAlbum album(String key, {String artist = 'Radiohead'}) =>
      PlexAlbum(ratingKey: key, title: 'Album $key', artist: artist);

  group('buried treasure', () {
    List<PlexAlbum> pool() => [for (var i = 0; i < 60; i++) album('$i')];

    test('holds still all day and moves tomorrow', () {
      final today = buriedTreasureShelf(pool(), seed: 20310)!.items;
      final again = buriedTreasureShelf(pool(), seed: 20310)!.items;
      final tomorrow = buriedTreasureShelf(pool(), seed: 20311)!.items;

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
    expect(
      daySeed(DateTime.utc(2026, 8, 9, 1)),
      daySeed(DateTime.utc(2026, 8, 9, 23)),
    );
    expect(
      daySeed(DateTime.utc(2026, 8, 10)),
      daySeed(DateTime.utc(2026, 8, 9)) + 1,
    );
  });

  group('never played, in the database', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> insert(String key, {int? lastViewedAt, int addedAt = 0}) => db
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

    test(
      'excludes recent arrivals but keeps albums with no added date',
      () async {
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
      },
    );

    test(
      'albumsByKeys returns only what is held, and nothing for none',
      () async {
        await insert('here');
        expect(
          (await db.albumsByKeys(['here', 'gone'])).map((a) => a.ratingKey),
          ['here'],
        );
        expect(await db.albumsByKeys(const []), isEmpty);
      },
    );
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

    test('play history does not ask the server to filter by type', () async {
      // **The bug this test exists for.** `type=10` is how a section listing is
      // narrowed to tracks, and against the history endpoint it returns nothing
      // at all: 200, empty container, no error. Measured on 10 August 2026, on
      // a server with years of listening on it, where the shipping request
      // returned zero rows and the same request without `type` returned as many
      // as it was asked for. Rollups are dropped after parsing instead.
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
      expect(asked.queryParameters, isNot(contains('type')));
      // The window is a bounded page rather than a date filter, because Plex
      // drops filter parameters it does not recognise and an ignored one here
      // would return everything and make every month look the same.
      expect(asked.queryParameters, isNot(contains('viewedAt>')));
      expect(headers['X-Plex-Container-Size'], '500');

      expect(plays.single.albumRatingKey, '50');
      expect(plays.single.artistRatingKey, '9');
    });

    test('every narrowing can be removed independently', () async {
      // The probe's whole job: "no plays", "not allowed" and "asked wrongly"
      // arrive identical, and only asking with each narrowing dropped in turn
      // separates them.
      late Uri asked;
      PlexClient probing() => clientReturning(
        jsonEncode({'MediaContainer': {}}),
        onRequest: (request) => asked = request.url,
      );

      await probing().playHistoryRaw(sectionKey: '3');
      expect(asked.queryParameters['librarySectionID'], '3');
      expect(asked.queryParameters['type'], '10');

      await probing().playHistoryRaw(sectionKey: '3', tracksOnly: false);
      expect(asked.queryParameters['librarySectionID'], '3');
      expect(asked.queryParameters, isNot(contains('type')));

      await probing().playHistoryRaw(tracksOnly: false);
      expect(asked.queryParameters, isNot(contains('librarySectionID')));
      expect(asked.queryParameters, isNot(contains('type')));

      await probing().playHistoryRaw(accountId: '1');
      expect(asked.queryParameters['accountID'], '1');
    });

    test(
      'the raw form reports a refusal that the shipping one hides',
      () async {
        // playHistory swallows, because a Home row must never show an error.
        // That is exactly what makes it useless for finding out why a row is
        // missing, which is why the probe does not use it.
        final client = clientReturning('{}', status: 403);

        expect(await client.playHistory('3'), isEmpty);
        await expectLater(
          client.playHistoryRaw(sectionKey: '3'),
          throwsA(isA<PlexClientException>()),
        );
      },
    );

    test('play history is empty rather than an error when refused', () async {
      // Not the owner. Plex answers this with an empty container rather than a
      // 403 on some versions, so both paths have to end in the same place: a
      // Home row that is simply not there.
      final client = clientReturning('{}', status: 403);
      expect(await client.playHistory('3'), isEmpty);
    });

    test('rollup rows are dropped here rather than by the server', () async {
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Metadata': [
              {
                'ratingKey': '1',
                'type': 'track',
                'parentRatingKey': '50',
                'viewedAt': 1786000000,
              },
              {
                'ratingKey': '50',
                'type': 'album',
                'parentRatingKey': '9',
                'viewedAt': 1786000001,
              },
            ],
          },
        }),
      );

      // Counting the album row alongside its own tracks would double every
      // total on a server that sends both.
      final plays = await client.playHistory('3');
      expect(plays.map((p) => p.trackRatingKey), ['1']);
    });

    test('a row with no type at all is kept', () async {
      // Lenient on purpose, and this is the whole lesson from the type=10 bug:
      // a server that does not label its history is a reason to include
      // everything, not to discard everything.
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Metadata': [
              {
                'ratingKey': '1',
                'parentRatingKey': '50',
                'viewedAt': 1786000000,
              },
            ],
          },
        }),
      );

      expect(await client.playHistory('3'), hasLength(1));
    });

    test('rows with no viewedAt are dropped', () async {
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Metadata': [
              {'ratingKey': '1', 'parentRatingKey': '50'},
              {
                'ratingKey': '2',
                'parentRatingKey': '50',
                'viewedAt': 1786000000,
              },
            ],
          },
        }),
      );
      expect(await client.playHistory('3'), hasLength(1));
    });

    test(
      'hubs are empty rather than an error on a server that has none',
      () async {
        final client = clientReturning('{}', status: 404);
        expect(await client.sectionHubs('3'), isEmpty);
      },
    );

    test('an album hub arrives with its albums', () async {
      // **These are the rows Home renders now.** Parsing the items was the
      // whole gap: the hub was read for its name and its count while this app
      // rebuilt three of the same rows from scratch beside it, with two bugs
      // neither of which could exist here, because none of the work is ours.
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Hub': [
              {
                'hubIdentifier': 'music.popular.3',
                'title': 'Most Played in November',
                'type': 'album',
                'size': 6,
                'context': 'hub.music.popular',
                'Metadata': [
                  {
                    'ratingKey': '1',
                    'title': 'Pink Moon',
                    'parentTitle': 'Nick Drake',
                  },
                  {
                    'ratingKey': '2',
                    'title': 'In Rainbows',
                    'parentTitle': 'Radiohead',
                  },
                ],
              },
            ],
          },
        }),
      );

      final hub = (await client.sectionHubs('3')).single;
      expect(hub.hubIdentifier, 'music.popular.3');
      expect(hub.title, 'Most Played in November');
      expect(hub.albums.map((a) => a.title), ['Pink Moon', 'In Rainbows']);
      expect(hub.albums.first.artist, 'Nick Drake');
    });

    test('a hub of anything else arrives with no albums', () async {
      // Artists, stations and music videos each need a tile and a tap this app
      // does not have. Parsing them as albums would put a row of blanks on
      // Home instead of leaving the row out.
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Hub': [
              {
                'hubIdentifier': 'music.stations.3',
                'title': 'Stations',
                'type': 'station',
                'size': 4,
                'Metadata': [
                  {'ratingKey': '9', 'title': 'Something Radio'},
                ],
              },
            ],
          },
        }),
      );

      final hub = (await client.sectionHubs('3')).single;
      expect(hub.size, 4, reason: 'the probe still reports what it holds');
      expect(hub.albums, isEmpty);
    });

    test('a hub reports what it declares, not what it sent', () async {
      // The two disagree when a server pages a hub, and the probe is asking
      // what the hub holds rather than what fitted in one response.
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Hub': [
              {
                'hubIdentifier': 'music.top.period.3',
                'title': 'Top Albums from 2000s',
                'type': 'album',
                'size': 40,
                'Metadata': [
                  {'ratingKey': '1', 'title': 'One', 'parentTitle': 'Someone'},
                ],
              },
            ],
          },
        }),
      );

      final hub = (await client.sectionHubs('3')).single;
      expect(hub.size, 40);
      expect(hub.albums, hasLength(1));
    });

    test('the section id is stripped before an identifier is compared', () async {
      // **The bug this caught, on Home, in front of James.** Plex suffixes
      // every hub identifier with its section, so `music.recent.added` arrives
      // as `music.recent.added.3` and the skip list could never fire: Recently
      // added and Recently Added in Music sat side by side showing the same six
      // albums. The probe output had said `.3` on every row for a fortnight.
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Hub': [
              {
                'hubIdentifier': 'music.recent.added.3',
                'title': 'Recently Added in Music',
                'type': 'album',
                'size': 1,
                'Metadata': [
                  {'ratingKey': '1', 'title': 'One', 'parentTitle': 'Someone'},
                ],
              },
            ],
          },
        }),
      );

      final hub = (await client.sectionHubs('3')).single;
      expect(hub.hubIdentifier, 'music.recent.added.3');
      expect(hub.kind, 'music.recent.added');
    });

    test('an identifier with no section suffix is left alone', () async {
      // Not every server names them the same way, and stripping something that
      // is not there would be a second, quieter version of the same bug.
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Hub': [
              {
                'hubIdentifier': 'home.music.recent',
                'title': 'Recently Played',
                'type': 'album',
                'size': 0,
              },
            ],
          },
        }),
      );

      expect((await client.sectionHubs('3')).single.kind, 'home.music.recent');
    });

    test('an artist hub arrives with its artists', () async {
      // `music.recent.played` is the server's own recently-played row and it is
      // artists rather than albums. It is a cross-device jump-back-in Plex has
      // already computed, and it was being dropped for want of a tile.
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Hub': [
              {
                'hubIdentifier': 'music.recent.played.3',
                'title': 'Recently Played Music',
                'type': 'artist',
                'size': 2,
                'Metadata': [
                  {'ratingKey': '10', 'title': 'Nick Drake'},
                  {'ratingKey': '11', 'title': 'Radiohead'},
                ],
              },
            ],
          },
        }),
      );

      final hub = (await client.sectionHubs('3')).single;
      expect(hub.albums, isEmpty);
      expect(hub.artists.map((a) => a.title), ['Nick Drake', 'Radiohead']);
      expect(hub.hasItems, isTrue);
    });

    test('a hub with nothing in it is not a row', () async {
      // Real: "Artists on Tour" and "Haven't played in 5 years" both came back
      // empty from James's server. A heading with nothing under it is worse
      // than an absent row.
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Hub': [
              {
                'hubIdentifier': 'music.vault.3',
                'title': "Haven't played in 5 years",
                'type': 'artist',
                'size': 0,
              },
            ],
          },
        }),
      );

      final hub = (await client.sectionHubs('3')).single;
      expect(hub.hasItems, isFalse);
    });
  });
}
