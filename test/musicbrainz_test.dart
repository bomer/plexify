import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/catalog/catalog_models.dart';
import 'package:plexify/core/catalog/musicbrainz_client.dart';

/// MusicBrainz enforces two rules with the *same* status code, and both of them
/// are invisible until they bite: a request per second, and a descriptive user
/// agent. It answers 503 for either, which reads as the service being down.
///
/// These tests pin both, plus the parsing, against recorded shapes rather than
/// a live service.
void main() {
  /// Records what was asked and answers with a canned body.
  ({http.Client client, List<http.Request> requests}) recording(
    Map<String, dynamic> Function(http.Request) body, {
    int status = 200,
  }) {
    final requests = <http.Request>[];
    return (
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(body(request)),
          status,
          headers: const {'content-type': 'application/json'},
        );
      }),
      requests: requests,
    );
  }

  /// Pacing is real time, so the tests inject a no-op sleep. What is being
  /// asserted is that the *request* was paced, not how long the test took.
  MusicBrainzClient clientWith(http.Client http_, {List<Duration>? slept}) =>
      MusicBrainzClient(httpClient: http_, sleep: (d) async => slept?.add(d));

  test('names the application and a contact in the user agent', () async {
    final recorded = recording((_) => {'release-groups': []});
    await clientWith(recorded.client).searchReleaseGroups('kid a');

    // MusicBrainz answers 503 to generic agents, which is indistinguishable
    // from being rate limited. Without this the whole tier silently returns
    // nothing and looks like a network problem.
    final agent = recorded.requests.single.headers['User-Agent'];
    expect(agent, contains('Plexify'));
    expect(agent, contains('github.com'));
  });

  test('parses a release group, artist credit and all', () async {
    final recorded = recording(
      (_) => {
        'release-groups': [
          {
            'id': 'mb-1',
            'title': 'OK Computer',
            'first-release-date': '1997-05-21',
            'primary-type': 'Album',
            'secondary-types': <String>[],
            'artist-credit': [
              {
                'name': 'Radiohead',
                'artist': {'id': 'artist-1', 'name': 'Radiohead'},
              },
            ],
          },
        ],
      },
    );

    final results = await clientWith(
      recorded.client,
    ).searchReleaseGroups('ok computer');

    expect(results, hasLength(1));
    expect(results.single.title, 'OK Computer');
    expect(results.single.artist, 'Radiohead');
    expect(results.single.artistMbid, 'artist-1');
    // A bare year, a year-month and a full date all have to yield the year.
    expect(results.single.year, 1997);
    expect(results.single.isPrimaryWork, isTrue);
  });

  test('a compilation is not a primary work', () {
    // Not a parsing detail: a well-catalogued artist has three or four times as
    // many compilations as albums, and listing them turns a missing-albums grid
    // into a wall nobody reads.
    final compilation = CatalogRelease.fromJson({
      'id': 'mb-2',
      'title': 'The Best Of',
      'primary-type': 'Album',
      'secondary-types': ['Compilation'],
    });

    expect(compilation.isPrimaryWork, isFalse);
  });

  test('asks for artist credits when browsing a discography', () async {
    final recorded = recording((_) => {'release-groups': []});
    await clientWith(recorded.client).releaseGroupsForArtist('artist-1');

    // Without inc=artist-credits every row comes back attributed to nobody,
    // which then matches nothing in the library and reports a complete
    // discography as entirely missing.
    expect(
      recorded.requests.single.url.queryParameters['inc'],
      'artist-credits',
    );
  });

  test('paces requests rather than trusting callers to', () async {
    final slept = <Duration>[];
    final recorded = recording((_) => {'release-groups': []});
    final client = clientWith(recorded.client, slept: slept);

    await client.searchReleaseGroups('a');
    await client.searchReleaseGroups('b');
    await client.searchReleaseGroups('c');

    expect(recorded.requests, hasLength(3));
    // The first request has nothing to wait for; every one after it does. Break
    // the gap and this drops to zero waits, which is exactly the 503 nobody can
    // diagnose.
    expect(slept, hasLength(2));
    expect(slept.every((d) => d > Duration.zero), isTrue);
  });

  test('two callers asking the same question cost one request', () async {
    final recorded = recording((_) => {'release-groups': []});
    final client = clientWith(recorded.client);

    // The artist page and search can want the same lookup at once. Paced, that
    // would be two seconds instead of one for an identical answer.
    await Future.wait([
      client.searchReleaseGroups('kid a'),
      client.searchReleaseGroups('kid a'),
    ]);

    expect(recorded.requests, hasLength(1));
  });

  test('retries a 503 once, and only once', () async {
    final slept = <Duration>[];
    final recorded = recording((_) => {}, status: 503);
    final client = clientWith(recorded.client, slept: slept);

    final results = await client.searchReleaseGroups('kid a');

    expect(results, isEmpty);
    // Two attempts, not a loop. A 503 is either the rate limit — worth one
    // wait — or a rejected user agent, which will never succeed however many
    // times it is asked, and hammering a service that just asked you to stop is
    // how an address gets blocked.
    expect(recorded.requests, hasLength(2));
    expect(client.lastError, contains('503'));
  });

  test('a failure is an empty result, never an exception', () async {
    final client = clientWith(
      MockClient((_) async => throw const SocketExceptionStub()),
    );

    // This is the lower tier of search. Local results are already on screen,
    // and MusicBrainz being unreachable must never be able to surface as an
    // error over a library that searched perfectly well.
    expect(await client.searchReleaseGroups('kid a'), isEmpty);
    expect(await client.searchArtists('radiohead'), isEmpty);
    expect(client.lastError, isNotNull);
  });

  test('escapes Lucene syntax in whatever was typed', () async {
    final recorded = recording((_) => {'artists': []});
    await clientWith(recorded.client).searchArtists('AC/DC: live?');

    // A bare colon or slash is a 400 from this endpoint, and album titles
    // contain both. Escaped rather than stripped, so the words survive.
    final query = recorded.requests.single.url.queryParameters['query']!;
    expect(query, contains(r'\/'));
    expect(query, contains(r'\:'));
    expect(query, contains('live'));
  });
}

/// Stands in for a transport failure without importing `dart:io`.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
