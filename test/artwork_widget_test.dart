import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/artwork/artwork_cache.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/features/library/artwork.dart';

/// The cache is unit-tested on its own; this covers the part that only fails in
/// a running app. `PlexArtwork` is a custom [ImageProvider], and getting that
/// wrong — the wrong override, a codec never completed — produces no analyzer
/// complaint and no failing unit test, just an app with no artwork anywhere.
void main() {
  /// A 1×1 PNG. Small, and more importantly a real one: the point is that it
  /// reaches Flutter's decoder and comes back as a frame.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('artwork_widget');
    // Flutter's ImageCache is global and outlives a test. Two tests using the
    // same thumb would otherwise share a decoded image — which is the caching
    // working, but it makes the second test measure the first.
    imageCache.clear();
    imageCache.clearLiveImages();
  });
  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  const server = PlexServer(
    name: 'Tower',
    baseUrl: 'https://10-0-0-4.plex.direct:32400',
    token: 'token',
    isLocal: true,
    isRelay: false,
  );

  Future<void> pump(
    WidgetTester tester, {
    required String? thumb,
    required bool serverAnswers,
  }) async {
    final cache = ArtworkCache(
      directory: directory,
      httpClient: MockClient(
        (_) async => serverAnswers
            ? http.Response.bytes(png, 200)
            : http.Response('', 404),
      ),
    );

    final app = ProviderScope(
      overrides: [
        artworkCacheProvider.overrideWithValue(cache),
        plexClientProvider.overrideWith(
          (ref) => PlexClient(
            server: server,
            identity: PlexIdentity.forTesting(),
            httpClient: MockClient((_) async => http.Response('', 200)),
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(body: Artwork(thumb: thumb)),
      ),
    );

    // Loading an image here does real work off the fake clock — a file write, a
    // file read, and a decode on the engine. `pumpAndSettle` drives timers and
    // animations, not those, so without `runAsync` the frame never arrives and
    // the test only ever sees the placeholder.
    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  testWidgets('a fetched image replaces the placeholder', (tester) async {
    await pump(
      tester,
      thumb: '/library/metadata/41/thumb/1',
      serverAnswers: true,
    );

    // The placeholder is an icon on a coloured box; once a frame arrives the
    // Image paints instead. Still seeing the icon means the codec never
    // completed, which is the failure mode a unit test cannot reach.
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('an image the server will not give up shows the placeholder', (
    tester,
  ) async {
    await pump(
      tester,
      thumb: '/library/metadata/41/thumb/1',
      serverAnswers: false,
    );

    // Not a broken-image glyph: the same placeholder as an album with no
    // artwork at all, which is the consistency this widget exists for.
    expect(find.byIcon(Icons.album), findsOneWidget);
  });

  testWidgets('an album with no artwork never asks the network', (
    tester,
  ) async {
    await pump(tester, thumb: null, serverAnswers: true);

    expect(find.byIcon(Icons.album), findsOneWidget);
    expect(directory.listSync(), isEmpty);
  });
}
