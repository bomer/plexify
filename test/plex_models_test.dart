import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/plex/plex_models.dart';

/// These fixtures mirror the shape a real Plex Media Server returns, including
/// its inconsistencies — numeric fields arriving as strings, optional fields
/// simply absent. Parsing must survive all of it, because a single malformed
/// field should never cost us the whole library listing.
void main() {
  group('PlexTrack', () {
    test('extracts the part key needed for direct play', () {
      final track = PlexTrack.fromJson(
        jsonDecode('''
        {
          "ratingKey": "45821",
          "title": "Everything In Its Right Place",
          "parentTitle": "Kid A",
          "grandparentTitle": "Radiohead",
          "index": 1,
          "duration": 251946,
          "Media": [
            {
              "container": "flac",
              "Part": [
                {"key": "/library/parts/9931/1699887/file.flac", "container": "flac"}
              ]
            }
          ]
        }
        ''')
            as Map<String, dynamic>,
      );

      expect(track.partKey, '/library/parts/9931/1699887/file.flac');
      expect(track.container, 'flac');
      expect(track.isPlayable, isTrue);
      expect(track.artist, 'Radiohead');
      expect(track.album, 'Kid A');
      expect(track.duration, const Duration(milliseconds: 251946));
    });

    test('is not playable when the media has no parts', () {
      final track = PlexTrack.fromJson(
        jsonDecode('''
        {"ratingKey": "1", "title": "Orphaned", "Media": [{"container": "mp3"}]}
        ''')
            as Map<String, dynamic>,
      );

      expect(track.isPlayable, isFalse);
      expect(track.partKey, isNull);
    });

    test('survives a track with no Media block at all', () {
      final track = PlexTrack.fromJson(
        jsonDecode('{"ratingKey": "2", "title": "Ghost"}')
            as Map<String, dynamic>,
      );

      expect(track.isPlayable, isFalse);
      expect(track.title, 'Ghost');
      expect(track.index, 0);
    });

    test('coerces numeric fields delivered as strings', () {
      // Older servers and some endpoints stringify these.
      final track = PlexTrack.fromJson(
        jsonDecode('''
        {"ratingKey": 99, "title": "Coerced", "index": "7", "duration": "1000"}
        ''')
            as Map<String, dynamic>,
      );

      expect(track.ratingKey, '99');
      expect(track.index, 7);
      expect(track.durationMs, 1000);
    });
  });

  group('PlexAlbum', () {
    test('reads the album artist from parentTitle', () {
      final album = PlexAlbum.fromJson(
        jsonDecode('''
        {
          "ratingKey": "45820",
          "title": "Kid A",
          "parentTitle": "Radiohead",
          "year": 2000,
          "thumb": "/library/metadata/45820/thumb/1699887"
        }
        ''')
            as Map<String, dynamic>,
      );

      expect(album.title, 'Kid A');
      expect(album.artist, 'Radiohead');
      expect(album.year, 2000);
    });

    test('falls back to placeholders rather than throwing', () {
      final album = PlexAlbum.fromJson(
        jsonDecode('{"ratingKey": "1"}') as Map<String, dynamic>,
      );

      expect(album.title, 'Unknown album');
      expect(album.artist, 'Unknown artist');
      expect(album.thumb, isNull);
    });
  });

  group('PlexSection', () {
    test('identifies the music section by type', () {
      final music = PlexSection.fromJson(
        jsonDecode(
              '{"key": "3", "type": "artist", "title": "Music", "updatedAt": 1699887}',
            )
            as Map<String, dynamic>,
      );
      final movies = PlexSection.fromJson(
        jsonDecode('{"key": "1", "type": "movie", "title": "Movies"}')
            as Map<String, dynamic>,
      );

      expect(music.isMusic, isTrue);
      expect(music.updatedAt, 1699887);
      expect(movies.isMusic, isFalse);
    });
  });

  group('PlexResource', () {
    test('separates local, remote and relay connections', () {
      final resource = PlexResource.fromJson(
        jsonDecode('''
        {
          "name": "Tower",
          "clientIdentifier": "abc123",
          "provides": "server",
          "owned": true,
          "accessToken": "servertoken",
          "connections": [
            {"uri": "https://192-168-1-10.abc.plex.direct:32400", "local": true,  "relay": false},
            {"uri": "https://82-1-2-3.abc.plex.direct:32400",     "local": false, "relay": false},
            {"uri": "https://relay.plex.direct:443",              "local": false, "relay": true}
          ]
        }
        ''')
            as Map<String, dynamic>,
      );

      expect(resource.isServer, isTrue);
      expect(resource.connections, hasLength(3));
      expect(resource.connections.where((c) => c.local), hasLength(1));
      expect(resource.connections.where((c) => c.relay), hasLength(1));
    });

    test('excludes resources that are not servers', () {
      final player = PlexResource.fromJson(
        jsonDecode(
              '{"name": "Phone", "clientIdentifier": "x", "provides": "player,controller"}',
            )
            as Map<String, dynamic>,
      );

      expect(player.isServer, isFalse);
    });

    test('treats Plex\'s 1/0 integers as booleans', () {
      final resource = PlexResource.fromJson(
        jsonDecode('''
        {
          "name": "Tower", "clientIdentifier": "abc", "provides": "server", "owned": 1,
          "connections": [{"uri": "https://x:32400", "local": 1, "relay": 0}]
        }
        ''')
            as Map<String, dynamic>,
      );

      expect(resource.owned, isTrue);
      expect(resource.connections.single.local, isTrue);
      expect(resource.connections.single.relay, isFalse);
    });
  });
}
