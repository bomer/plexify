import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/audio/playback_handler.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/features/player/playback_controller.dart';

import 'support/fake_just_audio.dart';

/// Walking out of the house is the case this exists for, and it used to look
/// like the app breaking: the song stops, skipping forward finds another dead
/// track, and another, until something rebuilds the queue from scratch.
///
/// The cause is that a queue is a list of URLs fixed at the moment it was
/// built, each embedding the server address that was live then — and the whole
/// list is handed to the engine up front, so *every* track dies at once, not
/// just the one playing.
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
  late List<http.Request> requests;

  setUp(() {
    audio = FakeJustAudio.install();
    requests = [];
  });

  PlexClient clientFor(PlexServer server) => PlexClient(
    server: server,
    identity: PlexIdentity.forTesting(),
    httpClient: MockClient((request) async {
      requests.add(request);
      return http.Response('', 200);
    }),
  );

  PlexTrack track(String ratingKey, {int? sourceKbps = 1000}) => PlexTrack(
    ratingKey: ratingKey,
    title: 'Track $ratingKey',
    index: 1,
    durationMs: 180000,
    album: 'Album',
    artist: 'Artist',
    partKey: '/library/parts/$ratingKey/file.flac',
    partSizeBytes: sourceKbps == null ? null : sourceKbps * 22500,
  );

  /// Plays [tracks] on the LAN, then hands back a handler and a controller
  /// built against [server] — the connection the app has just re-resolved to.
  Future<PlaybackController> afterMovingTo(
    PlexServer server, {
    required PlexifyAudioHandler handler,
    required List<PlexTrack> tracks,
    List<ConnectivityResult> connectivity = const [ConnectivityResult.mobile],
  }) async {
    final before = PlaybackController(
      handler: handler,
      client: clientFor(lan),
      checkConnectivity: () async => const [ConnectivityResult.wifi],
    );
    await before.playTracks(tracks);

    return PlaybackController(
      handler: handler,
      client: clientFor(server),
      checkConnectivity: () async => connectivity,
      newSession: () => 'session-new',
    );
  }

  test(
    'every track in the queue moves to the new address, not just one',
    () async {
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);

      final after = await afterMovingTo(
        remote,
        handler: handler,
        tracks: [track('1'), track('2'), track('3')],
      );
      expect(
        audio.player.loadedUris.every((u) => u.contains('192-168-0-2')),
        isTrue,
      );

      await after.resumeOnNewConnection();

      // The whole list, because the whole list was handed to the engine up front
      // — leaving the later ones would mean skipping forward still failed, which
      // is exactly the symptom being fixed.
      expect(audio.player.loadedUris, hasLength(3));
      expect(
        audio.player.loadedUris.every((u) => u.contains('82-1-2-3')),
        isTrue,
      );
    },
  );

  test(
    'quality is decided again for the connection that replaced it',
    () async {
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);

      final after = await afterMovingTo(
        remote,
        handler: handler,
        tracks: [track('1')],
      );
      expect(
        handler.queue.value.single.extras?['qualityDecision'],
        'directPlay',
      );

      await after.resumeOnNewConnection();

      // The address changed because the network did. A direct-play FLAC was the
      // right call on the LAN and is the wrong one on the cellular connection
      // that replaced it.
      expect(
        handler.queue.value.single.extras?['qualityDecision'],
        'transcode',
      );
      expect(
        audio.player.loadedUris.single,
        contains('/music/:/transcode/universal/start.mp3'),
      );
    },
  );

  test('playback carries on from where it stopped', () async {
    final handler = PlexifyAudioHandler();
    addTearDown(handler.dispose);

    final after = await afterMovingTo(
      lan,
      handler: handler,
      tracks: [track('1'), track('2')],
      connectivity: const [ConnectivityResult.wifi],
    );
    await handler.skipToNext();
    await handler.seek(const Duration(seconds: 45));

    await after.resumeOnNewConnection();

    // Same track, same place. Restarting the album from the top would be a
    // different kind of broken.
    expect(handler.currentIndex, 1);
    expect(handler.queue.value[1].extras?['ratingKey'], '2');
    expect(audio.player.position.inSeconds, 45);
  });

  test('a transcode resumes at an offset rather than a seek', () async {
    final handler = PlexifyAudioHandler();
    addTearDown(handler.dispose);

    final after = await afterMovingTo(
      remote,
      handler: handler,
      tracks: [track('1')],
    );
    await handler.seek(const Duration(seconds: 45));

    await after.resumeOnNewConnection();

    // The rebuilt track is a transcode now, and a transcode cannot be seeked —
    // it has to arrive already at the right place.
    expect(audio.player.loadedUris.single, contains('offset=45'));
    expect(handler.position.inSeconds, 45);
  });

  test('a paused queue does not start itself playing', () async {
    final handler = PlexifyAudioHandler();
    addTearDown(handler.dispose);

    final after = await afterMovingTo(
      remote,
      handler: handler,
      tracks: [track('1')],
    );
    await handler.pause();

    await after.resumeOnNewConnection();

    // Someone who deliberately paused should not have a reconnect override
    // them — least of all on cellular.
    expect(audio.player.playing, isFalse);
  });

  test('rebuilding needs neither the network nor the database', () async {
    final handler = PlexifyAudioHandler();
    addTearDown(handler.dispose);

    final after = await afterMovingTo(
      remote,
      handler: handler,
      tracks: [track('1'), track('2')],
    );
    requests.clear();

    await after.resumeOnNewConnection();

    // Everything a rebuild needs rides on the MediaItem, because this runs at
    // the moment the connection has just failed — the worst time to need a
    // round trip to answer what the queue already knew. The only requests
    // allowed are the teardown of the old transcode sessions.
    final lookups = requests.where(
      (r) => !r.url.path.endsWith('/transcode/universal/stop'),
    );
    expect(lookups, isEmpty);
  });

  test('nothing happens when there is no queue to rescue', () async {
    final handler = PlexifyAudioHandler();
    addTearDown(handler.dispose);

    final controller = PlaybackController(
      handler: handler,
      client: clientFor(remote),
      checkConnectivity: () async => const [ConnectivityResult.mobile],
    );

    // The provider that calls this also builds at startup, when there is
    // nothing loaded. It must not construct an empty queue or throw.
    await controller.resumeOnNewConnection();

    expect(handler.queue.value, isEmpty);
    expect(audio.players, isEmpty);
  });

  test(
    'a failed track tells the connection monitor, since nothing else can',
    () async {
      final handler = PlexifyAudioHandler();
      addTearDown(handler.dispose);

      var failures = 0;
      handler.onPlaybackFailed = () => failures++;

      await handler.setQueueAndPlay([
        MediaItem(
          id: 'https://192-168-0-2.plex.direct:32400/dead',
          title: 'Dead',
        ),
      ]);
      audio.player.fail();
      await Future<void>.delayed(Duration.zero);

      // The engine does its own HTTP, so a queue full of dead URLs never reaches
      // ConnectionHealth. Without this the reconnect waits on the 30-second poll
      // to notice what the user noticed immediately.
      expect(failures, 1);
    },
  );

  test('an unreachable track does not freeze the media session', () async {
    final handler = PlexifyAudioHandler();
    addTearDown(handler.dispose);

    await handler.setQueueAndPlay([
      MediaItem(
        id: 'https://192-168-0-2.plex.direct:32400/dead',
        title: 'Dead',
      ),
    ]);
    audio.player.fail();
    await Future<void>.delayed(Duration.zero);

    // `pipe` is `addStream`: an error reaching playbackState ends the
    // subscription for good, and the transport would stay frozen long after
    // the connection came back.
    expect(handler.playbackState.isClosed, isFalse);
    await handler.setQueueAndPlay([
      MediaItem(id: 'https://82-1-2-3.plex.direct:32400/alive', title: 'Alive'),
    ]);
    expect(handler.mediaItem.value?.title, 'Alive');
  });
}
