import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/artwork/artwork_cache.dart';
import 'package:plexify/core/audio/playback_handler.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/core/settings/app_settings.dart';
import 'package:plexify/core/sync/sync_scheduler.dart';
import 'package:plexify/features/settings/account_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Leaving a server is the one operation that deletes data, and the damage from
/// getting it wrong is not visible immediately: rows from the previous server
/// left behind do not look wrong, they look like a library. Plex numbers items
/// per server, so the two sets blend, and every stale row is a 404 waiting to
/// happen on the next tap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const localUri = 'https://local.plex.direct:32400';

  late AppDatabase db;
  late Directory artworkDirectory;
  late ArtworkCache artwork;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    artworkDirectory = Directory.systemTemp.createTempSync('account_artwork');
    artwork = ArtworkCache(directory: artworkDirectory);
    SharedPreferences.setMockInitialValues({});
    // Signing out deletes the token, and the real Keystore/DPAPI channel is not
    // available under `flutter test`.
    FlutterSecureStorage.setMockInitialValues({'plex_auth_token': 'token'});
  });
  tearDown(() async {
    await db.close();
    if (artworkDirectory.existsSync()) {
      artworkDirectory.deleteSync(recursive: true);
    }
  });

  /// A server resource with one connection, reachable or not per [reaching].
  Map<String, dynamic> resource(String id, String name, String uri) => {
    'name': name,
    'clientIdentifier': id,
    'provides': 'server',
    'owned': true,
    'accessToken': 'servertoken',
    'connections': [
      {'uri': uri, 'local': true, 'relay': false},
    ],
  };

  PlexDiscovery discovery({
    required List<Map<String, dynamic>> servers,
    Set<String> reaching = const {},
    List<String>? probed,
  }) {
    final reachable = reaching.map((u) => Uri.parse(u).host).toSet();
    return PlexDiscovery(
      identity: PlexIdentity.forTesting(),
      httpClient: MockClient((request) async {
        if (request.url.host == 'plex.tv') {
          return http.Response(_json(servers), 200);
        }
        probed?.add(request.url.host);
        return reachable.contains(request.url.host)
            ? http.Response('{}', 200)
            : http.Response('', 500);
      }),
    );
  }

  Future<ProviderContainer> containerWith({
    PlexDiscovery? withDiscovery,
    SyncScheduler? scheduler,
    String? token = 'token',
    String? preferredServer,
  }) async {
    final store = SettingsStore(await SharedPreferences.getInstance());
    if (preferredServer != null) {
      await store.write(AppSettings(preferredServerId: preferredServer));
    }

    final c = ProviderContainer(
      overrides: [
        plexIdentityProvider.overrideWithValue(PlexIdentity.forTesting()),
        settingsStoreProvider.overrideWithValue(store),
        databaseProvider.overrideWithValue(db),
        artworkCacheProvider.overrideWithValue(artwork),
        authTokenProvider.overrideWith((ref) => token),
        audioHandlerProvider.overrideWithValue(PlexifyAudioHandler()),
        if (withDiscovery != null)
          plexDiscoveryProvider.overrideWithValue(withDiscovery),
        if (scheduler != null)
          syncSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// One album, so an empty cache afterwards means something.
  Future<void> seedCache() async {
    await db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            ratingKey: 'a1',
            title: 'Kid A',
            normalisedTitle: 'kid a',
            artistTitle: 'Radiohead',
            normalisedArtist: 'radiohead',
          ),
        );
  }

  group('signing out', () {
    test('forgets the token', () async {
      final c = await containerWith();

      await c.read(accountControllerProvider).signOut();

      expect(c.read(authTokenProvider), isNull);
    });

    test('wipes the cache the next server cannot use', () async {
      await seedCache();
      final c = await containerWith();

      await c.read(accountControllerProvider).signOut();

      expect(await db.countAlbums(), 0);
    });

    test('takes the artwork with it', () async {
      File('${artworkDirectory.path}/cover').writeAsBytesSync([1, 2, 3]);
      final c = await containerWith();

      await c.read(accountControllerProvider).signOut();

      // Thumb paths are server-scoped, so the same path on another server is
      // different art. Keeping the files would show one library's covers over
      // another's albums.
      expect(artworkDirectory.listSync(), isEmpty);
    });

    test(
      'leaves nothing in the mini player pointing at the old server',
      () async {
        final c = await containerWith();
        final handler = c.read(audioHandlerProvider);
        handler.mediaItem.add(_item);

        await c.read(accountControllerProvider).signOut();

        // The mini player hides on a null mediaItem and on nothing else, so this
        // is what the difference looks like on screen.
        expect(handler.mediaItem.value, isNull);
        expect(handler.queue.value, isEmpty);
      },
    );
  });

  group('teardown order', () {
    test('the writers are stopped while the cache still has rows', () async {
      await seedCache();
      final spy = _SpyScheduler(db: db);
      final c = await containerWith(scheduler: spy);

      await c.read(accountControllerProvider).signOut();

      // Stopping after the wipe would be worse than not stopping at all: a
      // scheduler mid-pass, or a socket delivering a pushed change, writes the
      // old server's rows straight back into a cache that is meant to be empty
      // — and nothing later notices, because the wipe already happened.
      expect(spy.albumsWhenStopped, 1);
      expect(await db.countAlbums(), 0);
    });
  });

  group('switching server', () {
    test('records the choice', () async {
      final c = await containerWith();

      await c.read(accountControllerProvider).switchTo('server-b');

      expect(c.read(settingsProvider).preferredServerId, 'server-b');
    });

    test('keeps the token — it is one account, not a new login', () async {
      final c = await containerWith();

      await c.read(accountControllerProvider).switchTo('server-b');

      expect(c.read(authTokenProvider), 'token');
    });

    test('wipes the cache, since ratingKeys mean nothing elsewhere', () async {
      await seedCache();
      final c = await containerWith();

      await c.read(accountControllerProvider).switchTo('server-b');

      expect(await db.countAlbums(), 0);
    });

    test('releases the choice when asked for any server', () async {
      final c = await containerWith(preferredServer: 'server-a');

      await c.read(accountControllerProvider).switchTo(null);

      expect(c.read(settingsProvider).preferredServerId, isNull);
    });
  });

  group('which server is connected', () {
    test('with no preference, the first that answers wins', () async {
      final c = await containerWith(
        withDiscovery: discovery(
          servers: [
            resource('a', 'Tower', localUri),
            resource('b', 'Attic', 'https://other.plex.direct:32400'),
          ],
          reaching: {localUri, 'https://other.plex.direct:32400'},
        ),
      );

      final server = await c.read(connectServerProvider.future);

      expect(server?.clientIdentifier, 'a');
    });

    test('a chosen server is the only one tried', () async {
      final probed = <String>[];
      final c = await containerWith(
        preferredServer: 'b',
        withDiscovery: discovery(
          servers: [
            resource('a', 'Tower', localUri),
            resource('b', 'Attic', 'https://other.plex.direct:32400'),
          ],
          reaching: {localUri, 'https://other.plex.direct:32400'},
          probed: probed,
        ),
      );

      final server = await c.read(connectServerProvider.future);

      expect(server?.clientIdentifier, 'b');
      // Not merely last-one-wins: the unwanted server is never even probed.
      expect(probed, isNot(contains('local.plex.direct')));
    });

    test('a chosen server that is down does not fall back to another', () async {
      final c = await containerWith(
        preferredServer: 'b',
        withDiscovery: discovery(
          servers: [
            resource('a', 'Tower', localUri),
            resource('b', 'Attic', 'https://other.plex.direct:32400'),
          ],
          // Only the *other* server answers.
          reaching: {localUri},
        ),
      );

      // Connecting to A instead would wipe B's cache and sync A's library, and
      // then do it again in reverse the moment B came back. Better to stay
      // disconnected and keep browsing the cache.
      expect(await c.read(connectServerProvider.future), isNull);
    });
  });
}

const _item = MediaItem(
  id: 'https://old.example/track.flac',
  title: 'Idioteque',
);

/// A scheduler that records what the cache looked like when it was told to stop.
class _SpyScheduler extends SyncScheduler {
  _SpyScheduler({required this.db})
    : super(
        db: db,
        client: PlexClient(
          server: const PlexServer(
            name: 'Tower',
            baseUrl: 'https://local.plex.direct:32400',
            token: 't',
            isLocal: true,
            isRelay: false,
          ),
          identity: PlexIdentity.forTesting(),
          httpClient: MockClient((_) async => http.Response('', 500)),
        ),
      );

  final AppDatabase db;
  int? albumsWhenStopped;

  @override
  Future<void> stop() async {
    albumsWhenStopped = await db.countAlbums();
    await super.stop();
  }
}

String _json(List<Map<String, dynamic>> servers) => jsonEncode(servers);
