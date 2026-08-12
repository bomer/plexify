import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/core/radio/sonic_radio.dart';

/// Artist radio: who Plex names as similar, and how their tracks are woven
/// into a queue.
///
/// **Per artist because that is what the server holds.** Measured across eleven
/// request shapes on 12 August 2026: `/nearest` answers 200 with an empty
/// container for a track, an album and an artist alike, every station path
/// 404s, and `/library/metadata/{artist}/similar` is the one that returns rows.
/// Plexamp agrees from the other side, greying its sonic radio out on a song
/// and offering it on an artist.
void main() {
  final server = PlexServer(
    name: 'Tower',
    baseUrl: 'https://tower.example:32400',
    token: 'servertoken',
    isLocal: true,
    isRelay: false,
    clientIdentifier: 'abc123',
  );

  PlexClient clientReturning(
    String body, {
    int status = 200,
    void Function(http.Request request)? onRequest,
  }) => PlexClient(
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

  String container(List<Map<String, dynamic>> rows) => jsonEncode({
    'MediaContainer': {'size': rows.length, 'Metadata': rows},
  });

  Map<String, dynamic> artistJson(String key) => {
    'ratingKey': key,
    'type': 'artist',
    'title': 'Artist $key',
  };

  PlexTrack track(String key, {bool playable = true}) => PlexTrack(
    ratingKey: key,
    title: 'Track $key',
    index: 1,
    durationMs: 200000,
    album: 'An album',
    artist: 'An artist',
    partKey: playable ? '/library/parts/$key/file.flac' : null,
  );

  List<PlexTrack> tracksNamed(String prefix, int count) => [
    for (var i = 0; i < count; i++) track('$prefix$i'),
  ];

  group('similarArtists', () {
    test('asks the artist for its neighbours', () async {
      Uri? asked;
      final client = clientReturning(
        container([artistJson('1')]),
        onRequest: (request) => asked = request.url,
      );

      await client.similarArtists('57754');

      expect(asked!.path, '/library/metadata/57754/similar');
    });

    test('keeps artists and drops everything else', () async {
      // The endpoint answers with five rows on a real library and nothing
      // documents what they are, so the type on each row is what decides.
      final client = clientReturning(
        container([
          artistJson('1'),
          {'ratingKey': '900', 'type': 'album', 'title': 'An album'},
          artistJson('2'),
          {'ratingKey': '901', 'type': 'track', 'title': 'A track'},
        ]),
      );

      final artists = await client.similarArtists('57754');

      expect(artists.map((a) => a.ratingKey), ['1', '2']);
    });

    test('a server without the endpoint returns empty', () async {
      // Older servers 404 this, and a library with no similarity data answers
      // 200 with nothing. Neither is worth an exception through a tap handler.
      final client = clientReturning('Not Found', status: 404);

      expect(await client.similarArtists('57754'), isEmpty);
    });
  });

  group('play queues, which is how a station is played', () {
    PlexClient posting({
      required String body,
      void Function(http.Request request)? onRequest,
    }) => PlexClient(
      server: server,
      identity: PlexIdentity.forTesting(),
      httpClient: MockClient((request) async {
        onRequest?.call(request);
        return http.Response(
          body,
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    Map<String, dynamic> trackJson(String key) => {
      'ratingKey': key,
      'type': 'track',
      'title': 'Track $key',
      'index': 1,
      'duration': 200000,
      'parentTitle': 'An album',
      'grandparentTitle': 'An artist',
      'Media': [
        {
          'Part': [
            {'key': '/library/parts/$key/file.flac', 'size': 5000000},
          ],
        },
      ],
    };

    test('posts the station key as a play queue source', () async {
      // A station's key is a source URI, not a path: fetching
      // /library/sections/3/stations/1 directly is a 404 on a real server, and
      // reading it as a path is what made the Stations hub look broken. The
      // server has to be named in the uri as well as addressed, because a play
      // queue can in principle draw from more than one.
      http.Request? sent;
      final client = posting(
        body: container([trackJson('1')]),
        onRequest: (request) => sent = request,
      );

      await client.playQueueTracks('/library/sections/3/stations/1');

      expect(sent!.method, 'POST');
      expect(sent!.url.path, '/playQueues');
      expect(sent!.url.queryParameters['type'], 'audio');
      expect(
        sent!.url.queryParameters['uri'],
        'server://abc123/com.plexapp.plugins.library'
        '/library/sections/3/stations/1',
      );
    });

    test(
      'plays the tracks the server chose, not a container to fetch',
      () async {
        final client = posting(
          body: container([trackJson('1'), trackJson('2')]),
        );

        final tracks = await client.playQueueTracks(
          '/library/sections/3/stations/1',
        );

        expect(tracks.map((t) => t.ratingKey), ['1', '2']);
      },
    );

    test('a refusal reaches the caller rather than going quiet', () async {
      // The opposite of every other call in this client, and deliberate: a
      // station is something the user just pressed, so there is somewhere to
      // put the reason. Nothing about /playQueues has been measured against a
      // real server yet, and a silent failure would be the third time this
      // feature looked like a dead button.
      final client = PlexClient(
        server: server,
        identity: PlexIdentity.forTesting(),
        httpClient: MockClient((_) async => http.Response('nope', 400)),
      );

      expect(
        () => client.playQueueTracks('/library/sections/3/stations/1'),
        throwsA(isA<PlexClientException>()),
      );
    });
  });

  group('building a station', () {
    // Seeded so the shuffle inside each artist is repeatable; the interleaving
    // being asserted here is not affected by which track comes out of a pool.
    Random seeded() => Random(7);

    test('opens with the artist it was asked about', () async {
      // "More like this" that starts with somebody else has answered a
      // different question.
      final station = const SonicRadio().build(
        byArtist: [tracksNamed('seed', 4), tracksNamed('other', 4)],
        random: seeded(),
      );

      expect(station.first.ratingKey, startsWith('seed'));
    });

    test('alternates between artists rather than playing each in turn', () {
      // Concatenation would be a station in name only: forty minutes of the
      // seed, then forty of whoever came second.
      final station = const SonicRadio(batch: 6).build(
        byArtist: [
          tracksNamed('a', 5),
          tracksNamed('b', 5),
          tracksNamed('c', 5),
        ],
        random: seeded(),
      );

      final owners = [for (final t in station) t.ratingKey.substring(0, 1)];
      expect(owners, ['a', 'b', 'c', 'a', 'b', 'c']);
    });

    test('keeps going when one artist runs out', () {
      // A library holding two tracks by one of the named artists must not cap
      // the whole station at two.
      final station = const SonicRadio(batch: 8).build(
        byArtist: [tracksNamed('a', 6), tracksNamed('b', 2)],
        random: seeded(),
      );

      expect(station, hasLength(8));
    });

    test('stops rather than repeating when everything runs out', () {
      final station = const SonicRadio(batch: 50).build(
        byArtist: [tracksNamed('a', 3), tracksNamed('b', 2)],
        random: seeded(),
      );

      expect(station, hasLength(5));
      expect(station.map((t) => t.ratingKey).toSet(), hasLength(5));
    });

    test('excludes what the queue already holds', () {
      // A refill must not replay the album that has been playing for the last
      // forty minutes.
      final station = const SonicRadio(batch: 10).build(
        byArtist: [tracksNamed('a', 4)],
        exclude: {'a0', 'a1'},
        random: seeded(),
      );

      expect(station.map((t) => t.ratingKey), unorderedEquals(['a2', 'a3']));
    });

    test('drops a track with no playable part', () {
      // The engine is handed the whole queue up front and does not skip, so an
      // unplayable entry is not a gap, it is a stall.
      final station = const SonicRadio(batch: 10).build(
        byArtist: [
          [track('a0', playable: false), track('a1')],
        ],
        random: seeded(),
      );

      expect(station.map((t) => t.ratingKey), ['a1']);
    });

    test('two stations from one seed are not the same running order', () {
      final byArtist = [tracksNamed('a', 12), tracksNamed('b', 12)];
      final first = const SonicRadio().build(
        byArtist: byArtist,
        random: Random(1),
      );
      final second = const SonicRadio().build(
        byArtist: byArtist,
        random: Random(2),
      );

      expect(
        first.map((t) => t.ratingKey),
        isNot(equals(second.map((t) => t.ratingKey))),
      );
    });
  });
}
