import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/core/plex/transcode.dart';
import 'package:plexify/core/plex/transcode_probe.dart';

/// The transcode endpoint is the least-documented thing Plexify depends on, and
/// every way it can fail is quiet: it answers 200, the audio plays, and the
/// consequence — no caching, no seeking, a bitrate cap that does nothing —
/// only shows up as a data bill. These are the servers that fail that way.
void main() {
  const trackDuration = Duration(minutes: 4);

  final track = PlexTrack(
    ratingKey: '9001',
    title: 'A Track',
    index: 1,
    durationMs: trackDuration.inMilliseconds,
    album: 'An Album',
    artist: 'An Artist',
    container: 'flac',
    partKey: '/library/parts/1/2/file.flac',
  );

  /// Bytes a CBR stream of [kbps] would occupy over the track's duration. The
  /// probe infers the rate from the declared size, so this is what makes a
  /// server "honour" a parameter.
  int bytesFor(int kbps) => kbps * 1000 ~/ 8 * trackDuration.inSeconds;

  late List<Uri> requests;

  /// A server that behaves. Each named argument turns one behaviour off.
  MockClient server({
    bool hls = false,
    bool redirectToHls = false,
    bool honourRange = true,
    bool declareSize = true,
    Set<String> honouredBitrateParameters = const {'musicBitrate'},
    int defaultKbps = 320,
  }) {
    return MockClient((request) async {
      requests.add(request.url);

      if (request.url.path.endsWith('/stop')) {
        return http.Response('', 200);
      }

      if (redirectToHls) {
        return http.Response(
          '',
          302,
          headers: {'location': 'start.m3u8?session=x'},
        );
      }

      if (hls || request.url.path.endsWith('.m3u8')) {
        return http.Response(
          '#EXTM3U\n#EXT-X-VERSION:3\n',
          200,
          headers: {'content-type': 'application/vnd.apple.mpegurl'},
        );
      }

      var kbps = defaultKbps;
      for (final name in honouredBitrateParameters) {
        final asked = request.url.queryParameters[name];
        if (asked != null) kbps = int.parse(asked);
      }

      final total = bytesFor(kbps);
      // 256 KB of body, so a probe that ignores its own read cap would still
      // only be reading a window — the cap is asserted separately.
      final body = Uint8List(256 * 1024);

      return http.Response.bytes(
        body,
        honourRange ? 206 : 200,
        headers: {
          'content-type': 'audio/mpeg',
          if (honourRange && declareSize)
            'content-range': 'bytes 0-${body.length - 1}/$total',
          if (!honourRange && declareSize) 'content-length': '$total',
        },
      );
    });
  }

  TranscodeProbe probeAgainst(MockClient http_) {
    var n = 0;
    return TranscodeProbe(
      client: PlexClient(
        server: const PlexServer(
          name: 'Tower',
          baseUrl: 'https://tower.example:32400',
          token: 'sekrit',
          isLocal: true,
          isRelay: false,
        ),
        identity: PlexIdentity.forTesting(),
        httpClient: http_,
      ),
      httpClient: http_,
      newSession: () => 'session-${n++}',
    );
  }

  setUp(() => requests = []);

  ProbeCheck check(TranscodeProbeReport report, String startsWith) =>
      report.checks.firstWhere((c) => c.question.startsWith(startsWith));

  List<Uri> transcodeRequests() =>
      requests.where((u) => u.path.contains('universal/start')).toList();

  group('the URL', () {
    test('forces a transcode instead of asking for one', () async {
      await probeAgainst(server()).run(track);

      final q = transcodeRequests().first.queryParameters;
      // Without these Plex is free to decide the original is fine and hand
      // back the source file — so a bitrate cap appears to work while doing
      // nothing at all.
      expect(q['directPlay'], '0');
      expect(q['directStream'], '0');
      expect(q['path'], '/library/metadata/9001');
      expect(q['protocol'], 'http');
    });

    test('asks for the progressive form, not HLS', () async {
      await probeAgainst(server()).run(track);

      // LockCachingAudioSource caches progressive HTTP only. Asking for
      // start.m3u8 would make transcoded playback permanently uncacheable.
      expect(transcodeRequests().first.path, endsWith('start.mp3'));
    });

    test('carries credentials in the query string', () async {
      await probeAgainst(server()).run(track);

      // The audio engine does its own HTTP and carries none of our headers.
      final q = transcodeRequests().first.queryParameters;
      expect(q['X-Plex-Token'], 'sekrit');
      expect(q['X-Plex-Client-Identifier'], 'test-client-id');
      expect(q['session'], isNotEmpty);
    });

    test('names whichever bitrate parameter it was given', () {
      final client = PlexClient(
        server: const PlexServer(
          name: 'Tower',
          baseUrl: 'https://tower.example:32400',
          token: 'sekrit',
          isLocal: true,
          isRelay: false,
        ),
        identity: PlexIdentity.forTesting(),
      );

      final url = Uri.parse(
        client.transcodeUrl(
          '1',
          session: 's',
          bitrateKbps: 128,
          bitrateParameter: TranscodeBitrateParameter.maxAudioBitrate,
        ),
      );

      expect(url.queryParameters['maxAudioBitrate'], '128');
      expect(url.queryParameters.containsKey('musicBitrate'), isFalse);
    });
  });

  group('reading a healthy server', () {
    test('everything passes', () async {
      final report = await probeAgainst(server()).run(track);

      expect(
        report.checks.where((c) => c.outcome != ProbeOutcome.pass),
        isEmpty,
        reason: report.toText(),
      );
      expect(report.allPassed, isTrue);
    });

    test('the report never carries the token', () async {
      final report = await probeAgainst(server()).run(track);

      // The report exists to be pasted into a document or a chat window.
      expect(report.toText(), isNot(contains('sekrit')));
      expect(report.exampleUrl, contains('REDACTED'));
    });
  });

  group('a server that answers with HLS', () {
    test('is caught when it says so in the content type', () async {
      final report = await probeAgainst(server(hls: true)).run(track);

      final progressive = check(report, 'Is it progressive');
      expect(progressive.outcome, ProbeOutcome.fail);
      expect(progressive.detail, contains('cannot cache'));
    });

    test('is caught when it redirects there instead', () async {
      final report = await probeAgainst(server(redirectToHls: true)).run(track);

      // A client that followed redirects automatically would see a 200 with
      // audio and call this a pass, which is exactly the quiet failure the
      // spike exists to rule out.
      expect(check(report, 'Is it progressive').outcome, ProbeOutcome.fail);
    });
  });

  group('a server that ignores Range', () {
    test('fails the range check', () async {
      final report = await probeAgainst(server(honourRange: false)).run(track);

      final range = check(report, 'Does it honour Range');
      expect(range.outcome, ProbeOutcome.fail);
      // Seeking restarts the transcode from zero without it.
      expect(range.detail, contains('206'));
    });

    test('is still only read up to the window', () async {
      // Reading a whole transcode to find out Range was ignored would download
      // the entire track over the cellular link being measured.
      final report = await probeAgainst(server(honourRange: false)).run(track);

      expect(
        check(report, 'Does the progressive endpoint answer').detail,
        contains('${64 * 1024} bytes'),
      );
    });
  });

  test('a server that declares no size fails the size check', () async {
    final report = await probeAgainst(server(declareSize: false)).run(track);

    final size = check(report, 'Does it declare the total size');
    expect(size.outcome, ProbeOutcome.fail);
    // Without it the cache cannot tell a complete file from a truncated one.
    expect(size.detail, contains('truncated'));
  });

  group('which bitrate parameter is honoured', () {
    test('is named when only musicBitrate works', () async {
      final report = await probeAgainst(
        server(honouredBitrateParameters: {'musicBitrate'}),
      ).run(track);

      final bitrate = check(report, 'Which bitrate parameter');
      expect(bitrate.outcome, ProbeOutcome.pass);
      expect(bitrate.detail, contains('Honoured: musicBitrate.'));
    });

    test('is named when only maxAudioBitrate works', () async {
      final report = await probeAgainst(
        server(honouredBitrateParameters: {'maxAudioBitrate'}),
      ).run(track);

      final bitrate = check(report, 'Which bitrate parameter');
      expect(bitrate.outcome, ProbeOutcome.pass);
      expect(bitrate.detail, contains('Honoured: maxAudioBitrate.'));
    });

    test('reports both when both work', () async {
      final report = await probeAgainst(
        server(honouredBitrateParameters: {'musicBitrate', 'maxAudioBitrate'}),
      ).run(track);

      expect(
        check(report, 'Which bitrate parameter').detail,
        contains('Honoured: musicBitrate and maxAudioBitrate.'),
      );
    });

    test('is a failure when neither changes anything', () async {
      final report = await probeAgainst(
        server(honouredBitrateParameters: const {}),
      ).run(track);

      final bitrate = check(report, 'Which bitrate parameter');
      // This is the case that makes cellular listening expensive: the app
      // believes it asked for 128k and the server sends the full rate.
      expect(bitrate.outcome, ProbeOutcome.fail);
      expect(bitrate.detail, contains('Neither parameter'));
    });

    test('is not guessed at when the endpoint returned no audio', () async {
      final report = await probeAgainst(server(hls: true)).run(track);

      expect(
        check(report, 'Which bitrate parameter').outcome,
        ProbeOutcome.unknown,
      );
      // Comparing the sizes of two error pages would produce a confident
      // answer to a question that was never asked.
      expect(
        transcodeRequests().where((u) => u.path.endsWith('start.mp3')),
        hasLength(1),
      );
    });
  });

  group('transcode sessions', () {
    test('every session the probe opens is stopped again', () async {
      final report = await probeAgainst(server()).run(track);

      final opened = transcodeRequests()
          .map((u) => u.queryParameters['session'])
          .toSet();
      final stopped = requests
          .where((u) => u.path.endsWith('/stop'))
          .map((u) => u.queryParameters['session'])
          .toSet();

      // Abandoned sessions keep the server transcoding into a buffer nobody
      // reads — several at once is the difference between an idle NAS and a
      // pegged one.
      expect(opened, isNotEmpty);
      expect(stopped, opened);
      expect(
        check(report, 'Can the transcode session').outcome,
        ProbeOutcome.pass,
      );
    });

    test('are still stopped when the endpoint failed outright', () async {
      final report = await probeAgainst(
        MockClient((request) async {
          requests.add(request.url);
          if (request.url.path.endsWith('/stop')) {
            return http.Response('', 200);
          }
          return http.Response('Not found', 404);
        }),
      ).run(track);

      expect(requests.where((u) => u.path.endsWith('/stop')), isNotEmpty);
      expect(
        check(report, 'Does the progressive endpoint answer').outcome,
        ProbeOutcome.fail,
      );
    });
  });

  test('a server that cannot be reached is reported, not thrown', () async {
    final report = await probeAgainst(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/stop')) {
          return http.Response('', 200);
        }
        throw http.ClientException('Connection refused');
      }),
    ).run(track);

    // The probe runs from a car park on a flaky connection. A thrown
    // exception there tells you nothing about which check it died on.
    expect(
      check(report, 'Does the progressive endpoint answer').detail,
      contains('Connection refused'),
    );
    expect(report.allPassed, isFalse);
  });
}
