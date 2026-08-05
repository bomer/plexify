import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/audio/timeline_reporter.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/core/sync/library_writer.dart';

/// Plex is the source of truth for listening history, and a play that is not
/// reported cannot be reconstructed afterwards. These are the rules for what
/// gets sent and — just as important — what gets sent only once.
void main() {
  late AppDatabase db;
  late List<Uri> requests;
  late StreamController<MediaItem?> items;
  late StreamController<PlaybackState> states;
  late Duration position;
  late int failWithStatus;
  late TimelineReporter reporter;
  late DateTime clock;

  setUp(() {
    clock = DateTime(2026, 8, 5, 12);
    db = AppDatabase(NativeDatabase.memory());
    requests = [];
    items = StreamController<MediaItem?>.broadcast();
    states = StreamController<PlaybackState>.broadcast();
    position = Duration.zero;
    failWithStatus = 0;

    final client = PlexClient(
      server: const PlexServer(
        name: 'Tower',
        baseUrl: 'https://tower.example:32400',
        token: 'tok',
        isLocal: true,
        isRelay: false,
      ),
      identity: PlexIdentity.forTesting(),
      httpClient: MockClient((request) async {
        requests.add(request.url);
        if (failWithStatus != 0) return http.Response('', failWithStatus);
        return http.Response('', 200);
      }),
    );

    reporter = TimelineReporter(
      client: client,
      writer: LibraryWriter(db),
      mediaItems: items.stream,
      playbackStates: states.stream,
      position: () => position,
      interval: const Duration(milliseconds: 20),
      now: () => clock,
    );
    reporter.start();
  });

  tearDown(() async {
    await reporter.stop();
    await items.close();
    await states.close();
    await db.close();
  });

  MediaItem track(
    String key, {
    Duration duration = const Duration(minutes: 4),
  }) => MediaItem(
    id: 'https://tower.example:32400/parts/$key',
    title: 'Track $key',
    duration: duration,
    extras: {'ratingKey': key},
  );

  List<Uri> timelines() =>
      requests.where((u) => u.path == '/:/timeline').toList();
  List<Uri> scrobbles() =>
      requests.where((u) => u.path == '/:/scrobble').toList();

  /// Lets the reporter's serialised queue drain.
  Future<void> settle() => pumpEventQueue();

  group('reporting', () {
    test('starting a track tells Plex what is playing', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      await settle();

      final report = timelines().last;
      expect(report.queryParameters['ratingKey'], 't1');
      expect(report.queryParameters['state'], 'playing');
      // Plex wants both forms; sending only the bare key gets a 200 that
      // quietly does nothing.
      expect(report.queryParameters['key'], '/library/metadata/t1');
      expect(report.queryParameters['duration'], '240000');
      expect(
        report.queryParameters['identifier'],
        'com.plexapp.plugins.library',
      );
    });

    test('pausing is reported without waiting for the next tick', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      await settle();
      final before = timelines().length;

      states.add(PlaybackState(playing: false));
      await settle();

      // Someone watching from another device is waiting to see this.
      expect(timelines().length, before + 1);
      expect(timelines().last.queryParameters['state'], 'paused');
    });

    test('a running track keeps being reported', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      await settle();
      final before = timelines().length;

      await Future<void>.delayed(const Duration(milliseconds: 70));
      await settle();

      // Plex treats silence as the session having ended.
      expect(timelines().length, greaterThan(before));
    });

    test('a paused track is not reported on every tick', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      states.add(PlaybackState(playing: false));
      await settle();
      final before = timelines().length;

      await Future<void>.delayed(const Duration(milliseconds: 70));
      await settle();

      expect(timelines().length, before);
    });

    test('changing track closes the previous one', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      await settle();

      items.add(track('t2'));
      await settle();

      final stopped = timelines().where(
        (u) =>
            u.queryParameters['ratingKey'] == 't1' &&
            u.queryParameters['state'] == 'stopped',
      );
      // Otherwise the server keeps the old track in Now Playing until it times
      // out, and two tracks appear to be playing at once.
      expect(stopped, hasLength(1));
    });

    test('the session is closed explicitly on the way out', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      await settle();

      await reporter.reportStopped();

      // Left to time out, the entry sits in Plex's dashboard claiming to play
      // for minutes after the app has gone — and the next launch looks like a
      // second copy running alongside it.
      expect(timelines().last.queryParameters['state'], 'stopped');
      expect(timelines().last.queryParameters['ratingKey'], 't1');
    });

    test('a server that refuses does not throw', () async {
      failWithStatus = 500;

      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      await settle();

      // Reporting runs against a server that may be asleep or mid-reconnect.
      // The audio is the point; this is a courtesy.
      expect(reporter.lastError, isNotNull);
      expect(timelines(), isNotEmpty);
    });
  });

  group('scrobbling', () {
    test('a track played to the end is counted', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      position = const Duration(minutes: 4);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle();

      expect(scrobbles(), hasLength(1));
      expect(scrobbles().single.queryParameters['key'], 't1');
    });

    test('a track barely started is not counted', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      position = const Duration(seconds: 30);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle();

      expect(scrobbles(), isEmpty);
    });

    test('it is counted once, not once per tick', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      position = const Duration(minutes: 4);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await settle();

      // A play count that climbs while the last ten seconds run out would be
      // worse than not reporting at all.
      expect(scrobbles(), hasLength(1));
    });

    test('seeking back and forward again does not count twice', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      position = const Duration(minutes: 4);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle();

      position = const Duration(minutes: 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      position = const Duration(minutes: 4);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle();

      expect(scrobbles(), hasLength(1));
    });

    test('a track that ends between ticks is still counted', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1', duration: const Duration(seconds: 20)));
      await settle();

      // Runs to its end and is replaced before any tick notices — the case a
      // purely timer-driven reporter loses, and short tracks hit it most. The
      // player has already moved on, so its position getter reports the *new*
      // track; only elapsed time can say where the old one got to.
      clock = clock.add(const Duration(seconds: 20));
      items.add(track('t2'));
      await settle();

      expect(scrobbles().map((u) => u.queryParameters['key']), ['t1']);
    });

    test('a track skipped early is not counted', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1', duration: const Duration(seconds: 20)));
      await settle();

      // Same path as above, three seconds in instead of twenty.
      clock = clock.add(const Duration(seconds: 3));
      items.add(track('t2'));
      await settle();

      expect(scrobbles(), isEmpty);
    });

    test('going back to a finished track counts a second play', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      position = const Duration(minutes: 4);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      items.add(track('t2'));
      await settle();
      items.add(track('t1'));
      position = const Duration(minutes: 4);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle();

      // It really is a second play, so this is correct rather than a leak.
      expect(
        scrobbles().where((u) => u.queryParameters['key'] == 't1'),
        hasLength(2),
      );
    });
  });

  group('local history', () {
    setUp(() async {
      await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              ratingKey: 'a1',
              title: 'Album',
              normalisedTitle: 'album',
              artistTitle: 'Artist',
              normalisedArtist: 'artist',
            ),
          );
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              ratingKey: 't1',
              title: 'Track',
              normalisedTitle: 'track',
              albumRatingKey: const Value('a1'),
            ),
          );
    });

    test('a play updates the track and its album immediately', () async {
      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      position = const Duration(minutes: 4);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle();

      final row = await (db.select(
        db.tracks,
      )..where((t) => t.ratingKey.equals('t1'))).getSingle();
      final album = await (db.select(
        db.albums,
      )..where((a) => a.ratingKey.equals('a1'))).getSingle();

      // Home's "Jump back in" sorts on the album's lastViewedAt. Writing only
      // the track would leave the shelf unchanged by listening.
      expect(row.lastViewedAt, isNotNull);
      expect(album.lastViewedAt, isNotNull);
      // Plex stores epoch seconds; milliseconds here would sort wrongly against
      // every row the sync wrote.
      expect(album.lastViewedAt, DateTime(2026, 8, 5, 12).millisecondsSinceEpoch ~/ 1000);
    });

    test('history is recorded even when Plex refused the scrobble', () async {
      failWithStatus = 500;

      states.add(PlaybackState(playing: true));
      items.add(track('t1'));
      position = const Duration(minutes: 4);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle();

      final row = await (db.select(
        db.tracks,
      )..where((t) => t.ratingKey.equals('t1'))).getSingle();

      // The play happened. Showing it beats agreeing with a server that was
      // briefly unreachable, and the next sync reconciles either way.
      expect(row.lastViewedAt, isNotNull);
    });
  });
}
