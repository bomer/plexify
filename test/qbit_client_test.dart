import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/qbit/qbit_client.dart';
import 'package:plexify/core/qbit/qbit_models.dart';

/// qBittorrent answers **403** for three unrelated situations — a failed CSRF
/// check, an expired session, and an IP banned for repeated failed logins — and
/// the natural response to the first two is exactly what makes the third worse.
///
/// Most of what follows guards that, because the failure mode is a phone banned
/// by a server its owner runs, and the symptom is a 403 against a WebUI that
/// works perfectly in a browser.
void main() {
  const base = 'https://box.local:8080';

  /// A fake server that behaves the way qBittorrent actually does: a session
  /// cookie, `Ok.` bodies, and JSON everywhere else.
  ({http.Client client, List<http.BaseRequest> requests}) server({
    int loginStatus = 200,
    String loginBody = 'Ok.',
    Map<String, Object?> Function(http.Request request)? json,
  }) {
    final requests = <http.BaseRequest>[];
    return (
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            loginBody,
            loginStatus,
            headers: const {
              'set-cookie': 'SID=abc123; path=/; HttpOnly; Expires=Mon, 01 Jan',
            },
          );
        }
        if (request.url.path.endsWith('/app/version')) {
          return http.Response('v5.0.3', 200);
        }
        if (request.url.path.endsWith('/torrents/add')) {
          return http.Response('Ok.', 200);
        }
        return http.Response(
          jsonEncode(json?.call(request) ?? <String, Object?>{}),
          200,
        );
      }),
      requests: requests,
    );
  }

  QbitClient build(http.Client client, {String url = base}) => QbitClient(
    baseUrl: url,
    username: 'james',
    password: 'hunter2',
    httpClient: client,
  );

  test('the CSRF headers match the configured address exactly', () async {
    final fake = server();
    await build(fake.client).login();

    // qBittorrent compares Referer and Origin against Host *including the
    // port*. Getting this wrong is the single most common cause of a 403
    // against a server that is working, and it says nothing about which header
    // it disliked.
    final login = fake.requests.single;
    expect(login.headers['Referer'], base);
    expect(login.headers['Origin'], base);
  });

  test('a trailing slash is trimmed off the address', () async {
    final fake = server();
    await build(fake.client, url: '$base/').login();

    // Left on, every path becomes double-slashed and the Referer stops
    // matching — so this presents as a wrong password rather than as a typo.
    expect(fake.requests.single.url.toString(), '$base/api/v2/auth/login');
    expect(fake.requests.single.headers['Referer'], base);
  });

  test('a rejected password is a 200 with the body Fails.', () async {
    final fake = server(loginBody: 'Fails.');

    // Reading the status alone would treat this as a successful sign-in, and
    // every request after it would then 403 for what looks like a different
    // reason entirely.
    await expectLater(
      build(fake.client).login(),
      throwsA(
        isA<QbitException>().having(
          (e) => e.message,
          'message',
          contains('rejected the username or password'),
        ),
      ),
    );
  });

  test('a 403 on sign-in latches and refuses to try again', () async {
    final fake = server(loginStatus: 403);
    final client = build(fake.client);

    await expectLater(
      client.login(),
      throwsA(isA<QbitException>().having((e) => e.banned, 'banned', isTrue)),
    );
    expect(client.lockedOut, isTrue);

    await expectLater(client.login(), throwsA(isA<QbitException>()));

    // One request, not two. The client cannot tell a ban from a wrong password,
    // and guessing again is the one action that makes either worse — on a
    // server the user runs themselves.
    expect(fake.requests, hasLength(1));
  });

  test('the session cookie survives qBittorrent comma-laden headers', () async {
    final fake = server(json: (_) => {});
    final client = build(fake.client);
    await client.version();

    // `package:http` collapses Set-Cookie headers into one comma-separated
    // string, and cookie attributes contain their own commas (Expires=Mon, 01
    // Jan). Splitting on commas loses the value; scanning for the name does
    // not.
    expect(fake.requests.last.headers['Cookie'], 'SID=abc123');
  });

  test('adding a torrent files it under Music', () async {
    final fake = server();
    await build(fake.client).addTorrent('magnet:?xt=urn:btih:deadbeef');

    final add = fake.requests.last as http.Request;
    final body = Uri.splitQueryString(add.body);
    // The category *is* the integration: James's existing automation routes it
    // to the folder Plex watches, which is what makes this one step rather than
    // three. Nothing here renames or retags.
    expect(body['category'], 'Music');
    expect(body['urls'], 'magnet:?xt=urn:btih:deadbeef');
  });

  test('a search runs to completion and is always deleted', () async {
    var polls = 0;
    final fake = server(
      json: (request) {
        final path = request.url.path;
        if (path.endsWith('/search/start')) return {'id': 7};
        if (path.endsWith('/search/results')) {
          polls++;
          return {
            'status': polls >= 2 ? 'Stopped' : 'Running',
            'results': [
              {
                'fileName': 'Radiohead - OK Computer [FLAC]',
                'fileUrl': 'magnet:?xt=1',
                'fileSize': 400000000,
                'nbSeeders': 12,
                'nbLeechers': 3,
              },
            ],
          };
        }
        return {};
      },
    );

    final results = await build(
      fake.client,
    ).search('radiohead ok computer', pollInterval: Duration.zero);

    expect(results, hasLength(1));
    expect(results.single.seeders, 12);

    // qBittorrent keeps finished searches until they are removed and caps how
    // many may exist. Leak them and searching stops working after a few dozen
    // attempts, with an error that names nothing relevant.
    final paths = fake.requests.map((r) => r.url.path).toList();
    expect(paths.any((p) => p.endsWith('/search/delete')), isTrue);
  });

  test('no search plugins is reported, not mistaken for no results', () async {
    final fake = server(
      json: (request) => request.url.path.endsWith('/search/plugins') ? {} : {},
    );

    // With no plugins the search endpoints answer happily and return nothing,
    // which reads as "nobody is seeding this" for every album ever asked for.
    expect(await build(fake.client).hasSearchPlugins(), isFalse);
  });

  test('a completed torrent is recognised however it is phrased', () {
    // qBittorrent's state vocabulary grows between releases, and all of the
    // upload-side states mean the data is on disk — which is the only thing
    // this app cares about, since it never seeds anything itself.
    for (final state in ['uploading', 'stalledUP', 'pausedUP', 'forcedUP']) {
      final torrent = QbitTorrent.fromJson({
        'hash': 'h',
        'name': 'n',
        'progress': 1.0,
        'state': state,
        'size': 1,
        'category': 'Music',
      });
      expect(torrent.isComplete, isTrue, reason: state);
      expect(torrent.isFailed, isFalse, reason: state);
    }
  });
}
