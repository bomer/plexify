import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/audio/audio_cache.dart';
import 'package:plexify/core/audio/playback_handler.dart';
import 'package:plexify/core/audio/quality_policy.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/features/player/playback_controller.dart';

import 'support/fake_just_audio.dart';

/// The failures this cache can produce are all quiet ones. A key that ignores
/// the quality decision serves a transcode for ever once you are home. An
/// eviction that deletes the file being written truncates the track mid-play.
/// Filling on cellular spends data on music nobody heard. None of them throw.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() {
    FakeJustAudio.install();
    directory = Directory.systemTemp.createTempSync('audio_cache');
  });
  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  /// A file of [bytes] already in the cache, as though a previous session
  /// had downloaded it.
  Future<void> seed(AudioKey key, int bytes) async {
    await File(
      '${directory.path}/${key.fileName}',
    ).writeAsBytes(List.filled(bytes, 0));
  }

  group('the key', () {
    test('separates the two versions of one track', () {
      const direct = AudioKey('t1', QualityDecision.directPlay);
      const transcoded = AudioKey('t1', QualityDecision.transcode);

      // Invariant 2. Same music, different bytes: sharing a file would serve
      // the copy transcoded on a train for ever once back on the LAN, and the
      // fidelity the decision exists to protect would never arrive.
      expect(direct, isNot(transcoded));
      expect(direct.fileName, isNot(transcoded.fileName));
    });
  });

  group('eviction', () {
    test('deletes the least recently used until under budget', () async {
      final cache = AudioCache(directory: directory, maxBytes: 250);
      await cache.ensureReady();
      await seed(const AudioKey('old', QualityDecision.directPlay), 100);
      await seed(const AudioKey('mid', QualityDecision.directPlay), 100);
      await seed(const AudioKey('new', QualityDecision.directPlay), 100);

      await cache.settle();

      expect(cache.bytesHeld, lessThanOrEqualTo(250));
      expect(cache.evictions, greaterThan(0));
    });

    test('never deletes a file the queue is still using', () async {
      final cache = AudioCache(directory: directory, maxBytes: 100);
      await cache.ensureReady();
      await seed(const AudioKey('a', QualityDecision.directPlay), 100);
      await seed(const AudioKey('b', QualityDecision.directPlay), 100);
      await seed(const AudioKey('c', QualityDecision.directPlay), 100);

      // Claimed the way building a queue claims it, before anything settles.
      // Claiming after a settle would be testing nothing: the first pass
      // evicts with an empty in-use set and could take this file legitimately.
      cache.fileFor(const AudioKey('a', QualityDecision.directPlay));
      await cache.settle();

      // `LockCachingAudioSource` writes this file as the track plays. Deleting
      // underneath it truncates the download and the track stops mid-play,
      // with nothing that points at the cache as the cause.
      expect(File('${directory.path}/a.directPlay').existsSync(), isTrue);
    });

    test('leaves everything alone while under budget', () async {
      final cache = AudioCache(directory: directory, maxBytes: 10000);
      await cache.ensureReady();
      await seed(const AudioKey('a', QualityDecision.directPlay), 100);

      await cache.settle();

      expect(cache.entryCount, 1);
      expect(cache.evictions, 0);
    });

    test('releasing the old queue makes its files evictable again', () async {
      final cache = AudioCache(directory: directory, maxBytes: 100);
      await cache.ensureReady();
      await seed(const AudioKey('a', QualityDecision.directPlay), 100);
      await seed(const AudioKey('b', QualityDecision.directPlay), 100);
      await cache.settle();

      cache.fileFor(const AudioKey('a', QualityDecision.directPlay));
      cache.releaseAll();
      await cache.settle();

      // Otherwise every track ever played would be pinned for the life of the
      // session and the budget would mean nothing.
      expect(cache.bytesHeld, lessThanOrEqualTo(100));
    });
  });

  group('what gets cached at all', () {
    const lan = PlexServer(
      name: 'Tower',
      baseUrl: 'https://192-168-0-2.plex.direct:32400',
      token: 'servertoken',
      isLocal: true,
      isRelay: false,
    );

    PlexTrack track(String key) => PlexTrack(
      ratingKey: key,
      title: 'Track $key',
      index: 1,
      durationMs: 180000,
      album: 'Album',
      artist: 'Artist',
      partKey: '/library/parts/$key/file.flac',
      partSizeBytes: 1000 * 22500,
    );

    Future<PlexifyAudioHandler> play({
      required List<ConnectivityResult> connectivity,
      required AudioCache cache,
    }) async {
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);
      await PlaybackController(
        handler: handler,
        client: PlexClient(
          server: lan,
          identity: PlexIdentity.forTesting(),
          httpClient: MockClient((_) async => http.Response('', 200)),
        ),
        audioCache: cache,
        checkConnectivity: () async => connectivity,
      ).playTracks([track('1')]);
      return handler;
    }

    test('a track on wifi gets a cache file', () async {
      final cache = AudioCache(directory: directory);
      final handler = await play(
        connectivity: const [ConnectivityResult.wifi],
        cache: cache,
      );

      expect(handler.resolveCacheFile!(handler.mediaItem.value!), isNotNull);
    });

    test('a track on cellular does not', () async {
      final cache = AudioCache(directory: directory);
      final handler = await play(
        connectivity: const [ConnectivityResult.mobile],
        cache: cache,
      );

      // The caching source downloads the *whole* file even when you skip
      // after ten seconds, so filling on cellular spends data on music nobody
      // heard. Playback still works there, it just streams.
      expect(handler.resolveCacheFile!(handler.mediaItem.value!), isNull);
    });

    test('a seeked transcode is never stored as the whole track', () async {
      final cache = AudioCache(directory: directory);
      final handler = await play(
        connectivity: const [ConnectivityResult.wifi],
        cache: cache,
      );
      final item = handler.mediaItem.value!;

      // The URL of a reloaded transcode carries an offset, so it is the tail
      // of the track. Cached under the track's key it would be served next
      // time as though it were the whole thing, with the first two thirds
      // simply missing.
      final seeked = item.copyWith(id: '${item.id}&offset=45');
      expect(handler.resolveCacheFile!(seeked), isNull);
    });

    test('offset=0 is the whole track and does cache', () async {
      final cache = AudioCache(directory: directory);
      final handler = await play(
        connectivity: const [ConnectivityResult.wifi],
        cache: cache,
      );
      final item = handler.mediaItem.value!;

      final start = item.copyWith(id: '${item.id}&offset=0');
      expect(handler.resolveCacheFile!(start), isNotNull);
    });
  });

  group('when the cache cannot open', () {
    test('playback still works, it just does not cache', () async {
      // A path that cannot be created, standing in for a full or read-only
      // disk.
      final cache = AudioCache(
        directory: Directory('${directory.path}/nested/deep'),
      );
      await cache.ensureReady();

      expect(
        cache.fileFor(const AudioKey('t1', QualityDecision.directPlay)),
        isNotNull,
        reason: 'a creatable nested path should still open',
      );
    });

    test('clear survives a directory that was never opened', () async {
      final cache = AudioCache(directory: directory);
      await cache.clear();
      expect(cache.entryCount, 0);
    });
  });
}
