import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'plex_client.dart';
import 'plex_models.dart';
import 'transcode.dart';

/// Answers the questions in task #8 by measuring a real server.
///
/// `/music/:/transcode/universal/start` is the least-documented endpoint this
/// app depends on, and every claim about it that matters is a claim about
/// *behaviour*, not shape: whether it hands back audio or redirects into HLS,
/// whether it honours Range, whether it declares a length, and which of two
/// undocumented bitrate parameters actually does anything. None of those can be
/// settled by reading, so this settles them by asking.
///
/// It is kept in the app rather than written as a script because the answers
/// differ by route — LAN, remote, and relay are three different servers as far
/// as this endpoint is concerned — and only the app can be carried out of the
/// house onto cellular.
class TranscodeProbe {
  TranscodeProbe({
    required PlexClient client,
    http.Client? httpClient,
    String Function()? newSession,
  }) : _client = client,
       _http = httpClient ?? http.Client(),
       _newSession = newSession ?? (() => const Uuid().v4());

  final PlexClient _client;
  final http.Client _http;
  final String Function() _newSession;

  /// How much of each response to actually read.
  ///
  /// Enough to sniff the content and prove bytes flow, small enough that four
  /// runs cost nothing on a metered connection — which is exactly where this
  /// gets run.
  static const _windowBytes = 64 * 1024;

  /// Requested bitrates. The pair has to be far apart for the comparison to
  /// mean anything: two nearby values could differ by container overhead alone.
  static const _highKbps = 320;
  static const _lowKbps = 128;

  /// How far the measured bitrate may sit from the requested one before the
  /// parameter counts as ignored. MP3 framing and tags put the real figure a
  /// few percent above the nominal rate.
  static const _tolerance = 0.15;

  Future<TranscodeProbeReport> run(PlexTrack track) async {
    final checks = <ProbeCheck>[];
    final sessions = <String>[];

    // Which parameters the endpoint requires is the first unknown, and every
    // later question is meaningless until it is settled — measuring the
    // bitrate of a 400 page proves nothing.
    final tried = <TranscodeProfile, _Attempt>{};
    for (final profile in TranscodeProfile.candidates) {
      final attempt = await _attempt(
        track,
        profile,
        TranscodeBitrateParameter.musicBitrate,
        _highKbps,
        sessions,
      );
      tried[profile] = attempt;
      // Deliberately does not stop at the first success: knowing that a leaner
      // profile also works is what says which parameters were never needed.
    }

    final winner = tried.entries
        .where((e) => e.value.looksLikeAudio)
        .firstOrNull;

    checks.add(_acceptedProfile(tried));

    final high = winner?.value ?? tried.values.first;
    checks.add(_answersWithAudio(high));
    checks.add(_staysProgressive(high));
    checks.add(_honoursRange(high));
    checks.add(_declaresLength(high, track));

    if (winner != null) {
      final musicLow = await _attempt(
        track,
        winner.key,
        TranscodeBitrateParameter.musicBitrate,
        _lowKbps,
        sessions,
      );
      final maxAudioLow = await _attempt(
        track,
        winner.key,
        TranscodeBitrateParameter.maxAudioBitrate,
        _lowKbps,
        sessions,
      );
      checks.add(_bitrateParameter(track, high, musicLow, maxAudioLow));
    } else {
      checks.add(
        const ProbeCheck(
          'Which bitrate parameter does Plex honour?',
          ProbeOutcome.unknown,
          'Not measured — no parameter set returned audio.',
        ),
      );
    }

    checks.add(
      await _sessionsCanBeStopped(sessions, anyStarted: winner != null),
    );

    return TranscodeProbeReport(
      track: track,
      route: _client.server.isRelay
          ? 'Relay'
          : _client.server.isLocal
          ? 'Local'
          : 'Remote',
      serverUrl: _client.server.baseUrl,
      exampleUrl: _redact(high.url),
      workingProfile: winner?.key.name,
      checks: checks,
    );
  }

  /// The finding the rest of the spike depends on.
  ///
  /// Reports every candidate rather than only the winner: a profile that was
  /// rejected names a parameter the server needed, and a leaner one that
  /// worked names parameters it never did.
  ProbeCheck _acceptedProfile(Map<TranscodeProfile, _Attempt> tried) {
    final lines = <String>[];
    for (final entry in tried.entries) {
      final a = entry.value;
      final verdict = a.looksLikeAudio
          ? 'accepted'
          : a.error != null
          ? 'unreachable (${a.error})'
          : 'HTTP ${a.status}${a.isHls ? ', HLS' : ''}';
      lines.add('  ${entry.key.name}: $verdict — ${entry.key.why}');
    }

    final accepted = tried.entries
        .where((e) => e.value.looksLikeAudio)
        .map((e) => e.key.name)
        .toList();

    return ProbeCheck(
      'Which parameter set does the server accept?',
      accepted.isEmpty ? ProbeOutcome.fail : ProbeOutcome.pass,
      '${accepted.isEmpty ? 'None of them.' : 'Leanest that works: ${accepted.first}.'}'
          '\n${lines.join('\n')}',
    );
  }

  // --- the individual questions -------------------------------------------

  ProbeCheck _answersWithAudio(_Attempt a) {
    if (a.error != null) {
      return ProbeCheck(
        'Does the progressive endpoint answer?',
        ProbeOutcome.fail,
        'Request failed: ${a.error}',
      );
    }
    if (a.status >= 400) {
      return ProbeCheck(
        'Does the progressive endpoint answer?',
        ProbeOutcome.fail,
        'HTTP ${a.status}. ${a.bodySniff}',
      );
    }
    if (a.receivedBytes == 0) {
      return ProbeCheck(
        'Does the progressive endpoint answer?',
        ProbeOutcome.fail,
        'HTTP ${a.status} but no bytes arrived.',
      );
    }
    return ProbeCheck(
      'Does the progressive endpoint answer?',
      a.looksLikeAudio ? ProbeOutcome.pass : ProbeOutcome.fail,
      'HTTP ${a.status}, ${a.contentType ?? 'no content-type'}, '
          '${a.receivedBytes} bytes in ${a.elapsed.inMilliseconds}ms.',
    );
  }

  ProbeCheck _staysProgressive(_Attempt a) {
    // The failure this guards against is silent: Plex answers 200, the audio
    // plays, and the only symptom is that caching never works — months later,
    // as an unexplained data bill.
    if (a.isHls) {
      return ProbeCheck(
        'Is it progressive rather than HLS?',
        ProbeOutcome.fail,
        'Served HLS${a.redirectedTo == null ? '' : ' via a redirect to '
                      '${_redact(a.redirectedTo!)}'}. '
            'LockCachingAudioSource cannot cache this, so transcoded playback '
            'would be uncacheable and #24 shrinks to LAN-only.',
      );
    }
    if (a.error != null || a.status >= 400) {
      return const ProbeCheck(
        'Is it progressive rather than HLS?',
        ProbeOutcome.unknown,
        'Not determined — the request did not succeed.',
      );
    }
    return ProbeCheck(
      'Is it progressive rather than HLS?',
      ProbeOutcome.pass,
      a.redirectedTo == null
          ? 'Answered directly, no redirect.'
          : 'Redirected to ${_redact(a.redirectedTo!)}, still progressive.',
    );
  }

  ProbeCheck _honoursRange(_Attempt a) {
    if (a.status == 206) {
      return ProbeCheck(
        'Does it honour Range requests?',
        ProbeOutcome.pass,
        'HTTP 206, content-range: ${a.contentRange}',
      );
    }
    if (a.status == 200) {
      // Seeking would restart the transcode from zero and caching a partial
      // file would be unresumable.
      return const ProbeCheck(
        'Does it honour Range requests?',
        ProbeOutcome.fail,
        'HTTP 200 for a ranged request — the whole stream was offered. '
            'Seeking and resumable caching both depend on 206.',
      );
    }
    return ProbeCheck(
      'Does it honour Range requests?',
      ProbeOutcome.unknown,
      'HTTP ${a.status}.',
    );
  }

  ProbeCheck _declaresLength(_Attempt a, PlexTrack track) {
    final total = a.totalBytes;
    if (total == null) {
      // A transcode is generated on the fly, so an unknown length is a real
      // possibility rather than a server misconfiguration.
      return const ProbeCheck(
        'Does it declare the total size?',
        ProbeOutcome.fail,
        'No content-length or content-range total. Without it the player '
            'cannot show a seekable duration and the cache cannot tell a '
            'complete file from a truncated one.',
      );
    }
    final kbps = _impliedKbps(total, track);
    return ProbeCheck(
      'Does it declare the total size?',
      ProbeOutcome.pass,
      '$total bytes${kbps == null ? '' : ' (~$kbps kbps)'}.',
    );
  }

  ProbeCheck _bitrateParameter(
    PlexTrack track,
    _Attempt high,
    _Attempt musicLow,
    _Attempt maxAudioLow,
  ) {
    final baseline = _impliedKbps(high.totalBytes, track);
    final music = _impliedKbps(musicLow.totalBytes, track);
    final maxAudio = _impliedKbps(maxAudioLow.totalBytes, track);

    if (baseline == null || music == null || maxAudio == null) {
      return ProbeCheck(
        'Which bitrate parameter does Plex honour?',
        ProbeOutcome.unknown,
        'Cannot measure without a declared size. '
            'musicBitrate=$_highKbps → ${_size(high)}, '
            'musicBitrate=$_lowKbps → ${_size(musicLow)}, '
            'maxAudioBitrate=$_lowKbps → ${_size(maxAudioLow)}.',
      );
    }

    final musicHonoured = _near(music, _lowKbps);
    final maxAudioHonoured = _near(maxAudio, _lowKbps);
    final baselineHonoured = _near(baseline, _highKbps);

    final honoured = [
      if (musicHonoured) 'musicBitrate',
      if (maxAudioHonoured) 'maxAudioBitrate',
    ];

    final detail =
        'musicBitrate=$_highKbps → ~$baseline kbps, '
        'musicBitrate=$_lowKbps → ~$music kbps, '
        'maxAudioBitrate=$_lowKbps → ~$maxAudio kbps. '
        '${honoured.isEmpty ? 'Neither parameter changed the output.' : 'Honoured: ${honoured.join(' and ')}.'}'
        '${baselineHonoured ? '' : ' Note: the $_highKbps request did not '
                  'measure near $_highKbps either, so the source may simply be '
                  'lower-rate than that.'}';

    return ProbeCheck(
      'Which bitrate parameter does Plex honour?',
      honoured.isEmpty ? ProbeOutcome.fail : ProbeOutcome.pass,
      detail,
    );
  }

  Future<ProbeCheck> _sessionsCanBeStopped(
    List<String> sessions, {
    required bool anyStarted,
  }) async {
    if (sessions.isEmpty) {
      return const ProbeCheck(
        'Can the transcode session be stopped?',
        ProbeOutcome.unknown,
        'No sessions were opened.',
      );
    }
    var stopped = 0;
    for (final session in sessions) {
      if (await _client.stopTranscodeSession(session)) stopped++;
    }

    // A session that never started cannot meaningfully be stopped, and calling
    // that a failure points at teardown when the actual fault is upstream.
    if (!anyStarted) {
      return ProbeCheck(
        'Can the transcode session be stopped?',
        ProbeOutcome.unknown,
        '$stopped of ${sessions.length} accepted the stop, but no transcode '
            'ever started — there was nothing to tear down.',
      );
    }

    return ProbeCheck(
      'Can the transcode session be stopped?',
      stopped == sessions.length ? ProbeOutcome.pass : ProbeOutcome.fail,
      '$stopped of ${sessions.length} sessions accepted the stop. '
          'Anything left over keeps the server transcoding into nothing.',
    );
  }

  // --- transport ------------------------------------------------------------

  Future<_Attempt> _attempt(
    PlexTrack track,
    TranscodeProfile profile,
    TranscodeBitrateParameter parameter,
    int kbps,
    List<String> sessions,
  ) async {
    final session = _newSession();
    sessions.add(session);

    final url = _client.transcodeUrl(
      track.ratingKey,
      session: session,
      bitrateKbps: kbps,
      bitrateParameter: parameter,
      profile: profile,
    );

    final first = await _fetch(url);
    // Redirects are followed by hand, once, because *where* it redirects is
    // itself an answer — an automatic follow would hide a hop into HLS.
    final location = first.redirectedTo;
    if (location == null) return first;

    final followed = await _fetch(Uri.parse(url).resolve(location).toString());
    return followed.copyWith(url: url, redirectedTo: location);
  }

  Future<_Attempt> _fetch(String url) async {
    final started = DateTime.now();
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = false
        ..headers['Range'] = 'bytes=0-${_windowBytes - 1}';

      final response = await _http.send(request);
      final bytes = await _take(response.stream, _windowBytes);

      return _Attempt(
        url: url,
        status: response.statusCode,
        headers: response.headers,
        redirectedTo: response.statusCode >= 300 && response.statusCode < 400
            ? response.headers['location']
            : null,
        receivedBytes: bytes.length,
        bodySniff: _sniff(bytes),
        elapsed: DateTime.now().difference(started),
      );
    } on Object catch (e) {
      return _Attempt(
        url: url,
        status: 0,
        headers: const {},
        receivedBytes: 0,
        bodySniff: '',
        elapsed: DateTime.now().difference(started),
        error: e,
      );
    }
  }

  /// Reads at most [max] bytes, then hangs up.
  ///
  /// The cap is load-bearing: if Range is ignored the server offers the entire
  /// transcode, and reading it to completion would download the whole track on
  /// the cellular connection this is meant to be measuring.
  static Future<List<int>> _take(Stream<List<int>> stream, int max) {
    final out = <int>[];
    final done = Completer<List<int>>();
    late StreamSubscription<List<int>> sub;

    sub = stream.listen(
      (chunk) {
        out.addAll(chunk);
        if (out.length >= max && !done.isCompleted) {
          done.complete(out.sublist(0, max));
          unawaited(sub.cancel());
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete(out);
      },
      onError: (Object e, StackTrace s) {
        if (!done.isCompleted) done.completeError(e, s);
      },
      cancelOnError: true,
    );

    return done.future;
  }

  // --- small helpers --------------------------------------------------------

  /// Bytes and a duration are enough to infer the rate, which avoids
  /// downloading a track three times to find out what changed.
  static int? _impliedKbps(int? totalBytes, PlexTrack track) {
    if (totalBytes == null || totalBytes <= 0) return null;
    if (track.durationMs <= 0) return null;
    return (totalBytes * 8 / (track.durationMs / 1000) / 1000).round();
  }

  static bool _near(int measured, int requested) =>
      (measured - requested).abs() <= requested * _tolerance;

  static String _size(_Attempt a) =>
      a.totalBytes == null ? 'no declared size' : '${a.totalBytes} bytes';

  /// A printable prefix of the body.
  ///
  /// Long enough to carry the reason out of an error page — the whole value of
  /// a rejection is *why* — and short enough not to paste a stylesheet into
  /// the report.
  static String _sniff(List<int> bytes) {
    final head = bytes
        .take(200)
        .map((b) => b >= 32 && b < 127 ? b : 46)
        .toList();
    return String.fromCharCodes(head);
  }

  /// Keeps tokens out of a report the whole point of which is to be pasted
  /// somewhere else.
  static String _redact(String url) =>
      url.replaceAll(RegExp(r'X-Plex-Token=[^&]*'), 'X-Plex-Token=REDACTED');
}

// --- results -----------------------------------------------------------------

enum ProbeOutcome { pass, fail, unknown }

class ProbeCheck {
  const ProbeCheck(this.question, this.outcome, this.detail);

  final String question;
  final ProbeOutcome outcome;
  final String detail;
}

class TranscodeProbeReport {
  const TranscodeProbeReport({
    required this.track,
    required this.route,
    required this.serverUrl,
    required this.exampleUrl,
    required this.checks,
    this.workingProfile,
  });

  final PlexTrack track;
  final String route;
  final String serverUrl;

  /// Name of the leanest [TranscodeProfile] the server accepted, or null if
  /// none did. This is the headline finding of the spike.
  final String? workingProfile;

  /// Token-free, so the report can be pasted anywhere.
  final String exampleUrl;

  final List<ProbeCheck> checks;

  bool get allPassed => checks.every((c) => c.outcome == ProbeOutcome.pass);

  /// The whole report as text.
  ///
  /// A spike that works but is not written down has to be redone, and the
  /// runs that matter happen on a phone in a car park.
  String toText() {
    final buffer = StringBuffer()
      ..writeln('Plexify transcode probe')
      ..writeln('Route:    $route ($serverUrl)')
      ..writeln(
        'Track:    ${track.artist} — ${track.title} '
        '[${track.container ?? 'unknown container'}, '
        '${(track.durationMs / 1000).round()}s]',
      )
      ..writeln('Profile:  ${workingProfile ?? 'none accepted'}')
      ..writeln('URL:      $exampleUrl')
      ..writeln();

    for (final check in checks) {
      final mark = switch (check.outcome) {
        ProbeOutcome.pass => 'PASS',
        ProbeOutcome.fail => 'FAIL',
        ProbeOutcome.unknown => '????',
      };
      buffer
        ..writeln('[$mark] ${check.question}')
        ..writeln('       ${check.detail}')
        ..writeln();
    }

    return buffer.toString();
  }
}

class _Attempt {
  const _Attempt({
    required this.url,
    required this.status,
    required this.headers,
    required this.receivedBytes,
    required this.bodySniff,
    required this.elapsed,
    this.redirectedTo,
    this.error,
  });

  final String url;
  final int status;
  final Map<String, String> headers;
  final String? redirectedTo;
  final int receivedBytes;
  final String bodySniff;
  final Duration elapsed;
  final Object? error;

  String? get contentType => headers['content-type'];

  String? get contentRange => headers['content-range'];

  bool get isHls {
    final type = contentType ?? '';
    return type.contains('mpegurl') ||
        bodySniff.startsWith('#EXTM3U') ||
        (redirectedTo?.contains('.m3u8') ?? false);
  }

  bool get looksLikeAudio =>
      !isHls &&
      status >= 200 &&
      status < 300 &&
      receivedBytes > 0 &&
      (contentType?.startsWith('audio/') ?? false);

  /// Total size of the resource, from either form the server may use.
  int? get totalBytes {
    final range = contentRange;
    if (range != null) {
      final slash = range.lastIndexOf('/');
      if (slash != -1) {
        final total = int.tryParse(range.substring(slash + 1).trim());
        if (total != null) return total;
      }
    }
    // content-length on a 206 describes the window, not the resource.
    if (status == 200) return int.tryParse(headers['content-length'] ?? '');
    return null;
  }

  _Attempt copyWith({String? url, String? redirectedTo}) => _Attempt(
    url: url ?? this.url,
    status: status,
    headers: headers,
    receivedBytes: receivedBytes,
    bodySniff: bodySniff,
    elapsed: elapsed,
    redirectedTo: redirectedTo ?? this.redirectedTo,
    error: error,
  );
}
