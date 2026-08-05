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
    bool honourOffset = true,
    bool declareSize = true,
    Set<String> honouredBitrateParameters = const {'musicBitrate'},
    Set<String> requiredParameters = const {},
    int defaultKbps = 320,
  }) {
    return MockClient((request) async {
      requests.add(request.url);

      if (request.url.path.endsWith('/stop')) {
        return http.Response('', 200);
      }

      // Plex rejects a request it cannot form a transcode decision from, and
      // says nothing about which parameter was missing.
      final missing = requiredParameters.where(
        (p) => !request.url.queryParameters.containsKey(p),
      );
      if (missing.isNotEmpty) {
        return http.Response(
          '<html><head><title>Bad Request</title></head><body>'
          '<h1>400 Bad Request</h1></body></html>',
          400,
          headers: {'content-type': 'text/html'},
        );
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
      final offset = int.parse(request.url.queryParameters['offset'] ?? '0');

      // A live transcode is generated from the offset onwards, so asking for
      // the tail yields a short stream. A server that ignores offset sends the
      // whole thing instead — far past the probe's cap.
      final body = offset > 0 && honourOffset
          ? Uint8List(kbps * 1000 ~/ 8 * (trackDuration.inSeconds - offset))
          // 256 KB, so a probe that ignored its own read cap would still only
          // be reading a window. The cap is asserted separately.
          : Uint8List(offset > 0 ? 2 * 1024 * 1024 : 256 * 1024);

      // 206 only in answer to a Range request, as a real server would.
      final ranged = honourRange && request.headers.containsKey('Range');

      return http.Response.bytes(
        body,
        ranged ? 206 : 200,
        headers: {
          'content-type': 'audio/mpeg',
          if (ranged && declareSize)
            'content-range': 'bytes 0-${body.length - 1}/$total',
          if (!ranged && declareSize) 'content-length': '$total',
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

  group('measuring by asking for the tail', () {
    test(
      'offset shortening the stream is reported as its own finding',
      () async {
        final report = await probeAgainst(server()).run(track);

        final offset = check(report, 'Does offset shorten');
        expect(offset.outcome, ProbeOutcome.pass);
      },
    );

    test(
      'a server that ignores offset is caught, and stops the measurement',
      () async {
        final report = await probeAgainst(
          server(honourOffset: false),
        ).run(track);

        // Without Range, offset is the only way to seek — and if it does not
        // shorten the stream, the bytes describe the start of the track rather
        // than the window asked for, so any bitrate read off them is fiction.
        expect(check(report, 'Does offset shorten').outcome, ProbeOutcome.fail);
        expect(
          check(report, 'Which bitrate parameter').outcome,
          ProbeOutcome.unknown,
        );
      },
    );

    test(
      'the tail read gives up rather than downloading a whole track',
      () async {
        final report = await probeAgainst(
          server(honourOffset: false),
        ).run(track);

        // The server offers 2 MB. Reading it to the end would be the whole
        // track over the cellular link this exists to measure.
        expect(
          check(report, 'Does offset shorten').detail,
          contains('${1024 * 1024} bytes without reaching the end'),
        );
      },
    );

    test(
      'a bitrate is measured even when the server declares no size',
      () async {
        // Which is the real case: a live transcode has no length to declare.
        final report = await probeAgainst(
          server(declareSize: false),
        ).run(track);

        final bitrate = check(report, 'Which bitrate parameter');
        expect(bitrate.outcome, ProbeOutcome.pass);
        expect(bitrate.detail, contains('Honoured: musicBitrate.'));
      },
    );
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
      // answer to a question that was never asked: nothing beyond the
      // candidate sweep should have been requested.
      expect(
        transcodeRequests().where((u) => u.path.endsWith('start.mp3')),
        hasLength(TranscodeProfile.candidates.length),
      );
    });
  });

  group('finding the parameter set the server accepts', () {
    test('names the leanest one that works', () async {
      final report = await probeAgainst(server()).run(track);

      final accepted = check(report, 'Which parameter set');
      expect(accepted.outcome, ProbeOutcome.pass);
      expect(accepted.detail, contains('Leanest that works: minimal'));
    });

    test('walks past the ones the server rejects', () async {
      // A server that will not decide without knowing who is asking — which
      // it cannot learn from headers, because the audio engine sends none.
      final report = await probeAgainst(
        server(requiredParameters: {'X-Plex-Product'}),
      ).run(track);

      final accepted = check(report, 'Which parameter set');
      expect(accepted.outcome, ProbeOutcome.pass);
      expect(accepted.detail, contains('Leanest that works: identified'));
      // The rejections are the finding, not noise: each one names a parameter
      // the server turned out to need.
      expect(accepted.detail, contains('minimal: HTTP 400'));
      expect(report.workingProfile, 'identified');
    });

    test('reports every candidate, not just the winner', () async {
      final report = await probeAgainst(server()).run(track);

      final accepted = check(report, 'Which parameter set');
      for (final profile in TranscodeProfile.candidates) {
        // A leaner profile that also worked names parameters never needed.
        expect(accepted.detail, contains(profile.name));
      }
    });

    test('says so plainly when nothing works', () async {
      final report = await probeAgainst(
        server(requiredParameters: {'nothing-sends-this'}),
      ).run(track);

      final accepted = check(report, 'Which parameter set');
      expect(accepted.outcome, ProbeOutcome.fail);
      expect(accepted.detail, contains('None of them'));
      expect(report.workingProfile, isNull);
    });

    test(
      'carries the rejection body, which is where the reason lives',
      () async {
        final report = await probeAgainst(
          server(requiredParameters: {'nothing-sends-this'}),
        ).run(track);

        expect(
          check(report, 'Does the progressive endpoint answer').detail,
          contains('400 Bad Request'),
        );
      },
    );
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
