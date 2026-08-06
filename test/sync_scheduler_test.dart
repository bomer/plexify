import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/core/sync/sync_scheduler.dart';

/// The cheap tier of the sync design: ask a small question often, and only do
/// real work when the answer says something moved.
void main() {
  late AppDatabase db;
  late SyncScheduler scheduler;
  late List<String> requests;

  /// Query parameters of every section listing, so tests can tell a delta pass
  /// from a full one.
  late List<Map<String, String>> listingQueries;

  // What /library/sections currently reports for the music section.
  late int sectionUpdatedAt;
  late int sectionScannedAt;

  /// Albums the server returns from a listing. Empty unless a test cares.
  late List<Map<String, dynamic>> albumsFromServer;

  /// Injected clock, so the slow delta sweep can be reached without waiting.
  late DateTime clock;

  const serverId = 'server-1';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    requests = [];
    listingQueries = [];
    albumsFromServer = [];
    sectionUpdatedAt = 100;
    sectionScannedAt = 100;
    clock = DateTime(2026, 8, 4, 12);

    final client = PlexClient(
      server: const PlexServer(
        name: 'Tower',
        baseUrl: 'https://tower.example:32400',
        token: 'tok',
        isLocal: true,
        isRelay: false,
        clientIdentifier: serverId,
      ),
      identity: PlexIdentity.forTesting(),
      httpClient: MockClient((request) async {
        requests.add(request.url.path);

        if (request.url.path == '/library/sections') {
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'Directory': [
                  {
                    'key': '3',
                    'type': 'artist',
                    'title': 'Music',
                    'updatedAt': sectionUpdatedAt,
                    'scannedAt': sectionScannedAt,
                  },
                ],
              },
            }),
            200,
          );
        }

        if (request.url.path.endsWith('/refresh')) {
          return http.Response('', 200);
        }

        if (request.url.path.endsWith('/all')) {
          listingQueries.add(request.url.queryParameters);

          // Type 9 is albums. Everything else stays empty, so a sync is
          // otherwise a no-op that still leaves fingerprints in `requests`.
          final isAlbumPage =
              request.url.queryParameters['type'] == '9' &&
              request.url.queryParameters['X-Plex-Container-Start'] != '1';

          // **The fake applies the delta filter, and that is load-bearing.**
          // It did not until #52, so every test passed whether the sweep
          // filtered or not, and a regression that made ratings unreachable by
          // sync shipped with a green suite. A fake server that answers the
          // same however it is asked is not testing the question.
          final cutoff = request.url.queryParameters[PlexClient.deltaFilter];
          final visible = cutoff == null
              ? albumsFromServer
              : albumsFromServer
                    .where(
                      (a) => (a['updatedAt'] as int? ?? 0) > int.parse(cutoff),
                    )
                    .toList();

          if (isAlbumPage && visible.isNotEmpty) {
            albumsFromServer = [];
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': visible.length,
                  'Metadata': visible,
                },
              }),
              200,
            );
          }
        }

        return http.Response(
          jsonEncode({
            'MediaContainer': {'totalSize': 0},
          }),
          200,
        );
      }),
    );

    scheduler = SyncScheduler(
      client: client,
      db: db,
      pollInterval: const Duration(milliseconds: 20),
      now: () => clock,
    );
  });

  tearDown(() async {
    await scheduler.stop();
    await db.close();
  });

  /// Pretends a full sync already finished against this server.
  ///
  /// [sweptAt] is what makes a *relaunch* distinguishable from a first run:
  /// null means the sweep clock has never been written, which is a fresh
  /// install and always sweeps.
  Future<void> seedSyncedState({
    int updatedAt = 100,
    int scannedAt = 100,
    int cursor = 50,
    DateTime? sweptAt,
    bool initialComplete = true,
  }) {
    return db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            sectionKey: '3',
            serverClientIdentifier: serverId,
            lastSyncedUpdatedAt: Value(cursor),
            serverUpdatedAt: Value(updatedAt),
            serverScannedAt: Value(scannedAt),
            initialSyncComplete: Value(initialComplete),
            lastDeltaSweepAt: Value(sweptAt?.millisecondsSinceEpoch),
          ),
        );
  }

  bool syncedSinceLastCheck() => requests.any((path) => path.contains('/all'));

  void clearRequests() => requests.clear();

  test('the first pass runs even when nothing looks changed', () async {
    await seedSyncedState();

    await scheduler.start();

    // Never swept before, so this is the once-per-install pass rather than a
    // launch cost. The relaunch tests below are what stop it happening again.
    expect(syncedSinceLastCheck(), isTrue);
    expect(scheduler.passes, 1);
  });

  group('relaunching', () {
    test('a sweep inside the window is not repeated', () async {
      await seedSyncedState(
        sweptAt: clock.subtract(const Duration(minutes: 1)),
      );

      await scheduler.start();

      // The whole point of the change. `start` used to force a pass and the
      // sweep clock lived only in memory, so it reset every launch and a sweep
      // was permanently due. Against a server that ignores the delta filter,
      // and James's does, that meant refetching all 13,704 rows on every
      // launch: about seventy requests to learn nothing.
      expect(syncedSinceLastCheck(), isFalse);
      expect(requests, ['/library/sections']);
    });

    test('a sweep past the window still runs', () async {
      await seedSyncedState(
        sweptAt: clock.subtract(const Duration(minutes: 20)),
      );

      await scheduler.start();

      // The sweep exists to catch metadata edits the section clocks never
      // announce, ratings set in Plex above all. Skipping it because the app
      // restarted would be the previous bug in the other direction.
      expect(syncedSinceLastCheck(), isTrue);
    });

    test('an unfinished initial sync syncs however recent the sweep', () async {
      await seedSyncedState(
        sweptAt: clock.subtract(const Duration(seconds: 1)),
        initialComplete: false,
      );

      await scheduler.start();

      // This is what `force: true` was really protecting, and it survives
      // without it: an incomplete initial sync has to resume, and a partial
      // cache that stopped resuming would look like a library missing half its
      // albums for ever.
      expect(syncedSinceLastCheck(), isTrue);
    });

    test('the sweep is remembered across a restart', () async {
      await seedSyncedState();
      await scheduler.start();

      // Held in memory alone this reads back null, the next launch sweeps, and
      // the two tests above can never be reached in practice.
      expect(await db.lastDeltaSweepAt(), isNotNull);
    });
  });

  test('a poll with nothing changed costs one small request', () async {
    await seedSyncedState();
    await scheduler.start();
    clearRequests();

    // Clock deliberately still, so the slow delta sweep is not yet due.
    await scheduler.wake();

    expect(requests, ['/library/sections']);
    expect(syncedSinceLastCheck(), isFalse);
  });

  test('a changed updatedAt triggers a sync', () async {
    await seedSyncedState();
    await scheduler.start();
    clearRequests();

    sectionUpdatedAt = 200;
    await scheduler.wake();

    expect(syncedSinceLastCheck(), isTrue);
  });

  test('a changed scannedAt triggers a sync on its own', () async {
    await seedSyncedState();
    await scheduler.start();
    clearRequests();

    // A scan that finds new music bumps scannedAt first. Watching only
    // updatedAt would miss precisely the case this exists for.
    sectionScannedAt = 300;
    await scheduler.wake();

    expect(syncedSinceLastCheck(), isTrue);
  });

  test(
    'pull to refresh asks the server to rescan, then syncs anyway',
    () async {
      await seedSyncedState();
      await scheduler.start();
      clearRequests();

      await scheduler.refreshNow();

      // Forced: someone who pulls to refresh has already decided the screen is
      // wrong, and "nothing changed" would be the app arguing with them.
      expect(requests, contains('/library/sections/3/refresh'));
      expect(syncedSinceLastCheck(), isTrue);
    },
  );

  test(
    'a rating set in Plex arrives even with the section clocks still',
    () async {
      await seedSyncedState();
      await scheduler.start();
      clearRequests();

      // Two things are deliberately still here, and both were measured against
      // the real server on 6 August 2026.
      //
      // The section clocks do not move: rating an album leaves the library's
      // shape identical, so a scheduler trusting them alone never looks.
      //
      // **And the album's own `updatedAt` does not move either**, which is why it
      // sits below the stored cursor. That is the part that caught this project
      // out. While Plex was ignoring the delta filter every sweep was
      // accidentally a full pass and ratings arrived by brute force; the moment
      // the filter started working, the sweep could no longer see the one thing
      // it exists for. The sweep is therefore unfiltered, and this is the test
      // that says so.
      clock = clock.add(const Duration(minutes: 16));
      albumsFromServer = [
        {
          'ratingKey': 'b1',
          'title': 'Kid A',
          'parentTitle': 'Radiohead',
          'userRating': 10,
          'updatedAt': 10,
        },
      ];

      await scheduler.wake();

      final favourites = await db.watchFavouriteAlbums().first;
      expect(favourites.map((a) => a.title), ['Kid A']);
    },
  );

  test(
    'the sweep asks without a filter, the clock check asks with one',
    () async {
      await seedSyncedState(cursor: 4242, sweptAt: clock);

      // Something appeared, so the section clock moved. Whatever moved it also
      // moved its own updatedAt, so this pass can afford to filter.
      sectionUpdatedAt = 200;
      await scheduler.start();
      expect(
        listingQueries.every((q) => q[PlexClient.deltaFilter] == '4241'),
        isTrue,
        reason: 'a clock-triggered pass should carry the cursor',
      );

      // Now nothing has moved and the sweep falls due. This one has to ask
      // unfiltered, because what it is looking for never moves a timestamp.
      listingQueries.clear();
      sectionUpdatedAt = 200;
      clock = clock.add(const Duration(minutes: 16));
      await scheduler.wake();

      expect(listingQueries, isNotEmpty);
      expect(
        listingQueries.any((q) => q.containsKey(PlexClient.deltaFilter)),
        isFalse,
        reason: 'a sweep that filtered could never find a rating',
      );
    },
  );

  test('a forced refresh asks without a filter', () async {
    await seedSyncedState(cursor: 4242, sweptAt: clock);
    await scheduler.start();
    listingQueries.clear();

    await scheduler.refreshNow();

    // Someone who pressed refresh has already decided the screen is wrong.
    // Answering with a cheap query that structurally cannot see a rating would
    // be the app arguing with them.
    expect(listingQueries, isNotEmpty);
    expect(
      listingQueries.any((q) => q.containsKey(PlexClient.deltaFilter)),
      isFalse,
    );
  });

  test('a delta pass asks Plex only for what changed', () async {
    // Swept just now, so the section clock moving is the only reason to sync.
    // Without that this is a sweep, and a sweep is deliberately unfiltered.
    await seedSyncedState(cursor: 4242, sweptAt: clock);
    sectionUpdatedAt = 200;

    await scheduler.start();

    // Without this the "delta" sync would quietly be a full one every time,
    // which on a 50k-track library is the difference between seconds and
    // minutes of needless traffic.
    expect(listingQueries, isNotEmpty);
    expect(
      listingQueries.every((q) => q[PlexClient.deltaFilter] == '4241'),
      isTrue,
      reason: 'every listing should carry the stored cursor',
    );
  });

  test('a cache from another server is resynced in full', () async {
    await db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            sectionKey: '3',
            serverClientIdentifier: 'a-different-server',
            lastSyncedUpdatedAt: const Value(50),
            serverUpdatedAt: const Value(100),
            serverScannedAt: const Value(100),
            initialSyncComplete: const Value(true),
          ),
        );

    await scheduler.start();

    // ratingKeys collide across servers, so the other server's cursor is
    // meaningless here — carrying it over would skip everything older than a
    // timestamp from an unrelated library.
    expect(listingQueries, isNotEmpty);
    expect(
      listingQueries.any((q) => q.containsKey(PlexClient.deltaFilter)),
      isFalse,
      reason: 'a foreign cursor must not be reused',
    );

    final state = await db.select(db.syncState).getSingle();
    expect(state.serverClientIdentifier, serverId);
  });

  test('an unreachable server is retried, not reported as failure', () async {
    final failing = SyncScheduler(
      client: PlexClient(
        server: const PlexServer(
          name: 'Tower',
          baseUrl: 'https://tower.example:32400',
          token: 'tok',
          isLocal: true,
          isRelay: false,
          clientIdentifier: serverId,
        ),
        identity: PlexIdentity.forTesting(),
        httpClient: MockClient((_) async => http.Response('', 500)),
      ),
      db: db,
      pollInterval: const Duration(milliseconds: 20),
    );

    final events = <String>[];
    failing.progress.listen((p) => events.add(p.phase.name));

    await failing.start();
    await pumpEventQueue();

    // Being off the LAN is the normal case, not an error state worth a banner.
    expect(events, isEmpty);
    expect(failing.passes, 0);
    await failing.stop();
  });

  test('pausing stops the polling until resumed', () async {
    await seedSyncedState();
    await scheduler.start();
    scheduler.pause();
    clearRequests();

    await Future<void>.delayed(const Duration(milliseconds: 80));

    // Android keeps the isolate alive for a whole playback session, so a poll
    // that ignored the foreground would run for hours down a mobile connection
    // checking for changes to a screen nobody is looking at.
    expect(requests, isEmpty);

    await scheduler.resume();

    // Resuming checks straight away rather than waiting out an interval, so
    // what you see on coming back is current.
    expect(requests, isNotEmpty);
  });

  test('stop ends the polling', () async {
    await seedSyncedState();
    await scheduler.start();
    await scheduler.stop();
    clearRequests();

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(requests, isEmpty);
  });
}
