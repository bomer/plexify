import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/slskd/slskd_models.dart';

/// **Soulseek paths use backslashes, whatever platform the peer is on.**
///
/// This is the load-bearing assumption of the whole integration and the one
/// that fails silently. Split on `/` and no separator is ever found, so every
/// file reports the entire path as its directory, every file becomes its own
/// group of one, and the ranking scores a hundred imaginary single-track albums
/// instead of the handful of real ones. Nothing throws. Nothing looks wrong.
/// The search simply stops finding records.
void main() {
  SlskdFile file(String filename, {int size = 1}) =>
      SlskdFile(filename: filename, size: size);

  group('working out which folder a file is in', () {
    test('a backslash path splits, which is the case that actually happens', () {
      final track = file(r'@@abcde\Music\Radiohead\Kid A\01 Everything.flac');

      expect(track.directory, r'@@abcde\Music\Radiohead\Kid A');
      expect(track.name, '01 Everything.flac');
    });

    test('a forward slash path splits too', () {
      // Costs one character to accept and means a peer whose client normalises
      // paths does not silently become one giant group.
      final track = file('music/Radiohead/Kid A/01 Everything.flac');

      expect(track.directory, 'music/Radiohead/Kid A');
      expect(track.name, '01 Everything.flac');
    });

    test('a mixed path splits on the last separator of either kind', () {
      expect(file(r'music/Radiohead\Kid A\01.flac').directory, r'music/Radiohead\Kid A');
      expect(file(r'music\Radiohead/Kid A/01.flac').directory, r'music\Radiohead/Kid A');
    });

    test('a bare filename has no directory rather than a wrong one', () {
      final track = file('01 Everything.flac');
      expect(track.directory, '');
      expect(track.name, '01 Everything.flac');
    });

    test('two tracks in one folder group together, under the folder name', () {
      // The actual point of all of the above.
      //
      // **Both halves are asserted deliberately.** Comparing the two
      // directories alone passes with the backslash handling removed, because
      // then both are the empty string and the empty string equals itself. A
      // guard that survives the bug it guards against is worse than none, so
      // the value is pinned as well as the equality.
      final a = file(r'@@x\Kid A\01.flac');
      final b = file(r'@@x\Kid A\02.flac');

      expect(a.directory, b.directory);
      expect(a.directory, r'@@x\Kid A');
      expect(a.directory, isNotEmpty);
    });
  });

  group('deciding what is audio', () {
    test('the reported extension is used when there is one', () {
      const track = SlskdFile(
        filename: r'x\y\01 Everything.flac',
        size: 1,
        extension: 'flac',
      );
      expect(track.suffix, 'flac');
      expect(track.isAudio, isTrue);
    });

    test('a missing extension falls back to the filename', () {
      // Plenty of clients do not send one, and treating those files as
      // non-audio would empty out whole folders.
      expect(file(r'x\y\01 Everything.FLAC').suffix, 'flac');
      expect(file(r'x\y\01 Everything.FLAC').isAudio, isTrue);
    });

    test('a leading dot on the reported extension is tolerated', () {
      const track = SlskdFile(filename: 'a', size: 1, extension: '.mp3');
      expect(track.suffix, 'mp3');
    });

    test('cover art and logs are not audio', () {
      // They otherwise inflate the file count that decides whether a folder
      // looks like a record at all.
      for (final name in ['folder.jpg', 'album.log', 'playlist.m3u', 'rip.cue']) {
        expect(file(name).isAudio, isFalse, reason: name);
      }
    });
  });

  group('reading a transfer state', () {
    test('succeeded is complete', () {
      expect(
        const SlskdTransfer(
          filename: 'a',
          state: 'Completed, Succeeded',
          size: 1,
        ).isComplete,
        isTrue,
      );
    });

    test('cancelled counts as failed, not as still going', () {
      // A transfer the peer dropped is finished in the only sense that matters
      // here. Showing it in progress leaves the screen waiting on nobody.
      for (final state in [
        'Completed, Errored',
        'Completed, Cancelled',
        'Completed, TimedOut',
        'Completed, Rejected',
      ]) {
        final transfer = SlskdTransfer(filename: 'a', state: state, size: 1);
        expect(transfer.isFailed, isTrue, reason: state);
        expect(transfer.isComplete, isFalse, reason: state);
      }
    });

    test('a queued transfer is neither', () {
      const transfer = SlskdTransfer(
        filename: 'a',
        state: 'Queued, Remotely',
        size: 1,
      );
      expect(transfer.isComplete, isFalse);
      expect(transfer.isFailed, isFalse);
    });
  });

  group('a folder as one job', () {
    SlskdTransfer part(String state, {int size = 100, int done = 0}) =>
        SlskdTransfer(
          filename: 'a',
          state: state,
          size: size,
          bytesTransferred: done,
        );

    test('every file must land before the folder is complete', () {
      // Reporting completion on the first would ask Plex to rescan a
      // half-written album, which is how a broken record gets into the library
      // and then has to be fixed by hand.
      final job = SlskdDownload(
        username: 'peer',
        directory: r'x\Kid A',
        files: [
          part('Completed, Succeeded', done: 100),
          part('InProgress', done: 50),
        ],
      );

      expect(job.isComplete, isFalse);
      expect(job.progress, closeTo(0.75, 0.001));
    });

    test('all succeeded is complete', () {
      final job = SlskdDownload(
        username: 'peer',
        directory: r'x\Kid A',
        files: [
          part('Completed, Succeeded', done: 100),
          part('Completed, Succeeded', done: 100),
        ],
      );
      expect(job.isComplete, isTrue);
      expect(job.progress, 1.0);
    });

    test('one failure fails the folder', () {
      final job = SlskdDownload(
        username: 'peer',
        directory: r'x\Kid A',
        files: [part('Completed, Succeeded', done: 100), part('Completed, Errored')],
      );
      expect(job.isFailed, isTrue);
    });

    test('an empty folder is not silently complete', () {
      // `every` on an empty list is true, which would report a folder holding
      // nothing as a finished album and trigger a Plex rescan for it.
      const job = SlskdDownload(username: 'peer', directory: 'x', files: []);
      expect(job.isComplete, isFalse);
    });

    test('the job is named after the folder, not the whole path', () {
      const job = SlskdDownload(
        username: 'peer',
        directory: r'@@abcde\Music\Radiohead\Kid A',
        files: [],
      );
      expect(job.name, 'Kid A');
    });
  });
}
