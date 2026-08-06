import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/audio/quality_policy.dart';
import 'package:plexify/core/audio/playback_handler.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/features/player/playback_controller.dart';

/// `setQueueAndPlay` is overridden away rather than exercised for real: it
/// drives just_audio's platform channel, which `flutter test` has none of.
/// What's under test here is everything upstream of that call — which URL
/// gets built for a track, and the transcode session bookkeeping around
/// it — not playback itself.
class _RecordingHandler extends PlexifyAudioHandler {
  final calls = <List<MediaItem>>[];

  @override
  Future<void> setQueueAndPlay(
    List<MediaItem> items, {
    int initialIndex = 0,
  }) async {
    calls.add(items);
    queue.add(items);
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex.clamp(0, items.length - 1)]);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lan = PlexServer(
    name: 'Tower',
    baseUrl: 'https://192-168-1-10.plex.direct:32400',
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

  late List<http.Request> requests;

  PlexClient clientFor(PlexServer server) {
    return PlexClient(
      server: server,
      identity: PlexIdentity.forTesting(),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', 200);
      }),
    );
  }

  /// A playable track with an implied source bitrate of [sourceKbps], over a
  /// fixed 180-second duration.
  PlexTrack track(String ratingKey, {int? sourceKbps}) {
    return PlexTrack(
      ratingKey: ratingKey,
      title: 'Track $ratingKey',
      index: 1,
      durationMs: 180000,
      album: 'Album',
      artist: 'Artist',
      partKey: '/library/parts/$ratingKey/file.flac',
      partSizeBytes: sourceKbps == null ? null : sourceKbps * 22500,
    );
  }

  setUp(() {
    requests = [];
  });

  test('direct-plays on the LAN, whatever connectivity reports', () async {
    final handler = _RecordingHandler();
    final controller = PlaybackController(
      handler: handler,
      client: clientFor(lan),
      checkConnectivity: () async => const [ConnectivityResult.mobile],
    );

    await controller.playTracks([track('1', sourceKbps: 1000)]);

    final item = handler.calls.single.single;
    expect(item.id, contains('/library/parts/1/file.flac'));
    expect(item.id, contains('X-Plex-Token=servertoken'));
    expect(item.extras?['qualityDecision'], 'directPlay');
    expect(item.extras?.containsKey('transcodeSession'), isFalse);
  });

  test('transcodes a lossless file over cellular when remote', () async {
    final handler = _RecordingHandler();
    final controller = PlaybackController(
      handler: handler,
      client: clientFor(remote),
      checkConnectivity: () async => const [ConnectivityResult.mobile],
    );

    await controller.playTracks([track('2', sourceKbps: 1000)]);

    final item = handler.calls.single.single;
    expect(item.id, contains('/music/:/transcode/universal/start.mp3'));
    expect(item.extras?['qualityDecision'], 'transcode');
    expect(item.extras?['transcodeSession'], isNotNull);
  });

  test('a copy already at the transcoder\'s own rate direct-plays even '
      'remote and on cellular', () async {
    final handler = _RecordingHandler();
    final controller = PlaybackController(
      handler: handler,
      client: clientFor(remote),
      checkConnectivity: () async => const [ConnectivityResult.mobile],
    );

    await controller.playTracks([track('3', sourceKbps: 190)]);

    final item = handler.calls.single.single;
    expect(item.extras?['qualityDecision'], 'directPlay');
  });

  group('the settings override', () {
    /// Deliberately the opposite of what each connection would choose on its
    /// own, so a result matching the override cannot also be the automatic
    /// answer.
    QualityDecision? contrarian({required bool unmetered}) =>
        unmetered ? QualityDecision.transcode : QualityDecision.directPlay;

    test('is asked about the connection actually in use', () async {
      final onWifi = _RecordingHandler();
      await PlaybackController(
        handler: onWifi,
        client: clientFor(lan),
        qualityOverride: contrarian,
        checkConnectivity: () async => const [ConnectivityResult.wifi],
      ).playTracks([track('1', sourceKbps: 1000)]);

      final onMobile = _RecordingHandler();
      await PlaybackController(
        handler: onMobile,
        client: clientFor(remote),
        qualityOverride: contrarian,
        checkConnectivity: () async => const [ConnectivityResult.mobile],
      ).playTracks([track('2', sourceKbps: 1000)]);

      // Swap the two overrides and both of these still produce a valid-looking
      // URL, because each is the *automatic* answer for its connection. The
      // user-visible bug would be "save data on mobile" silently applying at
      // home and never applying on the train, which nothing else here would
      // catch.
      expect(
        onWifi.calls.single.single.extras?['qualityDecision'],
        'transcode',
      );
      expect(
        onMobile.calls.single.single.extras?['qualityDecision'],
        'directPlay',
      );
    });

    test('beats the source-rate floor, which nothing else does', () async {
      final handler = _RecordingHandler();
      await PlaybackController(
        handler: handler,
        client: clientFor(remote),
        qualityOverride: ({required bool unmetered}) =>
            QualityDecision.transcode,
        checkConnectivity: () async => const [ConnectivityResult.mobile],
      ).playTracks([track('4', sourceKbps: 190)]);

      // A 190kbps source is below the floor, so every automatic path returns
      // directPlay. An override that could be quietly overruled by one of the
      // signals it is meant to replace would be a setting that appears to do
      // nothing on exactly the tracks someone is trying to economise on.
      expect(
        handler.calls.single.single.extras?['qualityDecision'],
        'transcode',
      );
    });
  });

  test(
    'replacing the queue stops the previous batch\'s transcode sessions',
    () async {
      var sessionCount = 0;
      final handler = _RecordingHandler();
      final controller = PlaybackController(
        handler: handler,
        client: clientFor(remote),
        checkConnectivity: () async => const [ConnectivityResult.mobile],
        newSession: () => 'session-${++sessionCount}',
      );

      await controller.playTracks([track('4', sourceKbps: 1000)]);
      final firstSession =
          handler.calls.first.single.extras?['transcodeSession'] as String;

      await controller.playTracks([track('5', sourceKbps: 1000)]);
      // The stops are fired and forgotten *after* the new queue is loaded, so
      // the old transcode outlives the gap rather than the new track waiting
      // on a teardown. Give them the turn that ordering costs.
      await Future<void>.delayed(Duration.zero);

      final stopRequests = requests.where(
        (r) => r.url.path.endsWith('/transcode/universal/stop'),
      );
      expect(
        stopRequests.map((r) => r.url.queryParameters['session']),
        contains(firstSession),
      );
    },
  );

  test('disposeSessions stops whatever is still open', () async {
    var sessionCount = 0;
    final handler = _RecordingHandler();
    final controller = PlaybackController(
      handler: handler,
      client: clientFor(remote),
      checkConnectivity: () async => const [ConnectivityResult.mobile],
      newSession: () => 'session-${++sessionCount}',
    );

    await controller.playTracks([track('6', sourceKbps: 1000)]);
    final session =
        handler.calls.single.single.extras?['transcodeSession'] as String;

    controller.disposeSessions();
    // stopTranscodeSession fires and forgets; give it a turn to run.
    await Future<void>.delayed(Duration.zero);

    final stopRequests = requests.where(
      (r) => r.url.path.endsWith('/transcode/universal/stop'),
    );
    expect(
      stopRequests.map((r) => r.url.queryParameters['session']),
      contains(session),
    );
  });

  group('seeking a transcode', () {
    test('rebuilds the URL at an offset, reusing the same session', () async {
      final handler = _RecordingHandler();
      final controller = PlaybackController(
        handler: handler,
        client: clientFor(remote),
        checkConnectivity: () async => const [ConnectivityResult.mobile],
        newSession: () => 'session-1',
      );

      await controller.playTracks([track('9', sourceKbps: 1000)]);
      final item = handler.mediaItem.value!;

      final url = await handler.resolveSeekUrl!(
        item,
        const Duration(seconds: 90),
      );

      // Plex has no Range support here, so `offset` is the only handle on the
      // middle of a track — and the session must not change, or the server is
      // left transcoding the abandoned one.
      final query = Uri.parse(url!).queryParameters;
      expect(query['offset'], '90');
      expect(query['session'], 'session-1');
      expect(query['path'], '/library/metadata/9');
    });

    test('has no seek URL for a direct-played track', () async {
      final handler = _RecordingHandler();
      final controller = PlaybackController(
        handler: handler,
        client: clientFor(lan),
        checkConnectivity: () async => const [ConnectivityResult.wifi],
      );

      await controller.playTracks([track('10', sourceKbps: 1000)]);
      final item = handler.mediaItem.value!;

      // Null is what tells the handler to fall through to an ordinary seek,
      // which is what a static file supports and wants.
      expect(
        await handler.resolveSeekUrl!(item, const Duration(seconds: 90)),
        isNull,
      );
    });

    test('stops rebuilding URLs once the connection is gone', () async {
      final handler = _RecordingHandler();
      final controller = PlaybackController(
        handler: handler,
        client: clientFor(remote),
        checkConnectivity: () async => const [ConnectivityResult.mobile],
      );

      expect(handler.resolveSeekUrl, isNotNull);
      controller.disposeSessions();

      // Left behind, it would rebuild URLs against a server this app is no
      // longer signed in to.
      expect(handler.resolveSeekUrl, isNull);
    });
  });

  test('remaps startIndex when earlier tracks are unplayable', () async {
    final handler = _RecordingHandler();
    final controller = PlaybackController(
      handler: handler,
      client: clientFor(lan),
      checkConnectivity: () async => const [ConnectivityResult.wifi],
    );

    final unplayable = PlexTrack(
      ratingKey: 'x',
      title: 'Orphaned',
      index: 1,
      durationMs: 1000,
      album: 'Album',
      artist: 'Artist',
    );

    await controller.playTracks([
      unplayable,
      track('7'),
      track('8'),
    ], startIndex: 2);

    final items = handler.calls.single;
    expect(items, hasLength(2));
    expect(handler.mediaItem.value?.extras?['ratingKey'], '8');
  });
}
