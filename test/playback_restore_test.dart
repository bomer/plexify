import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/audio/playback_handler.dart';
import 'package:plexify/core/audio/playback_source.dart';
import 'package:plexify/core/audio/playback_state_store.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/core/sync/library_writer.dart';
import 'package:plexify/features/player/playback_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_just_audio.dart';

/// Two things a queue never used to know: that it should still exist tomorrow,
/// and what it was started *from*.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lan = PlexServer(
    name: 'Tower',
    baseUrl: 'https://192-168-0-2.plex.direct:32400',
    token: 'servertoken',
    isLocal: true,
    isRelay: false,
  );
  const remote = PlexServer(
    name: 'Tower',
    baseUrl: 'https://82-1-2-3.plex.direct:32400',
    token: 'servertoken',
    isLocal: false,
    isRelay: false,
  );

  late FakeJustAudio audio;
  late PlaybackStateStore store;

  setUp(() async {
    audio = FakeJustAudio.install();
    SharedPreferences.setMockInitialValues({});
    store = PlaybackStateStore(await SharedPreferences.getInstance());
  });

  PlexClient clientFor(PlexServer server) => PlexClient(
    server: server,
    identity: PlexIdentity.forTesting(),
    httpClient: MockClient((_) async => http.Response('', 200)),
  );

  PlexTrack track(String ratingKey, {int sourceKbps = 1000}) => PlexTrack(
    ratingKey: ratingKey,
    title: 'Track $ratingKey',
    index: 1,
    durationMs: 180000,
    album: 'Album',
    artist: 'Artist',
    partKey: '/library/parts/$ratingKey/file.flac',
    thumb: '/library/metadata/$ratingKey/thumb/1',
    partSizeBytes: sourceKbps * 22500,
  );

  PlaybackController controllerOn(
    PlexServer server,
    PlexifyAudioHandler handler, {
    List<ConnectivityResult> connectivity = const [ConnectivityResult.wifi],
  }) => PlaybackController(
    handler: handler,
    client: clientFor(server),
    store: store,
    checkConnectivity: () async => connectivity,
    newSession: () => 'session-1',
  );

  group('restoring the last session', () {
    test('brings the queue back where it was left', () async {
      final first = PlexifyAudioHandler();
      addTearDown(first.dispose);
      final before = controllerOn(lan, first);
      await before.playTracks([track('1'), track('2'), track('3')]);
      await first.skipToNext();
      await first.seek(const Duration(seconds: 45));
      await before.save();

      // A fresh handler is what the next launch actually has.
      final next = PlexifyAudioHandler();
      addTearDown(next.dispose);
      await controllerOn(lan, next).restore();

      expect(next.queue.value, hasLength(3));
      expect(next.currentIndex, 1);
      expect(next.queue.value[1].extras?['ratingKey'], '2');
      expect(audio.player.position.inSeconds, 45);
    });

    test('does not start playing on its own', () async {
      final first = PlexifyAudioHandler();
      addTearDown(first.dispose);
      await controllerOn(lan, first).playTracks([track('1')]);
      await controllerOn(lan, first).save();

      final next = PlexifyAudioHandler();
      addTearDown(next.dispose);
      await controllerOn(lan, next).restore();

      // Opening an app is not the same as asking it to make a noise. The mini
      // player appears with the track it left on and play resumes it.
      expect(next.mediaItem.value, isNotNull);
      expect(audio.player.playing, isFalse);
    });

    test('rebuilds URLs rather than restoring them', () async {
      final first = PlexifyAudioHandler();
      addTearDown(first.dispose);
      await controllerOn(lan, first).playTracks([track('1')]);
      await controllerOn(lan, first).save();

      // Reopened somewhere else entirely — off the LAN, on cellular.
      final next = PlexifyAudioHandler();
      addTearDown(next.dispose);
      await controllerOn(
        remote,
        next,
        connectivity: const [ConnectivityResult.mobile],
      ).restore();

      // A stored URL would embed the old address and the old token and be
      // reliably dead by now — a queue that restores looking perfect and will
      // not play. Quality is decided fresh too, so this is a transcode.
      expect(next.queue.value.single.id, contains('82-1-2-3'));
      expect(next.queue.value.single.extras?['qualityDecision'], 'transcode');
    });

    test('never lands on top of something already playing', () async {
      // Written straight to the store rather than played first, because
      // `playTracks` saves — so playing the racing track would overwrite the
      // very session this is meant to race against, and the test would pass
      // whether the guard existed or not.
      await store.write(
        const SavedPlayback(
          tracks: [SavedTrack(ratingKey: '1', title: 'Old', partKey: '/p/1')],
          index: 0,
          position: Duration.zero,
        ),
      );

      // Seeded on the handler rather than through `playTracks`, which saves —
      // going through the controller would overwrite the stored session and
      // the test would pass whether the guard existed or not.
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);
      await handler.setQueueAndPlay(const [
        MediaItem(
          id: 'https://tower.example/9',
          title: 'Chosen',
          extras: {'ratingKey': '9'},
        ),
      ]);

      // A slow restore racing someone who has already tapped an album must
      // lose, or the app would swap what they chose for what they left.
      await controllerOn(lan, handler).restore();

      expect(handler.queue.value.single.extras?['ratingKey'], '9');
    });

    test(
      'an unreadable session opens with no queue rather than failing',
      () async {
        SharedPreferences.setMockInitialValues({
          'playback_last_session': 'not json',
        });
        final handler = PlexifyAudioHandler();
        addTearDown(handler.dispose);
        final controller = PlaybackController(
          handler: handler,
          client: clientFor(lan),
          store: PlaybackStateStore(await SharedPreferences.getInstance()),
          checkConnectivity: () async => const [ConnectivityResult.wifi],
        );

        await controller.restore();

        expect(handler.queue.value, isEmpty);
      },
    );
  });

  group('what a queue was started from', () {
    late AppDatabase db;
    late LibraryWriter writer;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('is recorded the moment playback starts', () async {
      writer = LibraryWriter(db);
      await writer.markStarted(
        const PlaybackSource(PlaybackSourceKind.playlist, 'pl'),
        DateTime.utc(2026, 8, 6),
      );

      // Not at the 90% scrobble mark, which is what `markPlayed` waits for.
      // Putting a playlist on and quitting two minutes later used to record
      // nothing at all, which is why the shelf sat on an album from half an
      // hour earlier.
      final rows = await db.select(db.playbackHistory).get();
      expect(rows.single.kind, 'playlist');
      expect(rows.single.ratingKey, 'pl');
    });

    test(
      'the same thing twice moves it up rather than listing it twice',
      () async {
        writer = LibraryWriter(db);
        const source = PlaybackSource(PlaybackSourceKind.album, 'alb');
        await writer.markStarted(source, DateTime.utc(2026, 8, 6));
        await writer.markStarted(source, DateTime.utc(2026, 8, 7));

        final rows = await db.select(db.playbackHistory).get();
        expect(rows, hasLength(1));
        expect(
          rows.single.startedAt,
          DateTime.utc(2026, 8, 7).millisecondsSinceEpoch ~/ 1000,
        );
      },
    );

    test(
      'an album and a playlist with the same key are different rows',
      () async {
        writer = LibraryWriter(db);
        await writer.markStarted(
          const PlaybackSource(PlaybackSourceKind.album, '7'),
          DateTime.utc(2026, 8, 6),
        );
        await writer.markStarted(
          const PlaybackSource(PlaybackSourceKind.playlist, '7'),
          DateTime.utc(2026, 8, 6),
        );

        // Plex numbers albums and playlists in the same space, so the kind has
        // to be part of the key or one would silently replace the other.
        expect(await db.select(db.playbackHistory).get(), hasLength(2));
      },
    );
  });

  group('PlaybackSource encoding', () {
    test('survives a round trip through MediaItem extras', () {
      const source = PlaybackSource(PlaybackSourceKind.playlist, 'pl-1');
      expect(PlaybackSource.decode(source.encode()), source);
    });

    test('a ratingKey containing the separator survives', () {
      // Plex keys are numeric today, but splitting on the last colon rather
      // than the first would silently truncate one that is not.
      const source = PlaybackSource(PlaybackSourceKind.album, 'a:b:c');
      expect(PlaybackSource.decode(source.encode()), source);
    });

    test('rubbish decodes to null rather than throwing', () {
      expect(PlaybackSource.decode('nonsense'), isNull);
      expect(PlaybackSource.decode('album:'), isNull);
      expect(PlaybackSource.decode(null), isNull);
      expect(PlaybackSource.decode(42), isNull);
    });
  });
}
