import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/db/normalise.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/features/library/rating_controller.dart';

void main() {
  group('PlexRating', () {
    test('maps stars onto Plex\'s 0-10 scale', () {
      expect(PlexRating.fromStars(0), 0);
      expect(PlexRating.fromStars(3), 6);
      expect(PlexRating.fromStars(5), 10);
      // Out-of-range input must clamp, not produce an invalid rating.
      expect(PlexRating.fromStars(9), 10);
    });

    test('rounds half-star ratings set by other clients', () {
      // Plex permits halves; discarding them would show a 3.5-star album as
      // 3 stars and then overwrite it on the next tap.
      expect(PlexRating.toStars(7), 4);
      expect(PlexRating.toStars(5), 3);
      expect(PlexRating.toStars(null), 0);
    });

    test('favourite means four stars or better', () {
      expect(PlexRating.isFavourite(null), isFalse);
      expect(PlexRating.isFavourite(6), isFalse);
      expect(PlexRating.isFavourite(8), isTrue);
      expect(PlexRating.isFavourite(10), isTrue);
    });

    test('clear is -1, not 0', () {
      // 0 stores an explicit zero-star rating, which is a different state and
      // would still match rating filters.
      expect(PlexRating.clear, -1);
    });
  });

  group('rating writes', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    PlexClient clientThat({required bool succeeds, List<Uri>? log}) {
      return PlexClient(
        server: const PlexServer(
          name: 'Tower',
          baseUrl: 'https://tower.example:32400',
          token: 'tok',
          isLocal: true,
          isRelay: false,
        ),
        identity: PlexIdentity.forTesting(),
        httpClient: MockClient((request) async {
          log?.add(request.url);
          return http.Response('', succeeds ? 200 : 500);
        }),
      );
    }

    Future<PlexAlbum> seedAlbum({int? rating}) async {
      await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              ratingKey: 'b1',
              title: 'Kid A',
              normalisedTitle: normalise('Kid A'),
              artistTitle: 'Radiohead',
              normalisedArtist: normalise('Radiohead'),
              userRating: Value(rating),
            ),
          );
      return PlexAlbum(
        ratingKey: 'b1',
        title: 'Kid A',
        artist: 'Radiohead',
        userRating: rating,
      );
    }

    test('writes the rating locally and to Plex', () async {
      final log = <Uri>[];
      final album = await seedAlbum();
      final controller = RatingController(
        db: db,
        client: clientThat(succeeds: true, log: log),
      );

      final ok = await controller.rateAlbum(album, 4);

      expect(ok, isTrue);
      expect((await db.select(db.albums).getSingle()).userRating, 8);
      expect(log.single.path, '/:/rate');
      expect(log.single.queryParameters['rating'], '8');
      expect(log.single.queryParameters['key'], 'b1');
      expect(
        log.single.queryParameters['identifier'],
        'com.plexapp.plugins.library',
      );
    });

    test('rating zero stars clears via -1', () async {
      final log = <Uri>[];
      final album = await seedAlbum(rating: 8);
      final controller = RatingController(
        db: db,
        client: clientThat(succeeds: true, log: log),
      );

      await controller.rateAlbum(album, 0);

      expect((await db.select(db.albums).getSingle()).userRating, isNull);
      expect(log.single.queryParameters['rating'], '-1');
    });

    test('reverts the local write when Plex rejects it', () async {
      final album = await seedAlbum(rating: 6);
      final controller = RatingController(
        db: db,
        client: clientThat(succeeds: false),
      );

      final ok = await controller.rateAlbum(album, 5);

      expect(ok, isFalse);
      // Leaving 5 stars showing when the server still has 3 would be worse
      // than a visible failure, because ratings are what you browse by later.
      expect((await db.select(db.albums).getSingle()).userRating, 6);
    });

    test('rates an album the cache has never seen', () async {
      final controller = RatingController(
        db: db,
        client: clientThat(succeeds: true),
      );
      // A brand new album, reachable through a live Plex read but with no row
      // yet. The local write is an UPDATE, so without creating the row first it
      // matches nothing, Plex still accepts the rating, and Favourites stays
      // empty with no error anywhere.
      const album = PlexAlbum(
        ratingKey: 'new-1',
        title: 'Brand New',
        artist: 'Someone',
      );

      final ok = await controller.rateAlbum(album, 5);

      expect(ok, isTrue);
      expect(await db.watchFavouriteAlbums().first, hasLength(1));
    });

    test('favourites query returns only four stars and above', () async {
      for (final (key, rating) in [
        ('1', 10),
        ('2', 8),
        ('3', 6),
        ('4', null),
      ]) {
        await db
            .into(db.albums)
            .insert(
              AlbumsCompanion.insert(
                ratingKey: key,
                title: 'Album $key',
                normalisedTitle: normalise('Album $key'),
                artistTitle: 'A',
                normalisedArtist: 'a',
                userRating: Value(rating),
              ),
            );
      }

      final rows = await db.watchFavouriteAlbums().first;

      expect(rows.map((a) => a.ratingKey), ['1', '2']);
    });
  });

  group('smart playlists', () {
    test('parses the smart flag Plex sends as a string', () {
      final smart = PlexPlaylist.fromJson(
        jsonDecode(
              '{"ratingKey": "1", "title": "Recently Added", "smart": "1"}',
            )
            as Map<String, dynamic>,
      );
      final manual = PlexPlaylist.fromJson(
        jsonDecode('{"ratingKey": "2", "title": "Road trip"}')
            as Map<String, dynamic>,
      );

      expect(smart.smart, isTrue);
      expect(manual.smart, isFalse);
    });
  });
}
