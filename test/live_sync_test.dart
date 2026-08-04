import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/db/normalise.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_notifications.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/core/sync/live_sync.dart';

/// Push sync is the mechanism that decides whether newly added music shows up
/// on its own, and the one place where getting a failure wrong deletes data the
/// server still has.
void main() {
  late AppDatabase db;
  late StreamController<PlexLibraryChange> changes;
  late LiveSync sync;
  late Map<String, Map<String, dynamic>> serverItems;
  late List<String> fetched;
  late int failWithStatus;

  /// Per-fetch responses, consumed in request order, overriding [serverItems].
  /// Lets a test make an earlier request answer later than a later one.
  late List<({Map<String, dynamic> item, Duration delay})> scripted;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    changes = StreamController<PlexLibraryChange>();
    serverItems = {};
    fetched = [];
    scripted = [];
    failWithStatus = 0;

    final client = PlexClient(
      server: const PlexServer(
        name: 'Tower',
        baseUrl: 'https://tower.example:32400',
        token: 'tok',
        isLocal: true,
        isRelay: false,
      ),
      identity: PlexIdentity.forTesting(),
      httpClient: MockClient((request) async {
        if (failWithStatus != 0) {
          return http.Response('', failWithStatus);
        }

        if (request.url.path == '/playlists') {
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'Metadata': [
                  {'ratingKey': 'p1', 'title': 'Road trip', 'smart': '1'},
                ],
              },
            }),
            200,
          );
        }

        final key = request.url.path.split('/').last;
        fetched.add(key);

        Map<String, dynamic>? item;
        if (scripted.isNotEmpty) {
          final next = scripted.removeAt(0);
          await Future<void>.delayed(next.delay);
          item = next.item;
        } else {
          item = serverItems[key];
        }
        if (item == null) return http.Response('', 404);

        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'Metadata': [item],
            },
          }),
          200,
        );
      }),
    );

    sync = LiveSync(client: client, db: db, changes: changes.stream);
    sync.start();
  });

  tearDown(() async {
    await changes.close();
    await sync.stop();
    await db.close();
  });

  /// Pushes a change and waits for it to be written.
  Future<void> push(PlexLibraryChange change) async {
    changes.add(change);
    await pumpEventQueue();
    await sync.settle();
  }

  Future<void> seedAlbum(String key, {String? artistKey}) {
    return db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            ratingKey: key,
            title: 'Album $key',
            normalisedTitle: normalise('Album $key'),
            artistRatingKey: Value(artistKey),
            artistTitle: 'Artist',
            normalisedArtist: normalise('Artist'),
          ),
        );
  }

  Future<void> seedTrack(String key, String albumKey) {
    return db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            ratingKey: key,
            title: 'Track $key',
            normalisedTitle: normalise('Track $key'),
            albumRatingKey: Value(albumKey),
          ),
        );
  }

  test('an added album is fetched and cached', () async {
    serverItems['b1'] = {
      'ratingKey': 'b1',
      'type': 'album',
      'title': 'Kid A',
      'parentTitle': 'Radiohead',
      'year': 2000,
    };

    await push(
      const PlexLibraryChange(
        kind: PlexChangeKind.upserted,
        ratingKey: 'b1',
        metadataType: 9,
      ),
    );

    final row = await db.select(db.albums).getSingle();
    expect(row.title, 'Kid A');
    expect(row.year, 2000);
  });

  test('a track arriving before its album pulls the album in too', () async {
    // Plex finishes scanning individual files first, so this is the normal
    // order, not an edge case. The artist page joins tracks through albums —
    // without the album the new track would simply never appear.
    serverItems['t1'] = {
      'ratingKey': 't1',
      'type': 'track',
      'title': 'Everything In Its Right Place',
      'parentRatingKey': 'b1',
      'parentTitle': 'Kid A',
      'grandparentTitle': 'Radiohead',
    };
    serverItems['b1'] = {
      'ratingKey': 'b1',
      'type': 'album',
      'title': 'Kid A',
      'parentRatingKey': 'a1',
      'parentTitle': 'Radiohead',
    };
    serverItems['a1'] = {
      'ratingKey': 'a1',
      'type': 'artist',
      'title': 'Radiohead',
    };

    await push(
      const PlexLibraryChange(
        kind: PlexChangeKind.upserted,
        ratingKey: 't1',
        metadataType: 10,
      ),
    );

    expect(await db.select(db.tracks).getSingle(), isNotNull);
    expect((await db.select(db.albums).getSingle()).title, 'Kid A');
    expect((await db.select(db.artists).getSingle()).title, 'Radiohead');
    expect(await db.watchTracksForArtist('a1').first, hasLength(1));
  });

  test('does not refetch parents already cached', () async {
    await seedAlbum('b1');
    serverItems['t1'] = {
      'ratingKey': 't1',
      'type': 'track',
      'title': 'Track',
      'parentRatingKey': 'b1',
    };

    await push(
      const PlexLibraryChange(
        kind: PlexChangeKind.upserted,
        ratingKey: 't1',
        metadataType: 10,
      ),
    );

    expect(fetched, ['t1']);
  });

  test('a deleted album takes its tracks with it', () async {
    await seedAlbum('b1');
    await seedTrack('t1', 'b1');
    await seedTrack('t2', 'b1');

    await push(
      const PlexLibraryChange(
        kind: PlexChangeKind.deleted,
        ratingKey: 'b1',
        metadataType: 9,
      ),
    );

    expect(await db.select(db.albums).get(), isEmpty);
    // Orphaned tracks are worse than absent ones: they still list, then 404 on
    // play, which reads as a broken player rather than a deleted album.
    expect(await db.select(db.tracks).get(), isEmpty);
  });

  test('a deleted artist takes albums and tracks with it', () async {
    await seedAlbum('b1', artistKey: 'a1');
    await seedTrack('t1', 'b1');
    await db
        .into(db.artists)
        .insert(
          ArtistsCompanion.insert(
            ratingKey: 'a1',
            title: 'Radiohead',
            normalisedTitle: normalise('Radiohead'),
          ),
        );

    await push(
      const PlexLibraryChange(
        kind: PlexChangeKind.deleted,
        ratingKey: 'a1',
        metadataType: 8,
      ),
    );

    expect(await db.select(db.artists).get(), isEmpty);
    expect(await db.select(db.albums).get(), isEmpty);
    expect(await db.select(db.tracks).get(), isEmpty);
  });

  test('an item that 404s on fetch is removed', () async {
    await seedAlbum('b1');

    await push(
      const PlexLibraryChange(
        kind: PlexChangeKind.upserted,
        ratingKey: 'b1',
        metadataType: 9,
      ),
    );

    expect(await db.select(db.albums).get(), isEmpty);
  });

  test('a server error leaves the cache alone', () async {
    await seedAlbum('b1');
    failWithStatus = 500;

    await push(
      const PlexLibraryChange(
        kind: PlexChangeKind.upserted,
        ratingKey: 'b1',
        metadataType: 9,
      ),
    );

    // Treating a timeout or a 500 as "deleted" would let one bad minute of
    // network empty the library.
    expect(await db.select(db.albums).get(), hasLength(1));
  });

  test('a playlist change refreshes the playlist list', () async {
    await push(
      const PlexLibraryChange(
        kind: PlexChangeKind.upserted,
        ratingKey: 'p1',
        metadataType: 15,
      ),
    );

    final row = await db.select(db.playlists).getSingle();
    expect(row.title, 'Road trip');
    expect(row.smart, isTrue);
  });

  test(
    'falls back to the textual type when the event omits the number',
    () async {
      serverItems['a1'] = {
        'ratingKey': 'a1',
        'type': 'artist',
        'title': 'Björk',
      };

      await push(
        const PlexLibraryChange(kind: PlexChangeKind.upserted, ratingKey: 'a1'),
      );

      expect((await db.select(db.artists).getSingle()).title, 'Björk');
    },
  );

  test('the newest notification wins even if its fetch is faster', () async {
    // The first request is answered slowly and the second quickly. Applied
    // concurrently, the stale response would land last and undo the rename —
    // the classic edit-then-refresh race, which on a library you are actively
    // tagging would show the old title until the next full sync.
    Map<String, dynamic> album(String title) => {
      'ratingKey': 'b1',
      'type': 'album',
      'title': title,
      'parentTitle': 'Artist',
    };

    scripted = [
      (item: album('First'), delay: const Duration(milliseconds: 40)),
      (item: album('Renamed'), delay: Duration.zero),
    ];

    const change = PlexLibraryChange(
      kind: PlexChangeKind.upserted,
      ratingKey: 'b1',
      metadataType: 9,
    );
    changes
      ..add(change)
      ..add(change);

    await pumpEventQueue();
    await sync.settle();

    expect(scripted, isEmpty, reason: 'both fetches should have happened');
    expect((await db.select(db.albums).getSingle()).title, 'Renamed');
  });
}
