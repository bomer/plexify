import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_server.dart';

/// Exercises PlexClient against recorded response shapes so CI never needs a
/// live Plex server.
void main() {
  final server = PlexServer(
    name: 'Tower',
    baseUrl: 'https://tower.example:32400',
    token: 'servertoken',
    isLocal: true,
    isRelay: false,
  );

  PlexClient clientReturning(
    String body, {
    int status = 200,
    void Function(http.Request request)? onRequest,
  }) {
    return PlexClient(
      server: server,
      identity: PlexIdentity.forTesting(),
      httpClient: MockClient((request) async {
        onRequest?.call(request);
        return http.Response(
          body,
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  group('sections', () {
    test('finds the music section among other library types', () async {
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Directory': [
              {'key': '1', 'type': 'movie', 'title': 'Movies'},
              {'key': '3', 'type': 'artist', 'title': 'Music'},
              {'key': '2', 'type': 'show', 'title': 'TV'},
            ],
          },
        }),
      );

      final section = await client.musicSection();

      expect(section, isNotNull);
      expect(section!.key, '3');
      expect(section.title, 'Music');
    });

    test('returns null when the server has no music library', () async {
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Directory': [
              {'key': '1', 'type': 'movie', 'title': 'Movies'},
            ],
          },
        }),
      );

      expect(await client.musicSection(), isNull);
    });

    test('treats an absent list key as empty, not an error', () async {
      // Plex omits the key entirely rather than sending [].
      final client = clientReturning(jsonEncode({'MediaContainer': {}}));

      expect(await client.sections(), isEmpty);
    });
  });

  group('albums', () {
    test('requests type=9 and paginates via container headers', () async {
      late http.Request captured;
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Metadata': [
              {'ratingKey': '1', 'title': 'Kid A', 'parentTitle': 'Radiohead'},
            ],
          },
        }),
        onRequest: (r) => captured = r,
      );

      final albums = await client.albums('3', start: 100, size: 50);

      expect(albums, hasLength(1));
      expect(albums.single.title, 'Kid A');
      expect(captured.url.queryParameters['type'], '9');
      // Pagination is a header contract on Plex, not a query one.
      expect(captured.headers['X-Plex-Container-Start'], '100');
      expect(captured.headers['X-Plex-Container-Size'], '50');
    });

    test('sends the token and asks for JSON', () async {
      late http.Request captured;
      final client = clientReturning(
        jsonEncode({'MediaContainer': {}}),
        onRequest: (r) => captured = r,
      );

      await client.sections();

      expect(captured.headers['X-Plex-Token'], 'servertoken');
      // Without this header Plex returns XML and every parser here breaks.
      expect(captured.headers['Accept'], 'application/json');
      expect(captured.headers['X-Plex-Client-Identifier'], 'test-client-id');
    });
  });

  group('the delta filter', () {
    Future<Map<String, String>> queryFor(int? minUpdatedAt) async {
      late http.Request captured;
      final client = clientReturning(
        jsonEncode({'MediaContainer': {}}),
        onRequest: (r) => captured = r,
      );
      await client.sectionPage<Object>(
        '3',
        type: PlexClient.typeTrack,
        parse: (json) => json,
        minUpdatedAt: minUpdatedAt,
      );
      return captured.url.queryParameters;
    }

    test('asks one second earlier than the cursor', () async {
      final query = await queryFor(1000);

      // The filter is strict, measured (#51): `updatedAt>=` is silently ignored
      // by Plex while `updatedAt>` is applied. The cursor is the newest
      // updatedAt already stored, so asking for strictly-newer-than-it would
      // skip a row stamped that same second which we have never seen. A bulk
      // edit stamps many rows with one timestamp, so that is a real case.
      //
      // The cost of the compensation is one already-cached row coming back per
      // pass, and every sync write is an upsert, so it lands on itself.
      expect(query[PlexClient.deltaFilter], '999');
    });

    test('is left off entirely for a full sync', () async {
      expect(await queryFor(0), isNot(contains(PlexClient.deltaFilter)));
      expect(await queryFor(null), isNot(contains(PlexClient.deltaFilter)));

      // Cursor zero means "fetch everything", which is what a fresh install and
      // every migration rewind ask for. Sending `updatedAt>-1` instead would be
      // harmless here but would quietly exclude rows carrying no timestamp at
      // all, and roughly 1,500 of James's 11,492 tracks are in that state.
    });
  });

  group('errors', () {
    test('gives an actionable message on an expired token', () async {
      final client = clientReturning('', status: 401);

      expect(
        () => client.sections(),
        throwsA(
          isA<PlexClientException>().having(
            (e) => e.message,
            'message',
            contains('sign in again'),
          ),
        ),
      );
    });

    test('surfaces the status code on other failures', () async {
      final client = clientReturning('', status: 503);

      expect(
        () => client.sections(),
        throwsA(
          isA<PlexClientException>().having(
            (e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });
  });

  group('URL building', () {
    test('direct play URL points at the part and carries the token', () async {
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Metadata': [
              {
                'ratingKey': '1',
                'title': 'Idioteque',
                'Media': [
                  {
                    'container': 'flac',
                    'Part': [
                      {'key': '/library/parts/99/1699/file.flac'},
                    ],
                  },
                ],
              },
            ],
          },
        }),
      );

      final tracks = await client.tracks('45820');
      final url = client.directPlayUrl(tracks.single);

      expect(url, isNotNull);
      final uri = Uri.parse(url!);
      expect(uri.path, '/library/parts/99/1699/file.flac');
      // The token must be in the query string, not a header: this URL is handed
      // to ExoPlayer/libmpv, which do their own HTTP and drop our headers.
      expect(uri.queryParameters['X-Plex-Token'], 'servertoken');
    });

    test('direct play URL is null for a track with no part', () async {
      final client = clientReturning(
        jsonEncode({
          'MediaContainer': {
            'Metadata': [
              {'ratingKey': '1', 'title': 'Ghost'},
            ],
          },
        }),
      );

      final tracks = await client.tracks('45820');
      expect(client.directPlayUrl(tracks.single), isNull);
    });

    test('artwork goes through the photo transcoder at a requested size', () {
      final client = clientReturning('');

      final url = client.artworkUrl(
        '/library/metadata/45820/thumb/1699887',
        width: 300,
        height: 300,
      );

      expect(url, isNotNull);
      final uri = Uri.parse(url!);
      expect(uri.path, '/photo/:/transcode');
      expect(uri.queryParameters['width'], '300');
      // **Relative, and this is the fix for "artwork never arrived off the
      // LAN".** It used to be `{baseUrl}{thumb}`, which asks the server to
      // fetch the image from itself over whichever address this client happens
      // to hold. At home that is harmless. Away, it tells the server to dial
      // its own public address — needing hairpin NAT — or its plex.tv relay,
      // which it has no business calling at all. The transcoder fails the same
      // way every time, so anything synced while away had no artwork then and
      // no artwork after a restart either.
      expect(
        uri.queryParameters['url'],
        '/library/metadata/45820/thumb/1699887',
      );
      expect(uri.queryParameters['X-Plex-Token'], 'servertoken');
    });

    test('the artwork URL carries no address but its own', () {
      // The server's address appears once, as the host being asked. A second
      // copy inside the query is what made this route-dependent.
      final url = clientReturning(
        '',
      ).artworkUrl('/library/metadata/45820/thumb/1699887')!;

      expect(url.indexOf('tower.example'), url.lastIndexOf('tower.example'));
    });

    test('artwork is null when the item has no thumb', () {
      final client = clientReturning('');

      expect(client.artworkUrl(null), isNull);
      expect(client.artworkUrl(''), isNull);
    });
  });
}
