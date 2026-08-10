import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/core/radio/sonic_radio.dart';

/// Sonic radio: what Plex's `/nearest` gives back, and what a station does with
/// it.
///
/// The endpoint itself is measured against recorded shapes rather than a live
/// server, and the shapes here are the ones that have actually bitten this
/// project: a container with rows of mixed type in it, and a server that
/// answers an endpoint it does not implement.
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

  Map<String, dynamic> trackJson(String key, {bool playable = true}) => {
    'ratingKey': key,
    'type': 'track',
    'title': 'Track $key',
    'index': 1,
    'duration': 200000,
    'parentTitle': 'An album',
    'grandparentTitle': 'An artist',
    if (playable)
      'Media': [
        {
          'Part': [
            {'key': '/library/parts/$key/file.flac', 'size': 5000000},
          ],
        },
      ],
  };

  String container(List<Map<String, dynamic>> rows) => jsonEncode({
    'MediaContainer': {'size': rows.length, 'Metadata': rows},
  });

  PlexTrack track(String key, {bool playable = true}) =>
      PlexTrack.fromJson(trackJson(key, playable: playable));

  group('nearest', () {
    test('asks the seed track for its neighbours', () async {
      Uri? asked;
      final client = clientReturning(
        container([trackJson('1'), trackJson('2')]),
        onRequest: (request) => asked = request.url,
      );

      await client.nearest('55', limit: 12);

      expect(asked!.path, '/library/metadata/55/nearest');
      expect(asked!.queryParameters['limit'], '12');
    });

    test('sends no type filter, because Plex ignores the ones it dislikes', () {
      // The whole class of bug this project keeps hitting: a parameter the
      // server does not implement is dropped rather than rejected, so a filter
      // that does nothing looks exactly like a filter that worked. Whatever
      // arrives is filtered here instead, on the row's own declared type.
      Uri? asked;
      final client = clientReturning(
        container([trackJson('1')]),
        onRequest: (request) => asked = request.url,
      );

      return client.nearest('55').then((_) {
        expect(asked!.queryParameters, isNot(contains('type')));
      });
    });

    test('keeps tracks and drops everything else in the container', () async {
      final client = clientReturning(
        container([
          trackJson('1'),
          {'ratingKey': '900', 'type': 'album', 'title': 'An album'},
          trackJson('2'),
          {'ratingKey': '901', 'type': 'artist', 'title': 'An artist'},
        ]),
      );

      final tracks = await client.nearest('55');

      expect(tracks.map((t) => t.ratingKey), ['1', '2']);
    });

    test('a server that has never heard of the endpoint returns empty', () async {
      // A library with no sonic analysis, or an older server. Both are ordinary
      // states rather than faults, and a station that cannot be built is a
      // message rather than an exception thrown through the tap handler.
      final client = clientReturning('Not Found', status: 404);

      expect(await client.nearest('55'), isEmpty);
    });
  });

  group('chooseRadioTracks', () {
    test("keeps Plex's order, which is the whole value of the endpoint", () {
      final picked = chooseRadioTracks(
        candidates: [track('3'), track('1'), track('2')],
        exclude: const {},
        want: 10,
      );

      expect(picked.map((t) => t.ratingKey), ['3', '1', '2']);
    });

    test('excludes what is already in the queue', () {
      // Sonic similarity is close to symmetric: the nearest track to A is
      // usually B and the nearest to B is usually A. Without this a station is
      // two songs, forever.
      final picked = chooseRadioTracks(
        candidates: [track('1'), track('2'), track('3')],
        exclude: const {'1', '3'},
        want: 10,
      );

      expect(picked.map((t) => t.ratingKey), ['2']);
    });

    test('drops a track with no playable part', () {
      // The engine is handed the whole queue up front and does not skip, so an
      // unplayable entry is not a gap, it is a stall.
      final picked = chooseRadioTracks(
        candidates: [track('1', playable: false), track('2')],
        exclude: const {},
        want: 10,
      );

      expect(picked.map((t) => t.ratingKey), ['2']);
    });

    test('one response listing a track twice yields it once', () {
      final picked = chooseRadioTracks(
        candidates: [track('1'), track('1'), track('2')],
        exclude: const {},
        want: 10,
      );

      expect(picked.map((t) => t.ratingKey), ['1', '2']);
    });

    test('stops at want, so a refill cannot queue an afternoon', () {
      final picked = chooseRadioTracks(
        candidates: [for (var i = 0; i < 50; i++) track('$i')],
        exclude: const {},
        want: 4,
      );

      expect(picked, hasLength(4));
    });
  });

  group('SonicRadio', () {
    test('a station starts with the song it was started from', () async {
      final client = clientReturning(
        container([trackJson('7'), trackJson('8'), trackJson('9')]),
      );

      final tracks = await const SonicRadio().start(client, track('7'));

      // Seed first, and exactly once: the endpoint returns the seed among its
      // own neighbours, and a station that opened with the same song twice
      // would look like a stutter.
      expect(tracks.map((t) => t.ratingKey), ['7', '8', '9']);
    });

    test('asks for more candidates than it means to keep', () async {
      // The exclusion set is at its densest right around the seed, so a batch
      // asked for exactly is a batch that comes back short and triggers another
      // refill straight away.
      Uri? asked;
      final client = clientReturning(
        container([trackJson('1')]),
        onRequest: (request) => asked = request.url,
      );

      await const SonicRadio(
        batch: 20,
      ).extend(client, seedRatingKey: '7', exclude: const {});

      expect(int.parse(asked!.queryParameters['limit']!), greaterThan(20));
    });

    test('a refill will not replay what the queue already holds', () async {
      final client = clientReturning(
        container([trackJson('1'), trackJson('2'), trackJson('3')]),
      );

      final more = await const SonicRadio().extend(
        client,
        seedRatingKey: '1',
        exclude: const {'1', '2'},
      );

      expect(more.map((t) => t.ratingKey), ['3']);
    });

    test(
      'an exhausted neighbourhood ends the station rather than looping',
      () async {
        final client = clientReturning(container([trackJson('1')]));

        final more = await const SonicRadio().extend(
          client,
          seedRatingKey: '1',
          exclude: const {'1'},
        );

        expect(more, isEmpty);
      },
    );
  });
}
