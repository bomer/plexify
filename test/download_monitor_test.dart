import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/acquire/download_monitor.dart';
import 'package:plexify/core/acquire/download_source.dart';
import 'package:plexify/core/qbit/qbit_models.dart';
import 'package:plexify/core/slskd/slskd_models.dart';

/// The monitor turns a finished download into a Plex rescan.
///
/// Two mistakes are easy here and neither is visible on screen. Announcing
/// everything already complete on the first poll asks Plex to rescan the whole
/// library on every cold start; announcing a finished download on *every*
/// subsequent poll does the same thing continuously, because both servers keep
/// it in the list afterwards. qBittorrent seeds it and slskd holds the
/// transfers until they are cleared.
///
/// It takes a poll function rather than a client, so what is tested here is the
/// logic rather than either server's JSON. The mapping from each server's own
/// model is pinned separately at the bottom, because that is where the ids come
/// from and a colliding id would merge two downloads into one.
void main() {
  DownloadJob job(
    String id, {
    double progress = 0,
    bool complete = false,
    bool failed = false,
  }) => DownloadJob(
    id: id,
    name: 'Radiohead - OK Computer',
    progress: progress,
    sizeBytes: 400000000,
    isComplete: complete,
    isFailed: failed,
  );

  /// A monitor over a list the test can change between polls.
  ({DownloadMonitor monitor, void Function(List<DownloadJob>) set, int Function() rescans})
  monitorOver(List<DownloadJob> initial, {bool Function()? fail}) {
    var jobs = initial;
    var rescans = 0;
    final monitor = DownloadMonitor(
      poll: () async {
        if (fail?.call() ?? false) throw Exception('server asleep');
        return jobs;
      },
      onComplete: () async => rescans++,
    );
    addTearDown(monitor.stop);
    return (monitor: monitor, set: (j) => jobs = j, rescans: () => rescans);
  }

  test('does not announce what was already finished at launch', () async {
    final fake = monitorOver([
      job('h1', progress: 1, complete: true),
      job('h2', progress: 1, complete: true),
    ]);

    await fake.monitor.pollNow();

    // Everything is complete on a cold start, since both servers keep finished
    // downloads in the list. Treating that as news means a full Plex rescan
    // every time the app opens.
    expect(fake.rescans(), 0);
    expect(fake.monitor.completions, 0);
  });

  test('announces a download that finishes, exactly once', () async {
    final fake = monitorOver([job('h1', progress: 0.4)]);

    await fake.monitor.pollNow();
    expect(fake.rescans(), 0);

    fake.set([job('h1', progress: 1, complete: true)]);
    await fake.monitor.pollNow();
    expect(fake.rescans(), 1);

    // Still in the list, still complete. Without the reported set this asks
    // Plex to rescan every five seconds for the rest of the session.
    await fake.monitor.pollNow();
    await fake.monitor.pollNow();
    expect(fake.rescans(), 1);
    expect(fake.monitor.completions, 1);
  });

  test('two downloads finishing are two completions', () async {
    final fake = monitorOver([job('h1'), job('h2')]);
    await fake.monitor.pollNow();

    fake.set([
      job('h1', progress: 1, complete: true),
      job('h2', progress: 1, complete: true),
    ]);
    await fake.monitor.pollNow();

    expect(fake.monitor.completions, 2);
    // One rescan, though. Plex is asked to look at the section, not at a file,
    // so twice would be the same work done twice.
    expect(fake.rescans(), 1);
  });

  test('keeps polling after the server stops answering', () async {
    var fail = true;
    final fake = monitorOver([], fail: () => fail);

    await fake.monitor.pollNow();
    expect(fake.monitor.lastError, isNotNull);

    // A server being asleep, restarting or briefly unreachable is ordinary. A
    // monitor that gave up on the first failure would only work when it was
    // never needed.
    fail = false;
    await fake.monitor.pollNow();
    expect(fake.monitor.lastError, isNull);
    expect(fake.monitor.polls, 1);
  });

  group('what each server calls a job', () {
    test('a torrent is identified by its hash', () {
      const torrent = QbitTorrent(
        hash: 'abc123',
        name: 'Radiohead - OK Computer',
        progress: 0.5,
        state: 'downloading',
        sizeBytes: 400000000,
        category: 'Music',
      );

      expect(torrent.asJob.id, 'abc123');
      expect(torrent.asJob.name, 'Radiohead - OK Computer');
    });

    test('a Soulseek job is identified by peer and folder together', () {
      // **Neither alone is unique.** Two people can share the same album, and
      // one person can be sending two different records at once. Collapsing
      // either case into one job would report a completion for something still
      // arriving.
      const a = SlskdDownload(
        username: 'alice',
        directory: r'@@x\Radiohead\Kid A',
        files: [],
      );
      const b = SlskdDownload(
        username: 'bob',
        directory: r'@@y\Radiohead\Kid A',
        files: [],
      );
      const c = SlskdDownload(
        username: 'alice',
        directory: r'@@x\Radiohead\Amnesiac',
        files: [],
      );

      expect(a.asJob.id, isNot(b.asJob.id), reason: 'same album, two peers');
      expect(a.asJob.id, isNot(c.asJob.id), reason: 'one peer, two albums');
      expect(a.asJob.name, 'Kid A');
    });
  });
}
