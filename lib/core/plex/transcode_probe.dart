import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'plex_client.dart';
import 'plex_models.dart';
import 'transcode.dart';

/// How much audio to fetch when measuring the delivered bitrate.
///
/// Long enough that per-request overhead does not distort the figure, short
/// enough to cost a few hundred kilobytes rather than a whole track.
const _tailSeconds = 10;

/// Give-up point for the tail read.
///
/// Comfortably more than [_tailSeconds] of the highest rate asked for, and far
/// less than a whole track — so hitting it means `offset` was ignored and the
/// server is streaming from the beginning regardless.
const _tailCapBytes = 1024 * 1024;

/// Answers the questions in task #8 by measuring a real server.
///
/// `/music/:/transcode/universal/start` is the least-documented endpoint this
/// app depends on, and every claim about it that matters is a claim about
/// *behaviour*, not shape: whether it hands back audio or redirects into HLS,
/// whether it honours Range, whether it declares a length, and which of several
/// undocumented ways of asking for a bitrate actually does anything. None of
/// those can be settled by reading, so this settles them by asking.
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

  /// The cap asked for when testing whether a cap works at all.
  ///
  /// Far enough below any plausible natural output that a server honouring it
  /// cannot be mistaken for one ignoring it.
  static const _lowKbps = 128;

  /// How far the measured bitrate may sit from the requested one before the
  /// parameter counts as ignored. MP3 framing and tags put the real figure a
  /// few percent above the nominal rate.
  static const _tolerance = 0.15;

  Future<TranscodeProbeReport> run(PlexTrack track) async {
    final checks = <ProbeCheck>[];
    final log = _SessionLog();

    // Which parameters the endpoint requires is the first unknown, and every
    // later question is meaningless until it is settled — measuring the
    // bitrate of a 400 page proves nothing.
    final tried = <TranscodeProfile, _Attempt>{};
    for (final profile in TranscodeProfile.candidates) {
      final attempt = await _attempt(track, profile, log);
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
      // Measured from delivered bytes rather than a declared size, because on
      // a live transcode there is no declared size to read.
      final natural = await _measureTail(track, winner.key, null, null, log);
      checks.add(_offsetShortensTheStream(natural));

      final capped = <TranscodeBitrateMechanism, _Tail>{};
      if (natural.kbps != null) {
        for (final mechanism in TranscodeBitrateMechanism.candidates) {
          capped[mechanism] = await _measureTail(
            track,
            winner.key,
            mechanism,
            _lowKbps,
            log,
          );
        }
      }
      checks.add(_bitrateMechanism(natural, capped));
      checks.add(await _plexOwnAccount(track, winner.key, log));
    } else {
      checks
        ..add(
          const ProbeCheck(
            'Does offset shorten the stream?',
            ProbeOutcome.unknown,
            'Not measured — no parameter set returned audio.',
          ),
        )
        ..add(
          const ProbeCheck(
            'How can the bitrate be capped?',
            ProbeOutcome.unknown,
            'Not measured — no parameter set returned audio.',
          ),
        );
    }

    checks.add(_sessionsCanBeStopped(log));

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

  ProbeCheck _offsetShortensTheStream(_Tail tail) {
    if (tail.error != null) {
      return ProbeCheck(
        'Does offset shorten the stream?',
        ProbeOutcome.unknown,
        'Request failed: ${tail.error}',
      );
    }
    if (!tail.completed) {
      // The measurement below depends on this, and so does seeking: a
      // transcode with no Range support can only be seeked by restarting it
      // at an offset.
      return ProbeCheck(
        'Does offset shorten the stream?',
        ProbeOutcome.fail,
        'Asked for the last $_tailSeconds seconds and read ${tail.bytes} '
            'bytes without reaching the end — offset appears to be ignored. '
            'Without it there is no way to seek a stream that has no Range '
            'support.',
      );
    }
    return ProbeCheck(
      'Does offset shorten the stream?',
      ProbeOutcome.pass,
      'The last $_tailSeconds seconds came back whole in ${tail.bytes} bytes, '
          'so offset both works and gives seeking a route that does not need '
          'Range.',
    );
  }

  /// Which way of asking for a lower bitrate actually lowers it.
  ///
  /// Compared against the rate the server produces when asked for nothing,
  /// because "asked for 320, got 235" says nothing on its own — the source may
  /// simply be quieter than that. Only a request that moves the output away
  /// from the natural rate has been honoured.
  ProbeCheck _bitrateMechanism(
    _Tail natural,
    Map<TranscodeBitrateMechanism, _Tail> capped,
  ) {
    final baseline = natural.kbps;
    if (baseline == null) {
      return ProbeCheck(
        'How can the bitrate be capped?',
        ProbeOutcome.unknown,
        'Could not measure the natural rate: ${natural.describe}.',
      );
    }

    final lines = <String>[];
    final worked = <String>[];
    for (final entry in capped.entries) {
      final kbps = entry.value.kbps;
      final honoured = kbps != null && _near(kbps, _lowKbps);
      if (honoured) worked.add(entry.key.name);
      lines.add(
        '  ${entry.key.name}: '
        '${kbps == null ? entry.value.describe : '~$kbps kbps'}'
        '${honoured ? ' — honoured' : ''}',
      );
    }

    return ProbeCheck(
      'How can the bitrate be capped?',
      worked.isEmpty ? ProbeOutcome.fail : ProbeOutcome.pass,
      'Natural output ~$baseline kbps. Asked each for $_lowKbps:\n'
          '${lines.join('\n')}\n'
          '${worked.isEmpty ? 'None of them changed the output, so there is no '
                    'way to cap the rate — cellular listening costs full price.' : 'Use: ${worked.first}.'}',
    );
  }

  /// What Plex says it decided, in its own words.
  ///
  /// Three ways of asking for 128 kbps all came back at the natural rate, which
  /// is either a server that ignores the cap or a request it read as something
  /// else entirely. Delivered bytes cannot tell those apart. The server's own
  /// session record can, and it also carries fields worth knowing that nobody
  /// thought to ask for — so it is reported verbatim rather than summarised.
  ///
  /// Reads only a window, deliberately: the transcode has to still be running
  /// when the question is asked.
  Future<ProbeCheck> _plexOwnAccount(
    PlexTrack track,
    TranscodeProfile profile,
    _SessionLog log,
  ) async {
    final session = _newSession();
    final url = _client.transcodeUrl(
      track.ratingKey,
      session: session,
      bitrateKbps: _lowKbps,
      bitrate: TranscodeBitrateMechanism.profileLimitation,
      profile: profile,
    );

    final read = await _fetch(url);
    if (!read.looksLikeAudio) {
      await log.close(session, _client, started: false);
      return const ProbeCheck(
        'What does Plex say it is doing?',
        ProbeOutcome.unknown,
        'The capped request did not return audio, so there was no session '
            'to ask about.',
      );
    }

    final sessions = await _client.transcodeSessions();
    await log.close(session, _client, started: true);

    if (sessions.isEmpty) {
      return const ProbeCheck(
        'What does Plex say it is doing?',
        ProbeOutcome.unknown,
        'The server listed no transcode sessions while one was running — '
            'either it does not report music transcodes, or the stream was '
            'already finished.',
      );
    }

    final mine = sessions.firstWhere(
      (s) => '${s['key']}'.contains(session),
      // Any session is better than none: if the key does not match, that
      // mismatch is worth seeing rather than hiding behind "not found".
      orElse: () => sessions.first,
    );

    final lines = mine.entries.map((e) => '  ${e.key}: ${e.value}').join('\n');
    return ProbeCheck(
      'What does Plex say it is doing?',
      ProbeOutcome.pass,
      'Asked for $_lowKbps kbps; the server describes the session as:\n$lines',
    );
  }

  /// Whether the server let go of the transcodes this run started.
  ///
  /// Only sessions that actually began are judged: a stop for one that never
  /// started cannot succeed, and reporting that as a failure points at teardown
  /// when the fault is upstream.
  ProbeCheck _sessionsCanBeStopped(_SessionLog log) {
    if (log.started.isEmpty) {
      return const ProbeCheck(
        'Can the transcode session be stopped?',
        ProbeOutcome.unknown,
        'No transcode ever started, so there was nothing to tear down.',
      );
    }

    final statuses = log.started.map((s) => log.stopStatus[s] ?? 0).toList();
    final accepted = statuses.where((s) => s > 0 && s < 400).length;
    final byCode = <int, int>{};
    for (final status in statuses) {
      byCode[status] = (byCode[status] ?? 0) + 1;
    }
    final breakdown = byCode.entries
        .map(
          (e) => '${e.value}x ${e.key == 0 ? 'unreachable' : 'HTTP ${e.key}'}',
        )
        .join(', ');

    return ProbeCheck(
      'Can the transcode session be stopped?',
      accepted == statuses.length ? ProbeOutcome.pass : ProbeOutcome.fail,
      '$accepted of ${statuses.length} started sessions accepted the stop '
          '($breakdown). Anything left over keeps the server transcoding into '
          'a buffer nobody is reading.',
    );
  }

  // --- transport ------------------------------------------------------------

  Future<_Attempt> _attempt(
    PlexTrack track,
    TranscodeProfile profile,
    _SessionLog log,
  ) async {
    final session = _newSession();

    // No bitrate asked for: this step is about which parameters the endpoint
    // requires, and a rejected bitrate parameter would muddle the answer.
    final url = _client.transcodeUrl(
      track.ratingKey,
      session: session,
      profile: profile,
    );

    final first = await _fetch(url);
    // Redirects are followed by hand, once, because *where* it redirects is
    // itself an answer — an automatic follow would hide a hop into HLS.
    final location = first.redirectedTo;
    final result = location == null
        ? first
        : (await _fetch(
            Uri.parse(url).resolve(location).toString(),
          )).copyWith(url: url, redirectedTo: location);

    // Torn down straight away rather than at the end of the run, so the probe
    // never has five transcodes going at once on a machine that is also
    // serving music.
    await log.close(session, _client, started: result.looksLikeAudio);
    return result;
  }

  /// Downloads the last [_tailSeconds] of the track and counts the bytes.
  ///
  /// A live transcode declares no length, so the size cannot be read off a
  /// header and the delivered bitrate cannot be inferred from one. Fetching
  /// whole tracks to compare would cost tens of megabytes on exactly the
  /// connection this exists to measure — but `offset` starts the transcode
  /// partway in, so asking for the final few seconds yields a short stream of
  /// known duration. Bytes over that duration is the bitrate, measured rather
  /// than believed.
  Future<_Tail> _measureTail(
    PlexTrack track,
    TranscodeProfile profile,
    TranscodeBitrateMechanism? mechanism,
    int? kbps,
    _SessionLog log,
  ) async {
    final offset = track.duration - const Duration(seconds: _tailSeconds);
    if (offset <= Duration.zero) {
      return const _Tail(
        bytes: 0,
        completed: false,
        error: 'Track is shorter than the measurement window.',
      );
    }

    final session = _newSession();

    final url = _client.transcodeUrl(
      track.ratingKey,
      session: session,
      bitrateKbps: kbps,
      bitrate: mechanism,
      profile: profile,
      offset: offset,
    );

    final read = await _fetch(url, maxBytes: _tailCapBytes, ranged: false);
    await log.close(session, _client, started: read.looksLikeAudio);

    if (read.error != null) return _Tail(bytes: 0, error: '${read.error}');
    if (read.status >= 400) {
      return _Tail(bytes: 0, error: 'HTTP ${read.status}');
    }
    return _Tail(bytes: read.receivedBytes, completed: read.completed);
  }

  Future<_Attempt> _fetch(
    String url, {
    int maxBytes = _windowBytes,
    bool ranged = true,
  }) async {
    final started = DateTime.now();
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = false;
      if (ranged) request.headers['Range'] = 'bytes=0-${maxBytes - 1}';

      final response = await _http.send(request);
      final (bytes, completed) = await _take(response.stream, maxBytes);

      return _Attempt(
        url: url,
        status: response.statusCode,
        headers: response.headers,
        redirectedTo: response.statusCode >= 300 && response.statusCode < 400
            ? response.headers['location']
            : null,
        receivedBytes: bytes.length,
        completed: completed,
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

  /// Reads at most [max] bytes, then hangs up. Reports whether the stream ended
  /// on its own.
  ///
  /// The cap is load-bearing: this server ignores Range and offers the entire
  /// transcode, so reading to completion would download the whole track over
  /// the cellular link being measured. Whether the cap was reached is itself a
  /// finding — it is how an ignored `offset` shows up.
  static Future<(List<int>, bool)> _take(Stream<List<int>> stream, int max) {
    final out = <int>[];
    final done = Completer<(List<int>, bool)>();
    late StreamSubscription<List<int>> sub;

    sub = stream.listen(
      (chunk) {
        out.addAll(chunk);
        if (out.length >= max && !done.isCompleted) {
          done.complete((out.sublist(0, max), false));
          unawaited(sub.cancel());
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete((out, true));
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

/// A measured stretch of audio: how many bytes arrived for a known duration.
class _Tail {
  const _Tail({required this.bytes, this.completed = false, this.error});

  final int bytes;

  /// Whether the stream ended on its own rather than being cut off at the cap.
  /// A cut-off read means `offset` was ignored, so the bytes describe the
  /// start of the track and not the window that was asked for.
  final bool completed;

  final String? error;

  int? get kbps => !completed || bytes <= 0
      ? null
      : (bytes * 8 / _tailSeconds / 1000).round();

  String get describe => error != null
      ? error!
      : completed
      ? '$bytes bytes'
      : 'did not end within $_tailCapBytes bytes';
}

class _Attempt {
  const _Attempt({
    required this.url,
    required this.status,
    required this.headers,
    required this.receivedBytes,
    required this.bodySniff,
    required this.elapsed,
    this.completed = false,
    this.redirectedTo,
    this.error,
  });

  final String url;
  final int status;
  final Map<String, String> headers;
  final String? redirectedTo;
  final int receivedBytes;

  /// Whether the body ended on its own rather than hitting the read cap.
  final bool completed;

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
    completed: completed,
    bodySniff: bodySniff,
    elapsed: elapsed,
    redirectedTo: redirectedTo ?? this.redirectedTo,
    error: error,
  );
}

/// Every transcode session this run opened, and what happened when it was
/// asked to stop.
class _SessionLog {
  /// Sessions where a transcode genuinely began.
  final started = <String>[];

  final stopStatus = <String, int>{};

  Future<void> close(
    String session,
    PlexClient client, {
    required bool started,
  }) async {
    if (started) this.started.add(session);
    stopStatus[session] = await client.stopTranscodeSession(session);
  }
}
