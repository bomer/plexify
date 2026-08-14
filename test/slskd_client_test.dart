import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/slskd/slskd_client.dart';
import 'package:plexify/core/slskd/slskd_models.dart';

/// slskd's API is far less treacherous than qBittorrent's, so what is guarded
/// here is different: not authentication traps, but the two things that would
/// quietly rot a server the user runs on their own NAS.
///
/// Searches persist until deleted, so a leaked one accumulates forever. And a
/// Soulseek search that ends `Completed, TimedOut` is the *ordinary successful*
/// ending rather than a failure, because peers answer whenever they like and
/// many never do. Reading that as an error would discard every search.
void main() {
  const base = 'https://nas.local:5031';

  ({http.Client client, List<http.BaseRequest> requests}) server({
    Object? Function(http.Request request)? json,
    int status = 200,
    String? body,
  }) {
    final requests = <http.BaseRequest>[];
    return (
      client: MockClient((request) async {
        requests.add(request);
        if (status != 200) return http.Response(body ?? '', status);
        return http.Response(
          body ?? jsonEncode(json?.call(request) ?? <String, Object?>{}),
          200,
        );
      }),
      requests: requests,
    );
  }

  SlskdClient build(http.Client client) =>
      SlskdClient(baseUrl: base, apiKey: 'k3y', httpClient: client);

  group('authorisation', () {
    test('the API key is sent on every request', () async {
      final fake = server();
      await build(fake.client).version();

      expect(fake.requests, isNotEmpty);
      for (final request in fake.requests) {
        expect(request.headers['X-API-Key'], 'k3y');
      }
    });

    test('401 and 403 are told apart, because the fixes differ', () async {
      final unauthorized = server(status: 401);
      await expectLater(
        build(unauthorized.client).version(),
        throwsA(
          isA<SlskdException>()
              .having((e) => e.unauthorized, 'unauthorized', isTrue)
              .having((e) => e.forbidden, 'forbidden', isFalse),
        ),
      );

      // The one that matters, and it has two causes that must both be named.
      //
      // A readonly key is the nastier one: keys configured in slskd.yml
      // default to it, and it searches perfectly while failing only on the
      // download, so it presents an hour later as an unrelated bug. The other
      // is a cidr that does not cover this device, which is invisible from the
      // machine the key was tested on.
      final forbidden = server(status: 403);
      await expectLater(
        build(forbidden.client).version(),
        throwsA(
          isA<SlskdException>()
              .having((e) => e.forbidden, 'forbidden', isTrue)
              .having((e) => e.message, 'names the role', contains('readwrite'))
              .having((e) => e.message, 'names the network', contains('cidr')),
        ),
      );
    });

    test('a trailing slash on the address does not double the path', () async {
      final fake = server();
      await SlskdClient(
        baseUrl: '$base/',
        apiKey: 'k3y',
        httpClient: fake.client,
      ).version();

      expect(fake.requests.single.url.path, '/api/v0/application');
    });
  });

  group('searching', () {
    /// A server that reports one poll in progress, then finished.
    ({http.Client client, List<http.BaseRequest> requests}) searching({
      String finalState = 'Completed, TimedOut',
      bool throwOnState = false,
    }) {
      var polls = 0;
      final requests = <http.BaseRequest>[];
      return (
        client: MockClient((request) async {
          requests.add(request);
          final path = request.url.path;

          if (path.endsWith('/responses')) {
            return http.Response(
              jsonEncode([
                {
                  'username': 'peer',
                  'hasFreeUploadSlot': true,
                  'uploadSpeed': 1000,
                  'queueLength': 0,
                  'files': [
                    {
                      'filename': r'@@music\Radiohead\Kid A\01 Everything.flac',
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
            if (throwOnState) return http.Response('nope', 500);
            polls++;
            return http.Response(
              jsonEncode({
                'id': 'x',
                'state': polls > 1 ? finalState : 'InProgress',
              }),
              200,
            );
          }

          return http.Response('{}', 200);
        }),
        requests: requests,
      );
    }

    test('a search is not finished just because it has not started', () async {
      // **The bug that made downloads fail intermittently, in one test.**
      //
      // slskd's states run Requested -> InProgress -> Completed, TimedOut, and
      // the first poll lands within milliseconds of the POST, while the state
      // is still Requested. Asking "is it complete" as `!contains(inprogress)`
      // answers *yes* to Requested, so the client read an empty response list
      // about 50ms in and reported nothing found, while slskd carried on and
      // filled the search in perfectly. That is why the search was sitting
      // complete in the web UI and downloaded fine by hand.
      //
      // The fake this file already had began at InProgress, so it never
      // modelled the moment the bug happens. Sixteen passing tests and a
      // client that could not finish a search.
      var polls = 0;
      final client = MockClient((request) async {
        final path = request.url.path;

        if (path.endsWith('/responses')) {
          // Empty until the search has actually run, which is the honest
          // behaviour: there is nothing to return yet.
          return http.Response(
            polls >= 3
                ? jsonEncode([
                    {
                      'username': 'peer',
                      'hasFreeUploadSlot': true,
                      'files': [
                        {
                          'filename': r'@@m\Radiohead\Kid A\01.flac',
                          'size': 1,
                          'extension': 'flac',
                        },
                      ],
                    },
                  ])
                : '[]',
            200,
          );
        }

        if (request.method == 'GET' && path.contains('/searches/')) {
          polls++;
          return http.Response(
            jsonEncode({
              'id': 'x',
              'state': switch (polls) {
                1 => 'Requested',
                2 => 'InProgress',
                _ => 'Completed, TimedOut',
              },
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final responses = await build(
        client,
      ).search('radiohead kid a', pollInterval: Duration.zero);

      expect(
        responses,
        hasLength(1),
        reason: 'gave up before the search had begun',
      );
      expect(polls, greaterThanOrEqualTo(3));
    });

    test('the search id is a GUID, because slskd parses it as one', () async {
      // Measured, not assumed. The first live search against James's server
      // answered 400 with a .NET type name:
      //
      //   The JSON value could not be converted to
      //   System.Nullable`1[System.Guid]. Path: $.id
      //
      // Nothing in the API documentation says the id has to be a GUID, and the
      // fake server here was happy to accept `plexify-1755043200123-7`, which
      // is exactly why this assertion is on the shape rather than on the call
      // succeeding.
      final fake = searching();
      await build(fake.client).search('anything', pollInterval: Duration.zero);

      final started = fake.requests.firstWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/searches'),
      );
      final id = (jsonDecode((started as http.Request).body) as Map)['id'];

      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ),
        ),
        reason: 'slskd rejects anything that is not a GUID with a 400',
      );
    });

    test("the server's own id is what gets polled", () async {
      // Ours is only a fallback. The thing being polled should be named by
      // whoever owns it, in case slskd ever decides to allocate its own.
      final requests = <http.BaseRequest>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST' && request.url.path.endsWith('/searches')) {
          return http.Response(
            jsonEncode({'id': '11111111-2222-3333-4444-555555555555'}),
            200,
          );
        }
        if (request.url.path.endsWith('/responses')) {
          return http.Response('[]', 200);
        }
        return http.Response(
          jsonEncode({'id': 'x', 'state': 'Completed, TimedOut'}),
          200,
        );
      });

      await build(client).search('anything', pollInterval: Duration.zero);

      expect(
        requests.any(
          (r) =>
              r.method == 'GET' &&
              r.url.path.contains('11111111-2222-3333-4444-555555555555'),
        ),
        isTrue,
      );
    });

    test('a timed-out search is a success, not a failure', () async {
      // The ordinary ending. A Soulseek search has no natural end, so slskd
      // stops waiting and keeps what arrived.
      final fake = searching();
      final responses = await build(fake.client).search(
        'radiohead kid a',
        pollInterval: Duration.zero,
      );

      expect(responses, hasLength(1));
      expect(responses.single.files.single.suffix, 'flac');
    });

    test('the search is left on the server, unlike qBittorrent', () async {
      final fake = searching();

      await build(fake.client).search('anything', pollInterval: Duration.zero);

      // **The opposite of what this asserted at first.** qBittorrent caps how
      // many searches it keeps, so leaking them breaks searching after a few
      // dozen. slskd has no cap, and its search history is where you go when
      // this app has not done what you wanted: downloading from it by hand is
      // a working fallback, and deleting it takes that away.
      expect(fake.requests.where((r) => r.method == 'DELETE'), isEmpty);
    });

    test('a failure on the way is reported rather than swallowed', () async {
      final fake = searching(throwOnState: true);

      await expectLater(
        build(fake.client).search('anything', pollInterval: Duration.zero),
        throwsA(isA<SlskdException>()),
      );
    });

    test('a search that never finishes keeps what arrived anyway', () async {
      // A peer that answered is a peer that answered, whether or not slskd ever
      // got round to declaring the search over. Returning nothing here would
      // throw away a perfectly good result because of a state string.
      var polls = 0;
      final fake = MockClient((request) async {
        if (request.url.path.endsWith('/responses')) {
          return http.Response(
            jsonEncode([
              {
                'username': 'slow-peer',
                'files': [
                  {
                    'filename': r'@@m\Radiohead\Kid A\01.flac',
                    'size': 1,
                    'extension': 'flac',
                  },
                ],
              },
            ]),
            200,
          );
        }
        if (request.method == 'GET' && request.url.path.contains('/searches/')) {
          polls++;
          return http.Response(
            jsonEncode({'id': 'x', 'state': 'InProgress'}),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final responses = await build(fake).search(
        'never',
        timeout: const Duration(milliseconds: 30),
        pollInterval: Duration.zero,
      );

      expect(responses, hasLength(1));
      expect(polls, greaterThan(0), reason: 'it should have polled at all');
    });
  });

  group('queueing', () {
    test("a whole folder goes in one request, with the peer's own paths", () async {
      final fake = server();
      const files = [
        SlskdFile(filename: r'@@x\Kid A\01 Everything.flac', size: 1),
        SlskdFile(filename: r'@@x\Kid A\02 Kid A.flac', size: 2),
      ];

      await build(fake.client).enqueue('peer', files);

      final request = fake.requests.single as http.Request;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v0/transfers/downloads/peer');

      // Verbatim. The path belongs to the peer's machine, and normalising the
      // separators here would produce something they cannot resolve.
      final sent = jsonDecode(request.body) as List;
      expect(sent, hasLength(2));
      expect(sent.first, {
        'filename': r'@@x\Kid A\01 Everything.flac',
        'size': 1,
      });
    });

    test('a username with a space survives the URL', () async {
      final fake = server();
      await build(
        fake.client,
      ).enqueue('some one', const [SlskdFile(filename: 'a.flac', size: 1)]);

      // Asserted on the decoded segment rather than the raw path: the wire form
      // is percent-encoded, and what matters is that slskd resolves it back to
      // the name the peer actually goes by.
      expect(fake.requests.single.url.pathSegments.last, 'some one');
    });

    test('enqueueing nothing makes no request at all', () async {
      final fake = server();
      await build(fake.client).enqueue('peer', const []);
      expect(fake.requests, isEmpty);
    });

    test('an empty 200 body is success, not a decode failure', () async {
      // Several endpoints answer with no body. jsonDecode('') throws, which
      // would turn every successful enqueue into an error.
      final fake = server(body: '');
      await expectLater(
        build(
          fake.client,
        ).enqueue('peer', const [SlskdFile(filename: 'a.flac', size: 1)]),
        completes,
      );
    });
  });

  group('downloads', () {
    test('files are grouped into folders, which is what a record is', () async {
      final fake = server(
        json: (_) => [
          {
            'username': 'peer',
            'directories': [
              {
                'directory': r'@@x\Radiohead\Kid A',
                'files': [
                  {
                    'filename': r'@@x\Radiohead\Kid A\01.flac',
                    'state': 'Completed, Succeeded',
                    'size': 100,
                    'bytesTransferred': 100,
                  },
                  {
                    'filename': r'@@x\Radiohead\Kid A\02.flac',
                    'state': 'InProgress',
                    'size': 100,
                    'bytesTransferred': 50,
                  },
                ],
              },
            ],
          },
        ],
      );

      final downloads = await build(fake.client).downloads();

      expect(downloads, hasLength(1));
      final job = downloads.single;
      expect(job.name, 'Kid A');
      expect(job.username, 'peer');
      expect(job.progress, closeTo(0.75, 0.001));

      // Not complete on the first file. Asking Plex to rescan a half-written
      // album is how a broken record gets into the library.
      expect(job.isComplete, isFalse);
    });
  });

  group('reachability', () {
    test('a server whose Soulseek connection is down is reported as such', () async {
      // This one is worth its own call. slskd's API answers perfectly while it
      // is logged out of Soulseek, so a server that can find nothing at all
      // looks identical to a healthy one until the first search comes back
      // empty.
      final connected = server(
        json: (_) => {
          'version': {'full': '0.22.3'},
          'server': {'isConnected': true, 'isLoggedIn': true},
        },
      );
      expect(await build(connected.client).isConnectedToSoulseek(), isTrue);

      final loggedOut = server(
        json: (_) => {
          'version': {'full': '0.22.3'},
          'server': {'isConnected': true, 'isLoggedIn': false},
        },
      );
      expect(await build(loggedOut.client).isConnectedToSoulseek(), isFalse);
    });

    test('the version is read for the Save and test button', () async {
      final fake = server(
        json: (_) => {
          'version': {'full': '0.22.3'},
        },
      );
      expect(await build(fake.client).version(), '0.22.3');
    });

    test('an unreachable server names the address rather than the exception', () async {
      final fake = MockClient((_) async => throw const SocketishFailure());
      await expectLater(
        build(fake).version(),
        throwsA(
          isA<SlskdException>().having(
            (e) => e.message,
            'message',
            contains(base),
          ),
        ),
      );
    });
  });
}

/// Stands in for a connection failure without dragging `dart:io` into a test
/// that otherwise runs anywhere.
class SocketishFailure implements Exception {
  const SocketishFailure();
  @override
  String toString() => 'Connection refused';
}
