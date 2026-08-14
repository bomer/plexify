import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/catalog/catalog_models.dart';
import 'package:plexify/core/catalog/listenbrainz_client.dart';
import 'package:plexify/core/providers.dart' show popularityKey;
import 'package:plexify/core/settings/app_settings.dart';
import 'package:plexify/features/acquire/catalog_release_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which of an artist's fifteen albums are the ones people actually love.
///
/// The load-bearing decision is that the bar is drawn **relative to the biggest
/// record in the same discography**, never on an absolute scale. Fifty thousand
/// listens is a monstrous hit for an obscure producer and a rounding error for
/// Radiohead, so a global scale would draw every page for a small artist as
/// uniformly empty and every page for a large one as uniformly full, which
/// answers a question nobody asked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsStore settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsStore(await SharedPreferences.getInstance());
  });

  ListenBrainzClient clientReturning(
    Object? body, {
    int status = 200,
    List<String>? capture,
  }) => ListenBrainzClient(
    httpClient: MockClient((request) async {
      if (capture != null) capture.add(request.body);
      return http.Response(
        body is String ? body : jsonEncode(body),
        status,
      );
    }),
  );

  group('reading listen counts', () {
    test('a whole discography is one request', () async {
      // The reason this endpoint was chosen over the per-artist one: it takes
      // exactly the ids already on screen.
      final sent = <String>[];
      final client = clientReturning([
        {'release_group_mbid': 'a', 'total_listen_count': 10},
      ], capture: sent);

      await client.popularityFor(['a', 'b', 'c']);

      expect(sent, hasLength(1));
      expect(
        (jsonDecode(sent.single) as Map)['release_group_mbids'],
        containsAll(['a', 'b', 'c']),
      );
    });

    test('an id nobody answered for is absent, not zero', () async {
      // "Nobody has heard it" and "we were not told" are different claims, and
      // only one of them should draw an empty bar.
      final client = clientReturning([
        {'release_group_mbid': 'a', 'total_listen_count': 10},
      ]);

      final result = await client.popularityFor(['a', 'b']);

      expect(result.containsKey('a'), isTrue);
      expect(result.containsKey('b'), isFalse);
    });

    test('a failure is an empty map, never an exception', () async {
      // Popularity is decoration on pages that already work. The rule the whole
      // catalog tier is built under is that the lower tier must never be able
      // to make the upper one worse.
      final broken = clientReturning('nonsense', status: 500);
      expect(await broken.popularityFor(['a']), isEmpty);

      final garbage = clientReturning('not json at all');
      expect(await garbage.popularityFor(['a']), isEmpty);

      final thrown = ListenBrainzClient(
        httpClient: MockClient((_) async => throw Exception('offline')),
      );
      expect(await thrown.popularityFor(['a']), isEmpty);
    });

    test('asking about nothing makes no request', () async {
      final sent = <String>[];
      final client = clientReturning([], capture: sent);

      expect(await client.popularityFor(const []), isEmpty);
      expect(await client.popularityFor(['', '  ']), isEmpty);
      expect(sent, isEmpty);
    });

    test('listeners are kept apart from listens', () async {
      // A thousand plays by four people is a different fact from a thousand
      // plays by four hundred.
      final client = clientReturning([
        {
          'release_group_mbid': 'a',
          'total_listen_count': 1000,
          'total_user_count': 4,
        },
      ]);

      final result = await client.popularityFor(['a']);
      expect(result['a']!.listens, 1000);
      expect(result['a']!.listeners, 4);
    });
  });

  test('the same set of records is the same cache key', () {
    // **The trap this exists for.** The obvious family key is a record holding
    // the list of ids, and it silently never terminates: records compare their
    // fields with `==`, and `List.==` is *identity*, so a list rebuilt during
    // `build` is a new key every frame. New key, new provider, new request,
    // another rebuild, forever. It showed up as a discography that never
    // settled and a request every frame at somebody else's service.
    //
    // Caught here as well as by the widget tests, because those catch it only
    // as a timeout, which names nothing.
    final first = [
      const CatalogRelease(mbid: 'a', title: 'One', artist: 'X'),
      const CatalogRelease(mbid: 'b', title: 'Two', artist: 'X'),
    ];
    final second = [
      const CatalogRelease(mbid: 'a', title: 'One', artist: 'X'),
      const CatalogRelease(mbid: 'b', title: 'Two', artist: 'X'),
    ];

    expect(popularityKey(first), popularityKey(second));
    expect(identical(first, second), isFalse, reason: 'different lists');

    // And a different set is genuinely a different key.
    expect(
      popularityKey(first),
      isNot(popularityKey([first.first])),
    );
  });

  group('what a card draws', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      ReleasePopularity? popularity,
      int? peak,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsStoreProvider.overrideWithValue(settings)],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 300,
                child: CatalogReleaseCard(
                  release: const CatalogRelease(
                    mbid: 'a',
                    title: 'Geogaddi',
                    artist: 'Boards of Canada',
                    year: 2002,
                  ),
                  popularity: popularity,
                  peakListens: peak,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the biggest record in its own row fills the bar', (
      tester,
    ) async {
      // **The whole point.** An artist whose largest record has four thousand
      // listens still shows a full bar for it. On an absolute scale this would
      // be a sliver, and the page would say "this artist is small" instead of
      // "this is their best-loved record", which is not the question.
      await pumpCard(
        tester,
        popularity: const ReleasePopularity(listens: 4000, listeners: 300),
        peak: 4000,
      );

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 1.0);
      expect(find.textContaining('4.0k plays'), findsOneWidget);
    });

    testWidgets('a lesser record shows its share of the biggest', (
      tester,
    ) async {
      await pumpCard(
        tester,
        popularity: const ReleasePopularity(listens: 1000, listeners: 90),
        peak: 4000,
      );

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.25, 0.001));
    });

    testWidgets('a discography nobody listens to draws no bars at all', (
      tester,
    ) async {
      // Not a row of empty ones. An empty bar is a claim that nobody listens to
      // this; no bar correctly says nothing. Dividing by a zero peak is the
      // obvious way to get that backwards.
      await pumpCard(
        tester,
        popularity: const ReleasePopularity(listens: 0, listeners: 0),
        peak: 0,
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('plays'), findsNothing);
    });

    testWidgets('no popularity at all renders as it did before', (tester) async {
      // A ListenBrainz failure must leave the page exactly as it was.
      await pumpCard(tester);

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Geogaddi'), findsOneWidget);
      expect(find.textContaining('2002'), findsOneWidget);
    });
  });
}
