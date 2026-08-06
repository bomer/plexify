import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/plex/delta_filter_probe.dart';
import 'package:plexify/core/plex/plex_client.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';

/// The probe answers a question that has no error to read. Plex accepts a
/// filter parameter it does not understand, answers 200, and silently returns
/// everything; and at least one spelling on James's server answers 200 with
/// nothing at all. Both are valid responses and neither says what happened, so
/// every judgement here is made by counting, twice.
void main() {
  const section = PlexSection(key: '3', title: 'Music', type: 'artist');
  const total = 11492;

  late List<Uri> asked;

  /// Builds a server with a per-request rule, recording what was asked.
  PlexClient serverThat(int Function(Uri url) count) {
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
        return http.Response(
          jsonEncode({
            'MediaContainer': {'totalSize': count(request.url)},
          }),
          200,
        );
      }),
    );
  }

  /// A server that genuinely applies [working] and ignores everything else.
  PlexClient serverApplying(String working) {
    return serverThat((url) {
      final value = url.queryParameters[working];
      if (value == null) return total;
      // A real filter: nothing changed in the last minute, everything changed
      // in the last ten years.
      final cutoff = int.parse(value);
      final aMinuteAgo =
          DateTime.now()
              .subtract(const Duration(minutes: 2))
              .millisecondsSinceEpoch ~/
          1000;
      return cutoff > aMinuteAgo ? 0 : total;
    });
  }

  setUp(() => asked = []);

  test('names a spelling that narrows and widens', () async {
    final report = await DeltaFilterProbe(
      client: serverApplying('updatedAt>>='),
    ).run(section);

    expect(report.baseline, total);
    expect(report.anyUsable, isTrue);
    expect(report.usable.single.filter, 'updatedAt>>=');
    expect(report.empty, isEmpty);
  });

  test('a filter that returns everything is ignored, not honoured', () async {
    final report = await DeltaFilterProbe(
      client: serverThat((_) => total),
    ).run(section);

    // Plex drops a parameter it does not recognise and answers 200 with the
    // whole library, which is indistinguishable from success unless something
    // counts.
    expect(report.anyUsable, isFalse);
    expect(report.empty, isEmpty);
    for (final result in report.results) {
      expect(result.verdictAgainst(total), contains('ignored'));
    }
  });

  test('a partial widening still counts as working', () {
    // The real numbers from James's server, and the case that corrected this
    // probe's own rule. `updatedAt>` returned 0 for the last minute and 9,988
    // for the last ten years, out of 11,492. The first rule demanded the
    // widening measurement return *everything*, which assumes every row has an
    // updatedAt inside the window; about 1,500 tracks are older than that or
    // carry no timestamp. A perfectly good filter was reported as broken.
    const partial = DeltaFilterResult(
      filter: 'updatedAt>',
      recent: 0,
      ancient: 9988,
    );

    expect(partial.usableAgainst(total), isTrue);
    expect(partial.verdictAgainst(total), contains('works'));
  });

  test('a filter that returns nothing is refused, however good it looks', () {
    // This is the case that made the second measurement necessary. On the real
    // server `updatedAt>` answered 0 for a one-minute window, which reads as a
    // perfect filter. Adopting it would have meant a delta sync that returned
    // nothing for ever: the library would simply stop gaining music, and
    // nothing in the app would report an error.
    const alwaysEmpty = DeltaFilterResult(
      filter: 'updatedAt>',
      recent: 0,
      ancient: 0,
    );

    expect(alwaysEmpty.usableAgainst(total), isFalse);
    expect(alwaysEmpty.verdictAgainst(total), contains('do not use'));
  });

  test('reports what changed lately, per type, once a filter works', () async {
    final report = await DeltaFilterProbe(
      client: serverApplying('updatedAt>'),
    ).run(section);

    // The question that actually matters, and the one the first two runs of
    // this probe could not answer: a filter being applied says nothing about
    // whether Plex ever moves the timestamp it filters on. If rating an album
    // leaves updatedAt alone, a delta sync that genuinely filters can never
    // carry that rating, and the app silently stops seeing stars set anywhere
    // else. That was invisible while the filter was being ignored, because
    // every sweep was accidentally a full sync.
    expect(report.changes.map((c) => c.label), ['Artists', 'Albums', 'Tracks']);
    for (final change in report.changes) {
      expect(change.counts.keys, DeltaFilterProbe.changeWindows.keys);
      expect(change.error, isNull);
    }
  });

  test(
    'does not ask what changed through a filter that does not work',
    () async {
      final report = await DeltaFilterProbe(
        client: serverThat((_) => total),
      ).run(section);

      // Every window would report the whole library and mean nothing, which is
      // worse than reporting nothing: it reads as "everything changed five
      // minutes ago".
      expect(report.changes, isEmpty);
    },
  );

  test('asks every spelling both questions', () async {
    await DeltaFilterProbe(client: serverThat((_) => total)).run(section);

    // One baseline plus two per candidate. All of them ask for zero metadata,
    // so the whole run stays free enough to do on cellular.
    expect(asked, hasLength(1 + DeltaFilterProbe.candidates.length * 2));
    expect(
      asked.every(
        (u) => !u.queryParameters.containsKey('X-Plex-Container-Size'),
      ),
      isTrue,
      reason: 'container size travels as a header, not a query parameter',
    );
  });

  test('the two cutoffs are a minute and a decade', () async {
    final now = DateTime(2026, 8, 6, 12);
    final report = await DeltaFilterProbe(
      client: serverThat((_) => total),
      now: () => now,
    ).run(section);

    // Deliberately not the real sync cursor for either. A library that genuinely
    // changed since the cursor would return rows through a working filter, and
    // a partial result cannot be told from an ignored one.
    expect(
      report.since,
      now.subtract(DeltaFilterProbe.window).millisecondsSinceEpoch ~/ 1000,
    );
    expect(
      report.ancient,
      now.subtract(DeltaFilterProbe.ancientWindow).millisecondsSinceEpoch ~/
          1000,
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
            'MediaContainer': {'totalSize': total},
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
    expect(report.results.where((r) => r.recent != null), isNotEmpty);
  });
}
