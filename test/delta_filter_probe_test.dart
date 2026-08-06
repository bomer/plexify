import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/plex/delta_filter_probe.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';

/// The probe answers a question that has no error to read: Plex accepts a
/// filter parameter it does not understand, answers 200, and silently returns
/// everything. So "honoured" can only mean "returned fewer rows than
/// unfiltered", and that is the judgement these tests are about.
void main() {
  const section = PlexSection(key: '3', title: 'Music', type: 'artist');

  late List<Uri> asked;

  /// A server that acts on [honours] and ignores every other filter, answering
  /// [total] whenever it does not filter.
  PlexClient serverThat({required Set<String> honours, int total = 13704}) {
    return PlexClient(
      server: const PlexServer(
        name: 'Tower',
        baseUrl: 'https://tower.example:32400',
        token: 'tok',
        isLocal: true,
        isRelay: false,
      ),
      identity: PlexIdentity.forTesting(),
      httpClient: MockClient((request) async {
        asked.add(request.url);
        final applied = honours.any(
          (f) => request.url.queryParameters.containsKey(f),
        );
        return http.Response(
          jsonEncode({
            'MediaContainer': {'totalSize': applied ? 2 : total},
          }),
          200,
        );
      }),
    );
  }

  setUp(() => asked = []);

  test('names the spelling that narrows the result', () async {
    final report = await DeltaFilterProbe(
      client: serverThat(honours: {'updatedAt>>='}),
    ).run(section);

    expect(report.baseline, 13704);
    expect(report.anyHonoured, isTrue);
    expect(report.honoured.first.filter, 'updatedAt>>=');
  });

  test('a filter that returns everything is not honoured', () async {
    final report = await DeltaFilterProbe(
      client: serverThat(honours: const {}),
    ).run(section);

    // The whole failure mode. Every candidate came back 200 with the entire
    // library, which is indistinguishable from success unless something counts.
    expect(report.anyHonoured, isFalse);
    for (final result in report.results) {
      expect(result.count, 13704);
      expect(result.error, isNull);
    }
  });

  test('asks for no metadata at all', () async {
    await DeltaFilterProbe(client: serverThat(honours: const {})).run(section);

    // Five requests against an 11k library have to stay free. The probe runs
    // on a phone, possibly on cellular, and a version of it that pulled a page
    // of tracks per candidate would cost more than the bug it is measuring.
    expect(asked, hasLength(DeltaFilterProbe.candidates.length + 1));
    expect(
      asked.every(
        (u) => !u.queryParameters.containsKey('X-Plex-Container-Size'),
      ),
      isTrue,
      reason: 'container size travels as a header, not a query parameter',
    );
  });

  test('asks about a window nothing can have changed in', () async {
    final now = DateTime(2026, 8, 6, 12);
    final report = await DeltaFilterProbe(
      client: serverThat(honours: const {}),
      now: () => now,
    ).run(section);

    // Deliberately not the real sync cursor. A library that genuinely changed
    // since the cursor would return rows through a working filter, and a
    // partial result cannot be told from an ignored one. A minute ago there is
    // no ambiguous middle: nearly nothing, or everything.
    expect(
      report.since,
      now.subtract(DeltaFilterProbe.window).millisecondsSinceEpoch ~/ 1000,
    );
  });

  test('a rejected spelling is a result, not a failed run', () async {
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
        if (request.url.queryParameters.keys.any((k) => k.contains('>>'))) {
          return http.Response('bad request', 400);
        }
        return http.Response(
          jsonEncode({
            'MediaContainer': {'totalSize': 13704},
          }),
          200,
        );
      }),
    );

    final report = await DeltaFilterProbe(client: client).run(section);

    // Which spellings the server rejects outright is part of the answer, so one
    // 400 must not abandon the candidates after it.
    expect(report.results, hasLength(DeltaFilterProbe.candidates.length));
    expect(report.results.where((r) => r.error != null), isNotEmpty);
    expect(report.results.where((r) => r.count != null), isNotEmpty);
  });
}
