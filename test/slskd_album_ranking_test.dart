import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/acquire/matching.dart';
import 'package:plexify/core/slskd/album_ranking.dart';
import 'package:plexify/core/slskd/slskd_models.dart';

/// Soulseek has no album object anywhere in it. An album is an inference this
/// app makes from several audio files sharing a folder on one person's disk,
/// and everything below is about that inference being right.
///
/// The failure this guards is not an exception. It is a tribute record landing
/// in the library under the name of the album that was asked for, which is only
/// noticed weeks later when somebody plays it.
void main() {
  SlskdFile track(
    String path, {
    int size = 30000000,
    int? bitRate,
  }) => SlskdFile(filename: path, size: size, bitRate: bitRate);

  /// A peer sharing one folder of [count] tracks.
  SlskdResponse peer({
    required String username,
    required String directory,
    int count = 10,
    String extension = 'flac',
    bool freeSlot = true,
    int queue = 0,
    int speed = 500000,
    int? bitRate,
  }) => SlskdResponse(
    username: username,
    hasFreeUploadSlot: freeSlot,
    uploadSpeed: speed,
    queueLength: queue,
    files: [
      for (var i = 1; i <= count; i++)
        track(
          '$directory\\${i.toString().padLeft(2, '0')} Track.$extension',
          bitRate: bitRate,
        ),
    ],
  );

  List<SlskdAlbum> rank(
    List<SlskdResponse> responses, {
    String artist = 'Radiohead',
    String album = 'Kid A',
    int? year,
  }) => rankSlskdAlbums(
    responses,
    artist: artist,
    album: album,
    year: year,
  );

  group('finding the record inside somebody\'s folders', () {
    test('files are grouped by folder, one album per directory', () {
      // One peer sharing two records answers with one flat file list. Nothing
      // in the protocol says where one album ends and the next begins.
      final response = SlskdResponse(
        username: 'peer',
        files: [
          track(r'@@x\Radiohead\Kid A\01.flac'),
          track(r'@@x\Radiohead\Kid A\02.flac'),
          track(r'@@x\Radiohead\Kid A\03.flac'),
          track(r'@@x\Radiohead\Amnesiac\01.flac'),
          track(r'@@x\Radiohead\Amnesiac\02.flac'),
        ],
      );

      final ranked = rank([response]);

      expect(ranked, hasLength(2));
      expect(ranked.first.folderName, 'Kid A');
      expect(ranked.first.trackCount, 3);
      expect(ranked.first.matchesRelease, isTrue);

      // Amnesiac is a real folder and a real answer, it is just not the record
      // that was asked for.
      expect(ranked.last.matchesRelease, isFalse);
    });

    test('the artist is matched from the parent folder', () {
      // The near-universal layout. Matching the leaf folder alone would fail
      // the artist half of essentially every result on the network.
      final ranked = rank([
        peer(username: 'peer', directory: r'@@x\Music\Radiohead\Kid A'),
      ]);

      expect(ranked.single.matchesRelease, isTrue);
    });

    test('cover art and logs do not count towards the track count', () {
      final response = SlskdResponse(
        username: 'peer',
        files: [
          track(r'@@x\Radiohead\Kid A\01.flac'),
          track(r'@@x\Radiohead\Kid A\02.flac'),
          track(r'@@x\Radiohead\Kid A\folder.jpg'),
          track(r'@@x\Radiohead\Kid A\rip.log'),
          track(r'@@x\Radiohead\Kid A\album.cue'),
        ],
      );

      // Two songs and three other things is a loose pair, not a five-track
      // record, and it must not be queued as one.
      expect(rank([response]).single.trackCount, 2);
    });

    test('a peer who keeps everything loose in one folder can never match', () {
      // Worth pinning because it is a safety property rather than a nicety.
      // This group is four thousand files; queueing it would pull somebody's
      // entire collection in answer to a request for one record.
      final response = SlskdResponse(
        username: 'hoarder',
        files: [
          for (var i = 0; i < 4000; i++)
            track('@@x\\Music\\Radiohead - Kid A - $i.flac'),
        ],
      );

      final ranked = rank([response]);
      expect(ranked.single.matchesRelease, isFalse);
      expect(bestSlskdAlbum(ranked), isNull);
    });
  });

  group('what outranks what', () {
    test('a folder naming the record beats a better-connected one that does not', () {
      final ranked = rank([
        peer(
          username: 'fast-but-wrong',
          directory: r'@@x\Various\Now Thats What I Call Music',
          freeSlot: true,
          speed: 10000000,
        ),
        peer(
          username: 'right',
          directory: r'@@x\Radiohead\Kid A',
          freeSlot: false,
          queue: 5,
          speed: 20000,
        ),
      ]);

      // Availability says whether you can get a file, never whether it is the
      // right file.
      expect(ranked.first.username, 'right');
    });

    test('among matches, a free slot beats a long queue', () {
      final ranked = rank([
        peer(
          username: 'busy',
          directory: r'@@x\Radiohead\Kid A',
          freeSlot: false,
          queue: 60,
        ),
        peer(
          username: 'idle',
          directory: r'@@y\Radiohead\Kid A',
          freeSlot: true,
        ),
      ]);

      expect(ranked.first.username, 'idle');
      expect(ranked.every((a) => a.matchesRelease), isTrue);
    });

    test('lossless beats lossy', () {
      final ranked = rank([
        peer(
          username: 'mp3',
          directory: r'@@x\Radiohead\Kid A',
          extension: 'mp3',
          bitRate: 320,
        ),
        peer(
          username: 'flac',
          directory: r'@@y\Radiohead\Kid A',
          extension: 'flac',
        ),
      ]);

      expect(ranked.first.username, 'flac');
      expect(ranked.first.format, AudioFormat.lossless);
    });

    test('real bitrate breaks ties within lossy but never crosses the tier', () {
      final ranked = rank([
        peer(
          username: 'low',
          directory: r'@@x\Radiohead\Kid A',
          extension: 'mp3',
          bitRate: 128,
        ),
        peer(
          username: 'high',
          directory: r'@@y\Radiohead\Kid A',
          extension: 'mp3',
          bitRate: 320,
        ),
      ]);

      expect(ranked.first.username, 'high');
      expect(ranked.first.bitRate, 320);
    });

    test('a stray wav does not make an mp3 rip look lossless', () {
      // AudioFormat.detect answers lossless if *any* extension present is, so
      // the majority extension is what decides, not the set.
      final response = SlskdResponse(
        username: 'peer',
        files: [
          track(r'@@x\Radiohead\Kid A\01.mp3'),
          track(r'@@x\Radiohead\Kid A\02.mp3'),
          track(r'@@x\Radiohead\Kid A\03.mp3'),
          track(r'@@x\Radiohead\Kid A\interlude.wav'),
        ],
      );

      expect(rank([response]).single.format, AudioFormat.lossy);
    });

    test('the year in the path is worth something', () {
      final ranked = rank(
        [
          peer(username: 'plain', directory: r'@@x\Radiohead\Kid A'),
          peer(username: 'dated', directory: r'@@y\Radiohead\Kid A (2000)'),
        ],
        year: 2000,
      );

      expect(ranked.first.username, 'dated');
    });
  });

  group('what is never chosen for you', () {
    test('a karaoke folder naming the record is not the automatic choice', () {
      // It contains every word of both the artist and the album, so it matches
      // on tokens alone. This is the case the whole unwanted-word gate exists
      // for, and it is shared with the torrent ranker.
      final ranked = rank([
        peer(
          username: 'karaoke',
          directory: r'@@x\Karaoke\Radiohead - Kid A Karaoke',
          freeSlot: true,
        ),
      ]);

      expect(ranked.single.matchesRelease, isFalse);
      expect(bestSlskdAlbum(ranked), isNull);
    });

    test('a live album is not sabotaged by its own name', () {
      final ranked = rank(
        [
          peer(
            username: 'peer',
            directory: r'@@x\Radiohead\I Might Be Wrong Live Recordings',
          ),
        ],
        album: 'I Might Be Wrong Live Recordings',
      );

      expect(ranked.single.matchesRelease, isTrue);
    });

    test('a single loose track is offered but never queued for you', () {
      final ranked = rank([
        peer(username: 'peer', directory: r'@@x\Radiohead\Kid A', count: 1),
      ]);

      // Still in the list. Sometimes one track is exactly what is wanted, and
      // that is a decision for a person.
      expect(ranked.single.matchesRelease, isTrue);
      expect(bestSlskdAlbum(ranked), isNull);
    });

    test('a folder with "discography" in the path is never the automatic choice', () {
      final ranked = rank([
        peer(
          username: 'peer',
          directory: r'@@x\Radiohead\Discography\Kid A',
          count: 200,
        ),
      ]);

      // Caught by the bundle word, before size is ever considered.
      expect(ranked.single.matchesRelease, isFalse);
      expect(bestSlskdAlbum(ranked), isNull);
    });

    test('a huge folder is not queued even when its path names the record', () {
      // The case the bundle word misses, and the one that actually costs
      // something: somebody's collection sitting in a folder that happens to be
      // named after the album, with two hundred files in it. Nothing in the
      // path says "discography", so only the size gate stops it.
      final ranked = rank([
        peer(username: 'dump', directory: r'@@x\Radiohead\Kid A', count: 200),
      ]);

      expect(ranked.single.matchesRelease, isTrue);
      expect(ranked.single.looksLikeAnAlbum, isFalse);
      expect(bestSlskdAlbum(ranked), isNull);
    });

    test('an ordinary long album is still fine', () {
      // The size gate must not swallow a double album or a boxed set disc.
      final ranked = rank([
        peer(username: 'peer', directory: r'@@x\Radiohead\Kid A', count: 28),
      ]);

      expect(bestSlskdAlbum(ranked)?.username, 'peer');
    });

    test('a peer with no slot and a wall of a queue is not chosen', () {
      final ranked = rank([
        peer(
          username: 'wall',
          directory: r'@@x\Radiohead\Kid A',
          freeSlot: false,
          queue: 200,
        ),
      ]);

      // A snackbar saying "Queued" would be technically true and practically a
      // lie.
      expect(ranked.single.matchesRelease, isTrue);
      expect(bestSlskdAlbum(ranked), isNull);
    });

    test('an ordinary short queue is fine, because that is a wait not a wall', () {
      final ranked = rank([
        peer(
          username: 'ok',
          directory: r'@@x\Radiohead\Kid A',
          freeSlot: false,
          queue: 3,
        ),
      ]);

      expect(bestSlskdAlbum(ranked)?.username, 'ok');
    });

    test('a 128k rip is chosen when it is the only match, by design', () {
      // The decision recorded in the plan: bitrate ranks, it never excludes.
      // Not getting the record at all is the worse outcome.
      final ranked = rank([
        peer(
          username: 'only',
          directory: r'@@x\Radiohead\Kid A',
          extension: 'mp3',
          bitRate: 128,
        ),
      ]);

      expect(bestSlskdAlbum(ranked)?.username, 'only');
    });

    test('nothing at all is not a choice', () {
      expect(bestSlskdAlbum(const []), isNull);
      expect(rank([]), isEmpty);
    });
  });
}
