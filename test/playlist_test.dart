import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/db/normalise.dart';
import 'package:plexify/core/plex/plex_models.dart';

void main() {
  group('PlexPlaylist parsing', () {
    test('reads artwork from composite, not thumb', () {
      final playlist = PlexPlaylist.fromJson(
        jsonDecode('''
        {
          "ratingKey": "500",
          "title": "Focus",
          "composite": "/playlists/500/composite/1699887",
          "leafCount": 42,
          "duration": 9000000,
          "lastViewedAt": 1699999
        }
        ''')
            as Map<String, dynamic>,
      );

      // Plex generates a mosaic for playlists and exposes it as `composite`.
      // Reading `thumb` here silently yields no artwork at all.
      expect(playlist.thumb, '/playlists/500/composite/1699887');
      expect(playlist.itemCount, 42);
      expect(playlist.lastViewedAt, 1699999);
    });

    test('survives a playlist with nothing but a key', () {
      final playlist = PlexPlaylist.fromJson(
        jsonDecode('{"ratingKey": "1"}') as Map<String, dynamic>,
      );

      expect(playlist.title, 'Untitled playlist');
      expect(playlist.itemCount, 0);
    });
  });

  group('playlist storage', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> addPlaylist(String key, String title, {int? lastViewedAt}) {
      return db
          .into(db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              ratingKey: key,
              title: title,
              normalisedTitle: normalise(title),
              lastViewedAt: Value(lastViewedAt),
            ),
          );
    }

    test('never-played playlists sort last, not first', () async {
      await addPlaylist('1', 'Never played');
      await addPlaylist('2', 'Played recently', lastViewedAt: 900);
      await addPlaylist('3', 'Played a while ago', lastViewedAt: 100);

      final rows = await db.watchPlaylists().first;

      // SQLite sorts NULLs first on DESC by default, which would put every
      // playlist you have never opened above the ones you actually use.
      expect(rows.map((p) => p.title), [
        'Played recently',
        'Played a while ago',
        'Never played',
      ]);
    });

    test('replacing items drops stale positions', () async {
      await addPlaylist('p1', 'Focus');

      Future<void> addTrack(String key) => db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              ratingKey: key,
              title: 'Track $key',
              normalisedTitle: normalise('Track $key'),
            ),
          );
      for (final key in ['a', 'b', 'c']) {
        await addTrack(key);
      }

      await db.replacePlaylistItems('p1', [
        PlaylistItemsCompanion.insert(
          playlistRatingKey: 'p1',
          trackRatingKey: 'a',
          position: 0,
        ),
        PlaylistItemsCompanion.insert(
          playlistRatingKey: 'p1',
          trackRatingKey: 'b',
          position: 1,
        ),
        PlaylistItemsCompanion.insert(
          playlistRatingKey: 'p1',
          trackRatingKey: 'c',
          position: 2,
        ),
      ]);
      expect(await db.watchPlaylistTracks('p1').first, hasLength(3));

      // The playlist is reordered and shortened server-side.
      await db.replacePlaylistItems('p1', [
        PlaylistItemsCompanion.insert(
          playlistRatingKey: 'p1',
          trackRatingKey: 'c',
          position: 0,
        ),
        PlaylistItemsCompanion.insert(
          playlistRatingKey: 'p1',
          trackRatingKey: 'a',
          position: 1,
        ),
      ]);

      final rows = await db.watchPlaylistTracks('p1').first;
      // An upsert would have left 'b' behind at position 2. Playlists are
      // arranged, so the stored order must match the server exactly.
      expect(rows.map((t) => t.ratingKey), ['c', 'a']);
    });

    test('playlist tracks come back in playlist order, not track order',
        () async {
      await addPlaylist('p1', 'Shuffle-ish');
      for (final (key, index) in [('z', 1), ('a', 2), ('m', 3)]) {
        await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                ratingKey: key,
                title: 'Track $key',
                normalisedTitle: normalise('Track $key'),
                trackIndex: Value(index),
              ),
            );
      }

      await db.replacePlaylistItems('p1', [
        PlaylistItemsCompanion.insert(
          playlistRatingKey: 'p1',
          trackRatingKey: 'm',
          position: 0,
        ),
        PlaylistItemsCompanion.insert(
          playlistRatingKey: 'p1',
          trackRatingKey: 'z',
          position: 1,
        ),
        PlaylistItemsCompanion.insert(
          playlistRatingKey: 'p1',
          trackRatingKey: 'a',
          position: 2,
        ),
      ]);

      final rows = await db.watchPlaylistTracks('p1').first;
      expect(rows.map((t) => t.ratingKey), ['m', 'z', 'a']);
    });
  });
}
