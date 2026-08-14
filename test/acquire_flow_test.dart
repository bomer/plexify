import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/acquire/acquire_queue.dart';
import 'package:plexify/core/acquire/download_source.dart';
import 'package:plexify/core/catalog/catalog_models.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/core/qbit/qbit_client.dart';
import 'package:plexify/core/slskd/slskd_client.dart';
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
    // A real search takes fifteen to twenty-five seconds. A fake that answers
    // instantly cannot show whether the acknowledgement arrives *before* the
    // work, which is the entire behaviour that changed.
    Duration delay = Duration.zero,
  }) {
    final added = <String>[];
    final client = QbitClient(
      baseUrl: 'https://box.local:8080',
      username: 'james',
      password: 'hunter2',
      httpClient: MockClient((request) async {
        await Future<void>.delayed(delay);
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
  late ProviderContainer container;

  Widget host(QbitClient client) {
    container = ProviderContainer(
      overrides: [
        qbitClientProvider.overrideWith((ref) async => client),
        // Pinned, because the flow asks which source is chosen before it does
        // anything, and that answer normally comes from persisted settings.
        downloadSourceKindProvider.overrideWithValue(
          DownloadSourceKind.qbittorrent,
        ),
      ],
    );
    addTearDown(container.dispose);

    return UncontrolledProviderScope(
      container: container,
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
  }

  /// The queue's view of one album, once the background search has finished.
  ///
  /// Tapping Get no longer waits for anything, so the outcome is no longer on
  /// screen: it is a row on the Downloads screen and a request in the queue.
  /// This is where the assertions moved to.
  Future<AcquireRequest> settledRequest(WidgetTester tester) async {
    final queue = container.read(acquireQueueProvider);
    for (var i = 0; i < 60; i++) {
      if (!queue.isBusy && queue.requests.isNotEmpty && queue.pending == 0) {
        return queue.requests.single;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('the queue never settled: ${queue.requests.map((r) => r.stage)}');
  }

  /// Opens the pushed page and returns once it is on screen.
  Future<void> openArtist(WidgetTester tester) async {
    await tester.tap(find.text('Open artist'));
    await tester.pumpAndSettle();
    expect(find.byType(_ArtistPage), findsOneWidget);
  }

  testWidgets('one tap says so at once, and the search happens after', (
    tester,
  ) async {
    // Any non-zero delay is enough: `pump()` with no duration advances no fake
    // time at all, so a server that is not instant is all this needs.
    final fake = fakeServer(delay: const Duration(milliseconds: 50));
    await tester.pumpWidget(host(fake.client));
    await openArtist(tester);

    await tester.tap(find.text('Get'));
    // **One frame, not one search.** Tapping used to block for the fifteen to
    // twenty-five seconds a search takes; the acknowledgement now has to be on
    // screen before any of that has happened, which is only observable against
    // a server that does not answer instantly.
    await tester.pump();

    expect(find.textContaining('Looking for'), findsOneWidget);
    expect(fake.added, isEmpty, reason: 'the search has not run yet');

    final request = await settledRequest(tester);
    expect(request.stage, AcquireStage.handedOver);
    expect(fake.added, ['magnet:?xt=urn:btih:deadbeef']);

    // **Still on the page you pressed the button from.** The original bug here
    // dismissed a dialog through the wrong navigator and took the artist page
    // with it, leaving a spinner over the page underneath.
    expect(find.byType(_ArtistPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a second tap replaces the message rather than queueing one', (
    tester,
  ) async {
    // The reported symptom: snackbars queue, so four taps left four banners
    // playing out one after another long after their searches had finished.
    final fake = fakeServer();
    await tester.pumpWidget(host(fake.client));
    await openArtist(tester);

    await tester.tap(find.text('Get'));
    await tester.pump();
    await tester.tap(find.text('Get'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    // And the same album twice is one request, so the second tap says so.
    expect(find.textContaining('already on the list'), findsOneWidget);

    // Let the background search finish. It is still running at this point,
    // which is the entire change: the assertions above did not wait for it, and
    // leaving it in flight would end the test with a pending timer.
    await settledRequest(tester);
  });

  testWidgets('a search that finds nothing is recorded, not lost', (
    tester,
  ) async {
    final fake = fakeServer(results: const []);
    await tester.pumpWidget(host(fake.client));
    await openArtist(tester);

    await tester.tap(find.text('Get'));
    final request = await settledRequest(tester);

    // An ordinary outcome, and it now survives on the Downloads screen instead
    // of being a snackbar that has gone by the time you look up.
    expect(request.stage, AcquireStage.notFound);
    expect(request.detail, contains('Nobody has it'));
    expect(find.byType(_ArtistPage), findsOneWidget);
  });

  testWidgets('a qBittorrent that never answers fails, and says why', (
    tester,
  ) async {
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
    final request = await settledRequest(tester);

    // Without a timeout on the client this never resolves at all and the
    // request sits searching for the life of the app.
    expect(request.stage, AcquireStage.failed);
    expect(request.detail, isNotNull);
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
    final request = await settledRequest(tester);

    expect(fake.added, isEmpty);
    expect(request.stage, AcquireStage.notFound);
    // Says what to do about it, since the results exist and one of them may
    // well be right.
    expect(request.detail, contains('long press'));
  });

  testWidgets('missing search plugins are named, not silently empty', (
    tester,
  ) async {
    final fake = fakeServer(plugins: false);
    await tester.pumpWidget(host(fake.client));
    await openArtist(tester);

    await tester.tap(find.text('Get'));
    final request = await settledRequest(tester);

    // With no plugins the search endpoints answer 200 and return nothing, which
    // reads as "nobody is seeding this" for every album ever asked for.
    expect(fake.added, isEmpty);
    expect(request.stage, AcquireStage.failed);
    expect(request.detail, contains('search plugins'));
  });

  group('the same screen, the other source', () {
    /// An slskd sharing one folder that names the record.
    ({SlskdClient client, List<String> enqueued}) fakeSlskd({
      String directory = r'@@abc\Music\Radiohead\OK Computer',
      bool loggedIn = true,
      int trackCount = 12,
    }) {
      final enqueued = <String>[];
      final client = SlskdClient(
        baseUrl: 'https://nas.local:5031',
        apiKey: 'k3y',
        httpClient: MockClient((request) async {
          final path = request.url.path;

          if (path.endsWith('/application')) {
            return http.Response(
              jsonEncode({
                'version': {'full': '0.22.3'},
                'server': {'isConnected': true, 'isLoggedIn': loggedIn},
              }),
              200,
            );
          }
          if (path.endsWith('/responses')) {
            return http.Response(
              jsonEncode([
                {
                  'username': 'peer',
                  'hasFreeUploadSlot': true,
                  'uploadSpeed': 900000,
                  'queueLength': 0,
                  'files': [
                    for (var i = 1; i <= trackCount; i++)
                      {
                        'filename': '$directory\\0$i Track.flac',
                        'size': 30000000,
                        'extension': 'flac',
                      },
                  ],
                },
              ]),
              200,
            );
          }
          if (request.method == 'GET' && path.contains('/searches/')) {
            // Finished on the first poll, so nothing waits out an interval.
            return http.Response(
              jsonEncode({'id': 'x', 'state': 'Completed, TimedOut'}),
              200,
            );
          }
          if (path.contains('/transfers/downloads/')) {
            enqueued.add(request.body);
            return http.Response('', 200);
          }
          return http.Response('{}', 200);
        }),
      );
      return (client: client, enqueued: enqueued);
    }

    Widget slskdHost(SlskdClient client) {
      container = ProviderContainer(
        overrides: [
          slskdClientProvider.overrideWith((ref) async => client),
          downloadSourceKindProvider.overrideWithValue(
            DownloadSourceKind.soulseek,
          ),
        ],
      );
      addTearDown(container.dispose);

      return UncontrolledProviderScope(
        container: container,
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
    }

    testWidgets('the whole folder from one peer is queued', (tester) async {
      // **The point of the seam.** Not one line of the button, the queue or the
      // Downloads screen was written twice, and this is the proof: the same
      // page, a completely different server behind it.
      final fake = fakeSlskd();
      await tester.pumpWidget(slskdHost(fake.client));
      await openArtist(tester);

      await tester.tap(find.text('Get'));
      final request = await settledRequest(tester);

      expect(request.stage, AcquireStage.handedOver);
      expect(fake.enqueued, hasLength(1));
      // All twelve tracks in one request. Half a record in the folder Plex
      // watches is worse than nothing there: it scans, looks complete, and the
      // gaps are only found on playing it.
      expect(jsonDecode(fake.enqueued.single), hasLength(12));
      expect(find.byType(_ArtistPage), findsOneWidget);
    });

    testWidgets('a folder that does not name the album is never queued', (
      tester,
    ) async {
      final fake = fakeSlskd(directory: r'@@abc\Music\Various\Computer Love');
      await tester.pumpWidget(slskdHost(fake.client));
      await openArtist(tester);

      await tester.tap(find.text('Get'));
      final request = await settledRequest(tester);

      expect(fake.enqueued, isEmpty);
      expect(request.stage, AcquireStage.notFound);
    });

    testWidgets('an slskd logged out of Soulseek is named, not silently empty', (
      tester,
    ) async {
      // The exact counterpart of missing search plugins, and just as invisible:
      // every request answers perfectly and every search finds nothing, which
      // reads as "nobody has this" for every album forever.
      final fake = fakeSlskd(loggedIn: false);
      await tester.pumpWidget(slskdHost(fake.client));
      await openArtist(tester);

      await tester.tap(find.text('Get'));
      final request = await settledRequest(tester);

      expect(fake.enqueued, isEmpty);
      expect(request.stage, AcquireStage.failed);
      expect(request.detail, contains('not logged in to Soulseek'));
    });
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
