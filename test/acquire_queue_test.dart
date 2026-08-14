import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/acquire/acquire_queue.dart';
import 'package:plexify/core/acquire/download_source.dart';
import 'package:plexify/core/acquire/matching.dart';
import 'package:plexify/core/catalog/catalog_models.dart';
import 'package:plexify/core/slskd/album_ranking.dart';
import 'package:plexify/core/slskd/slskd_models.dart';

/// Asking for an album stopped being something you wait for.
///
/// A Soulseek search takes fifteen to twenty-five seconds because it waits on
/// strangers, and the old flow spent all of it inside the tap, on a progress
/// banner. Three albums meant three concurrent searches and six queued
/// snackbars playing out long after the searches had finished, which reads as
/// the app being stuck.
///
/// What is guarded here is the ordering and the failure behaviour, because both
/// are invisible until they are wrong: a queue that stops on the first failure
/// silently abandons everything behind it.
void main() {
  CatalogRelease release(String mbid, [String title = 'Kid A']) =>
      CatalogRelease(mbid: mbid, title: title, artist: 'Radiohead');

  /// A source that records what it was asked for and answers as told.
  ///
  /// `answer` returns null for "queued it", or a string to fail with.
  ({DownloadSource source, List<String> asked}) fakeSource({
    String? Function(String mbid)? answer,
    Future<void> Function()? hold,
  }) {
    final asked = <String>[];
    return (
      source: _FakeSource(
        onSearch: (release) async {
          asked.add(release.mbid);
          if (hold != null) await hold();
          final error = answer?.call(release.mbid);
          if (error != null) {
            return AcquireOutcome.failed(DownloadSourceKind.soulseek, error);
          }
          return AcquireOutcome(
            kind: DownloadSourceKind.soulseek,
            queued: _candidate(release.title),
            candidates: [_candidate(release.title)],
          );
        },
      ),
      asked: asked,
    );
  }

  AcquireQueue queueOver(DownloadSource? source) {
    final queue = AcquireQueue(source: () async => source);
    addTearDown(queue.close);
    return queue;
  }

  /// Waits until nothing is left to do, without sleeping for a fixed time.
  Future<void> settle(AcquireQueue queue) async {
    for (var i = 0; i < 200; i++) {
      if (!queue.isBusy && queue.pending == 0) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('the queue never settled');
  }

  test('three albums are searched one at a time, in order', () async {
    // The whole reason this class exists. Concurrency here does not make the
    // work faster, because the wait is on other people's clients; it only makes
    // the results arrive in an order unrelated to the order they were asked
    // for.
    final fake = fakeSource();
    final queue = queueOver(fake.source);

    queue.add(release('a'));
    queue.add(release('b'));
    queue.add(release('c'));

    await settle(queue);

    expect(fake.asked, ['a', 'b', 'c']);
    expect(
      queue.requests.map((r) => r.stage),
      everyElement(AcquireStage.handedOver),
    );
  });

  test('only one search runs at a time', () async {
    var inFlight = 0;
    var peak = 0;
    final fake = fakeSource(
      hold: () async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await Future<void>.delayed(Duration.zero);
        inFlight--;
      },
    );
    final queue = queueOver(fake.source);

    queue.add(release('a'));
    queue.add(release('b'));
    queue.add(release('c'));
    await settle(queue);

    expect(peak, 1);
  });

  test('one failure does not abandon the rest of the queue', () async {
    // The failure that actually happens is a phone on a flaky mobile link, and
    // stopping there would silently drop everything behind it.
    final fake = fakeSource(
      answer: (mbid) => mbid == 'b' ? 'slskd did not answer in time' : null,
    );
    final queue = queueOver(fake.source);

    queue.add(release('a'));
    queue.add(release('b'));
    queue.add(release('c'));
    await settle(queue);

    expect(fake.asked, ['a', 'b', 'c']);

    final failed = queue.requests.firstWhere((r) => r.id == 'b');
    expect(failed.stage, AcquireStage.failed);
    // The server's own words, so the Downloads screen can say something useful
    // rather than "it failed".
    expect(failed.detail, contains('did not answer'));
  });

  test('asking twice for the same album queues it once', () async {
    final fake = fakeSource();
    final queue = queueOver(fake.source);

    expect(queue.add(release('a')), isTrue);
    // Says no rather than silently doing nothing, so the caller can tell you it
    // is already on the list.
    expect(queue.add(release('a')), isFalse);

    await settle(queue);
    expect(fake.asked, ['a']);
  });

  test('retry runs a failed request again', () async {
    var failNext = true;
    final fake = fakeSource(
      answer: (_) {
        if (!failNext) return null;
        failNext = false;
        return 'network went away';
      },
    );
    final queue = queueOver(fake.source);

    queue.add(release('a'));
    await settle(queue);
    expect(queue.requests.single.stage, AcquireStage.failed);

    expect(queue.retry('a'), isTrue);
    await settle(queue);

    expect(queue.requests.single.stage, AcquireStage.handedOver);
    expect(fake.asked, ['a', 'a']);
  });

  test('retrying something that never failed does nothing', () async {
    final fake = fakeSource();
    final queue = queueOver(fake.source);

    queue.add(release('a'));
    await settle(queue);

    expect(queue.retry('nope'), isFalse);
    expect(fake.asked, ['a']);
  });

  test('a search that finds nothing is not a failure', () async {
    // Two different outcomes with two different fixes. "Nobody has it" is an
    // ordinary answer about the world; "the server refused" is about the setup,
    // and only one of them is worth retrying.
    final queue = queueOver(
      _FakeSource(
        onSearch: (_) async =>
            const AcquireOutcome(kind: DownloadSourceKind.soulseek),
      ),
    );

    queue.add(release('a'));
    await settle(queue);

    expect(queue.requests.single.stage, AcquireStage.notFound);
    expect(queue.requests.single.detail, contains('Nobody has it'));
  });

  test('results that are found but not confident say what to do next', () async {
    final queue = queueOver(
      _FakeSource(
        onSearch: (_) async => AcquireOutcome(
          kind: DownloadSourceKind.soulseek,
          candidates: [_candidate('a'), _candidate('b')],
        ),
      ),
    );

    queue.add(release('a'));
    await settle(queue);

    final request = queue.requests.single;
    expect(request.stage, AcquireStage.notFound);
    // Never a best guess: queueing the wrong album puts it in the folder Plex
    // watches under this album's name.
    expect(request.detail, contains('2 results'));
    expect(request.detail, contains('long press'));
  });

  test('no configured server is a failure that says so', () async {
    final queue = queueOver(null);

    queue.add(release('a'));
    await settle(queue);

    expect(queue.requests.single.stage, AcquireStage.failed);
    expect(queue.requests.single.detail, contains('set up'));
  });

  test('the stream reports each change as it happens', () async {
    final fake = fakeSource();
    final queue = queueOver(fake.source);

    final seen = <List<AcquireStage>>[];
    final sub = queue.stream.listen(
      (rs) => seen.add([for (final r in rs) r.stage]),
    );
    addTearDown(sub.cancel);

    queue.add(release('a'));
    await settle(queue);

    // Queued, searching, done. A screen that only saw the last one could not
    // show anything happening.
    //
    // `equals` is not decoration here: bare `contains` on a list of lists
    // compares by identity, so it fails against a perfectly correct value.
    expect(seen.first, [AcquireStage.waiting]);
    expect(seen, contains(equals([AcquireStage.searching])));
    expect(seen.last, [AcquireStage.handedOver]);
  });

  test('finished requests can be cleared without touching the rest', () async {
    final fake = fakeSource(answer: (mbid) => mbid == 'b' ? 'nope' : null);
    final queue = queueOver(fake.source);

    queue.add(release('a'));
    queue.add(release('b'));
    await settle(queue);

    queue.clearFinished();
    expect(queue.requests, isEmpty);
  });
}

class _FakeSource implements DownloadSource {
  _FakeSource({required this.onSearch});

  final Future<AcquireOutcome> Function(CatalogRelease) onSearch;

  @override
  DownloadSourceKind get kind => DownloadSourceKind.soulseek;

  @override
  Future<AcquireOutcome> queueBest(CatalogRelease release) => onSearch(release);

  @override
  Future<AcquireOutcome> find(CatalogRelease release) => onSearch(release);

  @override
  Future<String?> add(AcquireCandidate candidate) async => null;
}

/// A real candidate rather than a stand-in.
///
/// `AcquireCandidate` is sealed, so it cannot be faked from outside its
/// library, which is the sealing working as intended: a third download source
/// should be a compile error everywhere it needs handling, not a runtime
/// surprise. Building the genuine article costs three lines and exercises the
/// real subtitle and readiness logic while it is here.
AcquireCandidate _candidate(String title) => SoulseekCandidate(
  SlskdAlbum(
    username: 'peer',
    directory: r'@@m\Radiohead\Kid A',
    files: const [SlskdFile(filename: r'@@m\Radiohead\Kid A\01.flac', size: 1)],
    score: 100,
    matchesRelease: true,
    format: AudioFormat.lossless,
    hasFreeUploadSlot: true,
    queueLength: 0,
    uploadSpeed: 500000,
  ),
);
