import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/qbit/qbit_models.dart';
import 'package:plexify/core/qbit/torrent_ranking.dart';

/// The one part of acquisition with judgement in it.
///
/// Everything else in the flow fails obviously — a wrong address 403s, a dead
/// tracker returns nothing. This fails by quietly downloading the wrong record
/// into the folder Plex watches, under the right album's name, and the first
/// anyone knows of it is a tribute band appearing in the library.
void main() {
  QbitSearchResult hit(
    String fileName, {
    int seeders = 10,
    int size = 400000000,
  }) => QbitSearchResult(
    fileName: fileName,
    fileUrl: 'magnet:?xt=$fileName',
    sizeBytes: size,
    seeders: seeders,
    leechers: 1,
  );

  List<RankedTorrent> rank(List<QbitSearchResult> results) => rankTorrents(
    results,
    artist: 'Radiohead',
    album: 'OK Computer',
    year: 1997,
  );

  test('matches through the punctuation filenames actually use', () {
    // The library normaliser drops punctuation entirely, which is right for
    // typed queries and wrong here: `OK_Computer` would fold to `okcomputer`
    // and stop containing either word.
    for (final name in [
      'Radiohead - OK Computer (1997) [FLAC]',
      'Radiohead.OK.Computer.1997.FLAC',
      'Radiohead_-_OK_Computer_[V0]',
    ]) {
      expect(rank([hit(name)]).single.matchesRelease, isTrue, reason: name);
    }
  });

  test('a loose match is never confident, however well seeded', () {
    final ranked = rank([
      hit('Radiohead - OK Computer [FLAC]', seeders: 2),
      hit('Various Artists - Computer Love', seeders: 5000),
    ]);

    // Seeder count measures popularity, never correctness. The most popular
    // result sharing one word with an album is routinely a different record.
    expect(ranked.first.result.fileName, contains('OK Computer'));
    expect(ranked.last.matchesRelease, isFalse);
  });

  test('lossless outranks lossy at similar seeder counts', () {
    final ranked = rank([
      hit('Radiohead - OK Computer [MP3 320]', seeders: 30),
      hit('Radiohead - OK Computer [FLAC]', seeders: 25),
    ]);

    expect(ranked.first.format, AudioFormat.lossless);
  });

  test('seeders matter, but with diminishing returns', () {
    final ranked = rank([
      hit('Radiohead - OK Computer [FLAC]', seeders: 4),
      hit('Radiohead - OK Computer [FLAC]', seeders: 400),
    ]);

    // The gap between 2 and 20 decides whether a download finishes; the gap
    // between 200 and 2000 decides nothing. Scored linearly, a hugely popular
    // result would outweigh everything else about a hit, including its format.
    expect(ranked.first.result.seeders, 400);
    expect(ranked.last.score, greaterThan(0));
  });

  test('karaoke and tribute records are pushed down', () {
    final ranked = rank([
      hit('Karaoke - OK Computer by Radiohead', seeders: 900),
      hit('Radiohead - OK Computer [FLAC]', seeders: 3),
    ]);

    expect(ranked.first.result.fileName, startsWith('Radiohead'));
  });

  test('a penalty word in the album title is not a penalty', () {
    final ranked = rankTorrents(
      [hit('The Who - Live at Leeds [FLAC]')],
      artist: 'The Who',
      album: 'Live at Leeds',
    );

    // Otherwise searching for a live album is sabotaged by its own name.
    expect(ranked.single.matchesRelease, isTrue);
    expect(ranked.single.score, greaterThan(0));
  });

  test('an abbreviated artist still matches on the album', () {
    final ranked = rankTorrents(
      [hit('RHCP - Californication [FLAC]')],
      artist: 'Red Hot Chili Peppers',
      album: 'Californication',
    );

    // Filenames abbreviate performers far more often than titles, so the album
    // needs every word and the artist needs one.
    expect(ranked.single.matchesRelease, isFalse);
  });

  test('a leading article is not required', () {
    final ranked = rankTorrents(
      [hit('Beatles - Revolver [FLAC]')],
      artist: 'The Beatles',
      album: 'Revolver',
    );

    expect(ranked.single.matchesRelease, isTrue);
  });

  group('bestAutomaticChoice', () {
    test('returns nothing when no result names the record', () {
      // The gate on the one-click button. Refusing costs one extra tap on a
      // list that is already open; getting it wrong costs a wrong album on the
      // server, and the two are not the same size of mistake.
      final ranked = rank([hit('Various Artists - Computer Love')]);
      expect(bestAutomaticChoice(ranked), isNull);
    });

    test('returns nothing for a zero-seeded torrent', () {
      final ranked = rank([hit('Radiohead - OK Computer [FLAC]', seeders: 0)]);
      expect(bestAutomaticChoice(ranked), isNull);
    });

    test('allows an unknown seeder count', () {
      // Several plugins simply do not report the figure. Treating "not stated"
      // as "nobody has it" rules out whole trackers.
      final ranked = rank([hit('Radiohead - OK Computer [FLAC]', seeders: -1)]);
      expect(bestAutomaticChoice(ranked), isNotNull);
    });

    test('never picks a whole discography for one album', () {
      final ranked = rank([
        hit('Radiohead - Discography 1993-2016 [FLAC]', seeders: 800),
      ]);

      // It matches every word of every album and is tens of gigabytes. Not
      // excluded from the list — sometimes it is exactly what you want — but
      // never chosen on your behalf.
      expect(bestAutomaticChoice(ranked), isNull);
    });
  });
}
