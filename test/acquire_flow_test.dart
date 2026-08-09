import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/catalog/catalog_models.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/core/qbit/qbit_client.dart';
import 'package:plexify/features/acquire/download_sheet.dart';

/// The one-click path, end to end through the widget layer.
///
/// This exists because the searching dialog hid a bug that no unit test could
/// reach and that made the whole feature do nothing: closing the dialog
/// ourselves completed its future, which set the same flag a user dismissal
/// sets, so the result was discarded every time. The button searched, found the
/// album, added nothing and said nothing.
///
/// **Nothing here calls `pumpAndSettle` once a search is running.** The
/// progress message holds a `CircularProgressIndicator`, which never stops
/// animating, so settling waits out its full timeout and reports a hang rather
/// than a failure.
void main() {
  /// A qBittorrent that answers everything the flow asks, in one shot.
  ({QbitClient client, List<String> added}) fakeServer({
    String fileName = 'Radiohead - OK Computer (1997) [FLAC]',
    bool plugins = true,
    List<Map<String, Object?>>? results,
  }) {
    final added = <String>[];
    final client = QbitClient(
      baseUrl: 'https://box.local:8080',
      username: 'james',
      password: 'hunter2',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/login')) {
          return http.Response(
            'Ok.',
            200,
            headers: const {'set-cookie': 'SID=abc'},
          );
        }
        if (path.endsWith('/search/plugins')) {
          return http.Response(
            jsonEncode([
              {'name': 'jackett', 'enabled': plugins},
            ]),
            200,
          );
        }
        if (path.endsWith('/search/start')) {
          return http.Response(jsonEncode({'id': 1}), 200);
        }
        if (path.endsWith('/search/results')) {
          return http.Response(
            jsonEncode({
              // Stopped on the first poll, so the flow never waits out a poll
              // interval and the test needs no timer pumping.
              'status': 'Stopped',
              'results':
                  results ??
                  [
                    {
                      'fileName': fileName,
                      'fileUrl': 'magnet:?xt=urn:btih:deadbeef',
                      'fileSize': 400000000,
                      'nbSeeders': 40,
                      'nbLeechers': 2,
                    },
                  ],
            }),
            200,
          );
        }
        if (path.endsWith('/torrents/add')) {
          added.add(Uri.splitQueryString(request.body)['urls']!);
          return http.Response('Ok.', 200);
        }
        return http.Response('{}', 200);
      }),
    );
    return (client: client, added: added);
  }

  /// The shell's shape, reduced to what matters here: a page pushed inside a
  /// **nested** navigator, the way every screen in this app lives.
  ///
  /// Not a convenience. The bug this guards against was a `Navigator.of` that
  /// resolved the nested navigator while the thing it meant to close had been
  /// pushed on the root one, so the pop took the page instead — you pressed
  /// download on an artist and landed back on the album you came from. A flat
  /// `MaterialApp` cannot express that at all, and the original test used one.
  Widget host(QbitClient client) => ProviderScope(
    overrides: [qbitClientProvider.overrideWith((ref) async => client)],
    child: MaterialApp(
      home: Scaffold(
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const _ArtistPage()),
              ),
              child: const Text('Open artist'),
            ),
          ),
        ),
      ),
    ),
  );

  /// Opens the pushed page and returns once it is on screen.
  Future<void> openArtist(WidgetTester tester) async {
    await tester.tap(find.text('Open artist'));
    await tester.pumpAndSettle();
    expect(find.byType(_ArtistPage), findsOneWidget);
  }

  /// Advances far enough for the HTTP futures and the dialog transition to
  /// finish, without ever waiting for an animation that does not end.
  Future<void> settleWithoutSpinner(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('one click queues the album and says which one', (tester) async {
    final fake = fakeServer();
    await tester.pumpWidget(host(fake.client));
    await openArtist(tester);

    await tester.tap(find.text('Get'));
    await settleWithoutSpinner(tester);

    // The whole point. Before the dialog fix this list was empty and the
    // snackbar never appeared, with no error anywhere to say why.
    expect(fake.added, ['magnet:?xt=urn:btih:deadbeef']);
    expect(find.textContaining('Queued'), findsOneWidget);

    // **Still on the page you pressed the button from.** Searching must not
    // navigate anywhere: the old dialog was dismissed through the wrong
    // navigator and took the artist page with it, leaving a spinner that never
    // went away over the page underneath.
    expect(find.byType(_ArtistPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    // And nothing is still claiming to be searching.
    expect(find.textContaining('Searching'), findsNothing);
  });

  testWidgets('a search that finds nothing says so', (tester) async {
    final fake = fakeServer(results: const []);
    await tester.pumpWidget(host(fake.client));
    await openArtist(tester);

    await tester.tap(find.text('Get'));
    await settleWithoutSpinner(tester);

    // An ordinary outcome — the plugins have nothing, or the record is obscure
    // — and silence after a twenty-second wait is indistinguishable from the
    // app having given up.
    expect(find.textContaining('No downloads found'), findsOneWidget);
    expect(find.byType(_ArtistPage), findsOneWidget);
  });

  testWidgets('a qBittorrent that never answers does not hang', (tester) async {
    final client = QbitClient(
      baseUrl: 'https://box.local:8080',
      username: 'james',
      password: 'hunter2',
      // Never responds, which is what an address that is not there does. It is
      // not refused and it is not an error; it is silence.
      httpClient: MockClient((_) => Completer<http.Response>().future),
      requestTimeout: const Duration(milliseconds: 20),
    );

    await tester.pumpWidget(host(client));
    await openArtist(tester);

    await tester.tap(find.text('Get'));
    await settleWithoutSpinner(tester);

    // Without a timeout on the client this never resolves and the progress
    // message stays on screen for the life of the app.
    expect(find.textContaining('Searching'), findsNothing);
    expect(find.byType(_ArtistPage), findsOneWidget);
  });

  testWidgets('a result that does not name the album is never queued', (
    tester,
  ) async {
    // Matches on one word and is enormously seeded. Torrent search returns
    // these constantly, and adding one puts a different record into the folder
    // Plex watches under this album's name.
    final fake = fakeServer(fileName: 'Various Artists - Computer Love');
    await tester.pumpWidget(host(fake.client));
    await openArtist(tester);

    await tester.tap(find.text('Get'));
    await settleWithoutSpinner(tester);

    expect(fake.added, isEmpty);
    // The list opens instead, so the choice is still one tap away.
    expect(find.textContaining('No result clearly names'), findsOneWidget);
  });

  testWidgets('missing search plugins are named, not silently empty', (
    tester,
  ) async {
    final fake = fakeServer(plugins: false);
    await tester.pumpWidget(host(fake.client));
    await openArtist(tester);

    await tester.tap(find.text('Get'));
    await settleWithoutSpinner(tester);

    // With no plugins the search endpoints answer 200 and return nothing, which
    // reads as "nobody is seeding this" for every album ever asked for.
    expect(fake.added, isEmpty);
    expect(find.textContaining('search plugins'), findsOneWidget);
  });
}

/// Stands in for the artist page — a route pushed inside the nested navigator,
/// carrying the button that starts a search.
class _ArtistPage extends ConsumerWidget {
  const _ArtistPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => acquire(
          context,
          ref,
          const CatalogRelease(
            mbid: 'mb-1',
            title: 'OK Computer',
            artist: 'Radiohead',
            year: 1997,
          ),
        ),
        child: const Text('Get'),
      ),
    ),
  );
}
