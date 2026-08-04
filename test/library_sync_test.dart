import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/core/sync/library_sync.dart';

/// Sync is the component most likely to fail in ways nobody notices: a
/// half-written cache still renders, it just quietly omits music. These tests
/// pin the behaviour that makes that detectable.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  const section = PlexSection(key: '3', type: 'artist', title: 'Music');

  /// Builds a client serving [items] of the requested type, honouring the
  /// container-header pagination the real server uses.
  PlexClient clientWith({
    List<Map<String, dynamic>> artists = const [],
    List<Map<String, dynamic>> albums = const [],
    List<Map<String, dynamic>> tracks = const [],
    List<String>? requestLog,
  }) {
    return PlexClient(
      server: const PlexServer(
        name: 'Tower',
        baseUrl: 'https://tower.example:32400',
        token: 'tok',
        isLocal: true,
        isRelay: false,
      ),
      identity: PlexIdentity.forTesting(),
      httpClient: MockClient((request) async {
        final type = request.url.queryParameters['type'];
        requestLog?.add(request.url.toString());

        final all = switch (type) {
          '8' => artists,
          '9' => albums,
          '10' => tracks,
          _ => const <Map<String, dynamic>>[],
        };

        final start =
            int.tryParse(request.headers['X-Plex-Container-Start'] ?? '0') ?? 0;
        final size =
            int.tryParse(request.headers['X-Plex-Container-Size'] ?? '100') ??
            100;
        final slice = start >= all.length
            ? const <Map<String, dynamic>>[]
            : all.sublist(start, (start + size).clamp(0, all.length));

        return http.Response(
          jsonEncode({
            'MediaContainer': {'totalSize': all.length, 'Metadata': slice},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  Map<String, dynamic> album(String key, String title, {int? updatedAt}) => {
    'ratingKey': key,
    'title': title,
    'parentTitle': 'Radiohead',
    'parentRatingKey': 'a1',
    'updatedAt': ?updatedAt,
  };

  test('writes artists, albums and tracks into the cache', () async {
    final sync = LibrarySync(
      client: clientWith(
        artists: [
          {'ratingKey': 'a1', 'title': 'Radiohead'},
        ],
        albums: [album('b1', 'Kid A')],
        tracks: [
          {
            'ratingKey': 't1',
            'title': 'Idioteque',
            'parentRatingKey': 'b1',
            'parentTitle': 'Kid A',
            'grandparentTitle': 'Radiohead',
            'index': 8,
            'duration': 320000,
            'Media': [
              {
                'container': 'flac',
                'Part': [
                  {'key': '/library/parts/1/2/file.flac'},
                ],
              },
            ],
          },
        ],
      ),
      db: db,
    );

    final phases = await sync
        .run(section, serverClientIdentifier: 'server-abc')
        .toList();

    expect(phases.last.phase, SyncPhase.done);
    expect((await db.select(db.artists).get()).single.title, 'Radiohead');
    expect((await db.select(db.albums).get()).single.title, 'Kid A');

    final track = (await db.select(db.tracks).get()).single;
    expect(track.title, 'Idioteque');
    // Without the part key the row is unplayable, which would be invisible
    // until someone actually pressed play.
    expect(track.partKey, '/library/parts/1/2/file.flac');
    expect(track.albumRatingKey, 'b1');
  });

  test('paginates through more rows than one page', () async {
    final many = List.generate(450, (i) => album('b$i', 'Album $i'));
    final sync = LibrarySync(
      client: clientWith(albums: many),
      db: db,
      pageSize: 100,
    );

    final progress = await sync
        .run(section, serverClientIdentifier: 'server-abc')
        .toList();

    expect(await db.select(db.albums).get(), hasLength(450));
    // Progress must actually advance, not jump straight to complete.
    final albumProgress = progress.where((p) => p.phase == SyncPhase.albums);
    expect(albumProgress.length, greaterThan(1));
    expect(albumProgress.last.done, 450);
    expect(albumProgress.last.total, 450);
    expect(albumProgress.last.fraction, 1.0);
  });

  test('re-syncing an item updates rather than duplicating it', () async {
    LibrarySync syncWith(String title) => LibrarySync(
      client: clientWith(albums: [album('b1', title)]),
      db: db,
    );

    await syncWith('Kid A').run(section, serverClientIdentifier: 's').drain();
    await syncWith(
      'Kid A (Remastered)',
    ).run(section, serverClientIdentifier: 's').drain();

    final all = await db.select(db.albums).get();
    expect(all, hasLength(1));
    expect(all.single.title, 'Kid A (Remastered)');
  });

  test('records the newest updatedAt as the delta cursor', () async {
    final sync = LibrarySync(
      client: clientWith(
        albums: [
          album('b1', 'Kid A', updatedAt: 1000),
          album('b2', 'Amnesiac', updatedAt: 5000),
          album('b3', 'In Rainbows', updatedAt: 3000),
        ],
      ),
      db: db,
    );

    await sync.run(section, serverClientIdentifier: 'server-abc').drain();

    final state = await db.select(db.syncState).getSingle();
    // The cursor must be the maximum, not the last seen — otherwise a delta
    // sync would re-fetch everything after the highest value forever.
    expect(state.lastSyncedUpdatedAt, 5000);
    expect(state.initialSyncComplete, isTrue);
  });

  test(
    'passes minUpdatedAt through so a delta sync is actually partial',
    () async {
      final log = <String>[];
      final sync = LibrarySync(
        client: clientWith(albums: [album('b1', 'Kid A')], requestLog: log),
        db: db,
      );

      await sync
          .run(
            section,
            serverClientIdentifier: 'server-abc',
            minUpdatedAt: 4242,
          )
          .drain();

      expect(log.any((url) => url.contains('4242')), isTrue);
    },
  );

  test('wipes the cache when the server changes', () async {
    // Cache built against one server.
    await LibrarySync(
      client: clientWith(albums: [album('b1', 'Kid A')]),
      db: db,
    ).run(section, serverClientIdentifier: 'server-ONE').drain();
    expect(await db.select(db.albums).get(), hasLength(1));

    // Same ratingKey, different server, different album entirely.
    await LibrarySync(
      client: clientWith(albums: [album('b1', 'Something Else')]),
      db: db,
    ).run(section, serverClientIdentifier: 'server-TWO').drain();

    final all = await db.select(db.albums).get();
    // Plex ratingKeys are unique only within a server, so the old row must be
    // gone rather than blended into the new library.
    expect(all, hasLength(1));
    expect(all.single.title, 'Something Else');
    expect(
      (await db.select(db.syncState).getSingle()).serverClientIdentifier,
      'server-TWO',
    );
  });

  test(
    'a failure leaves the sync resumable rather than marked complete',
    () async {
      final sync = LibrarySync(
        client: PlexClient(
          server: const PlexServer(
            name: 'Tower',
            baseUrl: 'https://tower.example:32400',
            token: 'tok',
            isLocal: true,
            isRelay: false,
          ),
          identity: PlexIdentity.forTesting(),
          httpClient: MockClient((_) async => http.Response('', 500)),
        ),
        db: db,
      );

      final progress = await sync
          .run(section, serverClientIdentifier: 'server-abc')
          .toList();

      expect(progress.last.phase, SyncPhase.failed);
      // initialSyncComplete must stay false so the next run resumes instead of
      // trusting a half-filled cache.
      expect(await db.select(db.syncState).get(), isEmpty);
    },
  );

  test('fraction is null while the total is unknown', () {
    const unknown = SyncProgress(phase: SyncPhase.albums, done: 10);
    // A bogus 0% is worse than an indeterminate bar.
    expect(unknown.fraction, isNull);
    expect(
      const SyncProgress(phase: SyncPhase.albums, done: 5, total: 10).fraction,
      0.5,
    );
  });
}
