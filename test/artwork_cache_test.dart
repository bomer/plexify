import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/artwork/artwork_cache.dart';

/// The failure this cache exists to prevent is not "images load slowly" — it is
/// "images are refetched constantly and nobody notices". A URL-keyed cache looks
/// perfect on a desk and misses on every single thumbnail the moment the token
/// is refreshed or the connection re-races between LAN and remote, which is the
/// exact moment the phone is on mobile data.
void main() {
  const thumb = '/library/metadata/41/thumb/1699887000';

  late Directory directory;
  late List<String> fetched;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('artwork_test');
    fetched = [];
  });
  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  /// A cache whose every fetch is recorded, returning [bytes] bytes of image.
  ArtworkCache cacheOf({int bytes = 64, int? maxBytes}) {
    return ArtworkCache(
      directory: directory,
      maxBytes: maxBytes,
      httpClient: MockClient((request) async {
        fetched.add(request.url.toString());
        return http.Response.bytes(Uint8List(bytes), 200);
      }),
    );
  }

  test('a hung fetch gives up rather than blocking the queue', () async {
    final started = <String>[];
    final cache = ArtworkCache(
      directory: directory,
      httpClient: MockClient((request) {
        started.add(request.url.toString());
        // Never answers. A degrading connection produces this rather than a
        // clean failure: the socket opens and then nothing comes back.
        return Completer<http.Response>().future;
      }),
      fetchTimeout: const Duration(milliseconds: 20),
    );

    // One more than the concurrency limit, so the last one can only run if the
    // hung ones have released their slots.
    final waiting = [
      for (var i = 0; i <= ArtworkCache.maxConcurrentFetches; i++)
        cache.load(ArtworkKey('/thumb/$i', 300), 'https://tower/$i'),
    ];
    final results = await Future.wait(waiting);

    // **Without a timeout this never returns.** `package:http` waits
    // indefinitely, so four hung requests hold every slot and every image
    // behind them waits for the rest of the session — a grid of placeholders
    // that stays empty even after the network comes back.
    expect(results.every((bytes) => bytes == null), isTrue);
    expect(
      started.length,
      greaterThan(ArtworkCache.maxConcurrentFetches),
      reason: 'the queue drained rather than jamming',
    );
    expect(cache.lastError, isNotNull);
  });

  /// The URL for a thumb, as `PlexClient.artworkUrl` builds it: base address
  /// and token both embedded, and both liable to change.
  String urlFor(
    String path, {
    String base = 'https://10-0-0-4.plex.direct:32400',
    String token = 'token-one',
    int size = 300,
  }) =>
      '$base/photo/:/transcode?width=$size&height=$size&url=$base$path'
      '&X-Plex-Token=$token';

  group('keying', () {
    test('a second read of the same image does not fetch again', () async {
      final cache = cacheOf();

      await cache.load(const ArtworkKey(thumb, 300), urlFor(thumb));
      await cache.load(const ArtworkKey(thumb, 300), urlFor(thumb));

      expect(fetched, hasLength(1));
    });

    test('a new token is a hit, not a second copy', () async {
      final cache = cacheOf();

      await cache.load(const ArtworkKey(thumb, 300), urlFor(thumb));
      // Same image, different URL — this is what a token refresh looks like.
      await cache.load(
        const ArtworkKey(thumb, 300),
        urlFor(thumb, token: 'token-two'),
      );

      expect(fetched, hasLength(1));
      expect(cache.entryCount, 1);
    });

    test('a new server address is a hit too', () async {
      final cache = cacheOf();

      await cache.load(const ArtworkKey(thumb, 300), urlFor(thumb));
      // Walking out of the house re-races the connection to the remote
      // address. Every visible thumbnail arrives here at once.
      await cache.load(
        const ArtworkKey(thumb, 300),
        urlFor(thumb, base: 'https://82-1-2-3.plex.direct:32400'),
      );

      expect(fetched, hasLength(1));
    });

    test('the same image at two sizes is two entries', () async {
      final cache = cacheOf();

      await cache.load(const ArtworkKey(thumb, 300), urlFor(thumb));
      await cache.load(const ArtworkKey(thumb, 600), urlFor(thumb, size: 600));

      // A 300px grid cell and a 600px artist header are different bytes;
      // sharing an entry would serve one at the other's resolution.
      expect(fetched, hasLength(2));
      expect(cache.entryCount, 2);
    });

    test('new artwork for the same album is a different key', () async {
      final cache = cacheOf();

      await cache.load(const ArtworkKey(thumb, 300), urlFor(thumb));
      // Plex puts a timestamp in the thumb path, so replacing the cover art
      // changes it. Without that this cache could never show a new cover.
      const replaced = '/library/metadata/41/thumb/1700000000';
      await cache.load(const ArtworkKey(replaced, 300), urlFor(replaced));

      expect(fetched, hasLength(2));
    });
  });

  group('persistence', () {
    test('a restart reads from disk rather than the network', () async {
      await cacheOf().load(const ArtworkKey(thumb, 300), urlFor(thumb));

      // A fresh instance over the same directory is what a cold start is: the
      // in-memory index is gone and has to be rebuilt from the files.
      final relaunched = cacheOf();
      final bytes = await relaunched.load(
        const ArtworkKey(thumb, 300),
        urlFor(thumb),
      );

      expect(bytes, isNotNull);
      expect(fetched, hasLength(1));
      expect(relaunched.entryCount, 1);
    });

    test('a cached image needs no connection at all', () async {
      final cache = cacheOf();
      await cache.load(const ArtworkKey(thumb, 300), urlFor(thumb));

      // Null url is what `Artwork` passes while disconnected. Browsing offline
      // has to draw the grid, not a wall of placeholders.
      final bytes = await cache.load(const ArtworkKey(thumb, 300), null);

      expect(bytes, isNotNull);
      expect(fetched, hasLength(1));
    });

    test('an uncached image while disconnected is null, not a throw', () async {
      final bytes = await cacheOf().load(const ArtworkKey(thumb, 300), null);

      expect(bytes, isNull);
    });
  });

  group('bounds', () {
    test('stays under budget by dropping the oldest', () async {
      // Room for two of these, not three.
      final cache = cacheOf(bytes: 100, maxBytes: 250);

      await cache.load(const ArtworkKey('/a', 300), urlFor('/a'));
      await cache.load(const ArtworkKey('/b', 300), urlFor('/b'));
      await cache.load(const ArtworkKey('/c', 300), urlFor('/c'));

      expect(cache.bytesHeld, lessThanOrEqualTo(250));
      expect(directory.listSync(), hasLength(2));
    });

    test('evicts least recently *used*, not least recently added', () async {
      final cache = cacheOf(bytes: 100, maxBytes: 250);

      await cache.load(const ArtworkKey('/a', 300), urlFor('/a'));
      await cache.load(const ArtworkKey('/b', 300), urlFor('/b'));
      // Touching A makes B the oldest. An add-ordered cache would drop A here
      // and refetch the album you are actually looking at.
      await cache.load(const ArtworkKey('/a', 300), urlFor('/a'));
      await cache.load(const ArtworkKey('/c', 300), urlFor('/c'));

      fetched.clear();
      await cache.load(const ArtworkKey('/a', 300), urlFor('/a'));
      expect(fetched, isEmpty);
    });
  });

  group('failures', () {
    test('a server error caches nothing', () async {
      final cache = ArtworkCache(
        directory: directory,
        httpClient: MockClient((_) async => http.Response('', 500)),
      );

      expect(
        await cache.load(const ArtworkKey(thumb, 300), urlFor(thumb)),
        isNull,
      );
      // Storing the failure would show the placeholder for this album until
      // the artwork path changed, which could be never.
      expect(cache.entryCount, 0);
    });

    test(
      'an unreachable server is reported as no image, not an error',
      () async {
        final cache = ArtworkCache(
          directory: directory,
          httpClient: MockClient(
            (_) async => throw http.ClientException('no route'),
          ),
        );

        expect(
          await cache.load(const ArtworkKey(thumb, 300), urlFor(thumb)),
          isNull,
        );
      },
    );

    test('concurrent reads of one image share a single fetch', () async {
      final cache = cacheOf();

      await Future.wait([
        cache.load(const ArtworkKey(thumb, 300), urlFor(thumb)),
        cache.load(const ArtworkKey(thumb, 300), urlFor(thumb)),
        cache.load(const ArtworkKey(thumb, 300), urlFor(thumb)),
      ]);

      // A scrolling grid asks for the same album from several builds before
      // the first request returns.
      expect(fetched, hasLength(1));
    });
  });

  group('clearing', () {
    test('leaves nothing behind for the next server', () async {
      final cache = cacheOf();
      await cache.load(const ArtworkKey(thumb, 300), urlFor(thumb));

      await cache.clear();

      expect(cache.entryCount, 0);
      expect(directory.listSync(), isEmpty);
    });
  });

  group('a grid asking all at once', () {
    test('never has more than the gate open on the server', () async {
      var open = 0;
      var peak = 0;
      final cache = ArtworkCache(
        directory: directory,
        httpClient: MockClient((_) async {
          open++;
          if (open > peak) peak = open;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          open--;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );

      // Thirty at once is what a grid plus its prefetch actually asks for.
      // Every one is a transcode on the server, not a file read, and a burst
      // that size is what got some of them refused.
      await Future.wait([
        for (var i = 0; i < 30; i++)
          cache.load(ArtworkKey('/thumb/$i', 300), 'https://plex.test/$i'),
      ]);

      expect(peak, lessThanOrEqualTo(ArtworkCache.maxConcurrentFetches));
    });

    test('still fetches every one of them', () async {
      final cache = ArtworkCache(
        directory: directory,
        httpClient: MockClient(
          (_) async => http.Response.bytes([1, 2, 3], 200),
        ),
      );

      await Future.wait([
        for (var i = 0; i < 30; i++)
          cache.load(ArtworkKey('/thumb/$i', 300), 'https://plex.test/$i'),
      ]);

      // Queued, not dropped. A gate that shed load would trade a random
      // scatter of blank tiles for a predictable one.
      expect(cache.entryCount, 30);
    });

    test(
      'retries a refusal once, since a busy server is not a missing image',
      () async {
        var attempts = 0;
        final cache = ArtworkCache(
          directory: directory,
          httpClient: MockClient((_) async {
            attempts++;
            return attempts == 1
                ? http.Response('', 503)
                : http.Response.bytes([1, 2, 3], 200);
          }),
        );

        final bytes = await cache.load(
          const ArtworkKey('/thumb/1', 300),
          'https://plex.test/1',
        );

        expect(attempts, 2);
        expect(bytes, isNotNull);
        expect(cache.fetchFailures, 0);
      },
    );

    test('gives up after the retry and says why', () async {
      final cache = ArtworkCache(
        directory: directory,
        httpClient: MockClient((_) async => http.Response('', 404)),
      );

      final bytes = await cache.load(
        const ArtworkKey('/thumb/1', 300),
        'https://plex.test/1',
      );

      // Two attempts, then a placeholder — not an infinite retry that would
      // hammer the server for an image that genuinely is not there.
      expect(bytes, isNull);
      expect(cache.fetchFailures, 1);
      expect(cache.lastError, contains('404'));
    });

    test('a slot is released even when the fetch throws', () async {
      var calls = 0;
      final cache = ArtworkCache(
        directory: directory,
        httpClient: MockClient((_) async {
          calls++;
          if (calls <= 2) throw const SocketException('refused');
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );

      // The first request fails both attempts. If its slot were not returned
      // the gate would leak one, and after four such failures the cache would
      // stop fetching entirely — artwork would work until it silently did not.
      await cache.load(const ArtworkKey('/a', 300), 'https://plex.test/a');
      final second = await cache.load(
        const ArtworkKey('/b', 300),
        'https://plex.test/b',
      );

      expect(second, isNotNull);
    });
  });
}
