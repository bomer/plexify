import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/catalog/catalog_matcher.dart';
import 'package:plexify/core/catalog/catalog_models.dart';

/// De-duplication (#30) is the part of the catalog tier that fails *quietly*.
///
/// Get it wrong in one direction and every album you own appears in the list of
/// albums you do not, which is noise you can see. Get it wrong in the other and
/// records you are missing silently never appear, which you cannot. Both are
/// asserted here, and the second is the one these tests exist for.
void main() {
  CatalogRelease release(
    String title, {
    String artist = 'Radiohead',
    String mbid = 'mb-1',
  }) => CatalogRelease(mbid: mbid, title: title, artist: artist);

  group('stripEditionQualifiers', () {
    test('drops a bracketed group that only names a pressing', () {
      // The one-sided problem this exists for: MusicBrainz titles are clean and
      // file tags are not, so without this every remastered album you own is
      // reported as an album you are missing.
      expect(stripEditionQualifiers('Nevermind (Deluxe Edition)'), 'Nevermind');
      expect(stripEditionQualifiers('Kid A [Remastered]'), 'Kid A');
      expect(stripEditionQualifiers('Abbey Road (2019 Mix)'), 'Abbey Road');
      expect(
        stripEditionQualifiers('Blue Lines (20th Anniversary Edition)'),
        'Blue Lines',
      );
    });

    test('keeps a bracketed group that is part of the title', () {
      // Stripping every bracket is one line shorter and wrong: this title would
      // stop matching itself.
      expect(
        stripEditionQualifiers("(What's the Story) Morning Glory?"),
        "(What's the Story) Morning Glory?",
      );
      expect(
        stripEditionQualifiers('Live at Leeds (Live at Leeds)'),
        'Live at Leeds (Live at Leeds)',
      );
    });

    test('keeps a qualifier that distinguishes two real records', () {
      // The invisible failure. Collapsing these means owning Volume 1 hides
      // Volume 2 from the missing list forever, and nothing on screen says so.
      expect(
        stripEditionQualifiers('Greatest Hits (Volume 1)'),
        'Greatest Hits (Volume 1)',
      );
      expect(
        stripEditionQualifiers('Greatest Hits (Volume 2)'),
        'Greatest Hits (Volume 2)',
      );
    });

    test('never reduces a title to nothing', () {
      // An empty key would match every other empty-keyed album at once.
      expect(stripEditionQualifiers('(Remastered)'), '(Remastered)');
    });
  });

  group('OwnedIndex', () {
    test('an exact MBID match is believed outright', () {
      final index = OwnedIndex([
        const OwnedAlbum(
          title: 'Something Else Entirely',
          artist: 'A Different Band',
          mbid: 'mb-42',
        ),
      ]);

      // Neither the title nor the artist agrees, and it is still the same
      // record — which is the whole reason to prefer the id when there is one.
      expect(index.owns(release('In Rainbows', mbid: 'mb-42')), isTrue);
    });

    test('falls back to normalised artist and title', () {
      // The common path: Plex records an MBID for very few albums.
      final index = OwnedIndex([
        const OwnedAlbum(title: "Ok Computer", artist: 'radiohead'),
      ]);

      expect(index.owns(release('OK Computer')), isTrue);
    });

    test('matches through an edition qualifier on the library side', () {
      final index = OwnedIndex([
        const OwnedAlbum(
          title: 'OK Computer (Collector\'s Edition)',
          artist: 'Radiohead',
        ),
      ]);

      expect(index.owns(release('OK Computer')), isTrue);
    });

    test('does not match a different album by the same artist', () {
      final index = OwnedIndex([
        const OwnedAlbum(title: 'OK Computer', artist: 'Radiohead'),
      ]);

      expect(index.owns(release('Amnesiac')), isFalse);
    });

    test('does not match the same title by a different artist', () {
      // Two records called Greatest Hits are routinely two records.
      final index = OwnedIndex([
        const OwnedAlbum(title: 'Greatest Hits', artist: 'Queen'),
      ]);

      expect(index.owns(release('Greatest Hits', artist: 'ABBA')), isFalse);
    });

    test('ignores the artist when told to', () {
      // What an artist page needs. The library spells performers however the
      // file tags did, and requiring "Beatles, The" to equal "The Beatles"
      // would report a complete discography as entirely missing.
      final index = OwnedIndex([
        const OwnedAlbum(title: 'Revolver', artist: 'Beatles, The'),
      ], requireArtist: false);

      expect(index.owns(release('Revolver', artist: 'The Beatles')), isTrue);
    });

    test('missingFrom keeps order and drops duplicates', () {
      final index = OwnedIndex([
        const OwnedAlbum(title: 'Amnesiac', artist: 'Radiohead'),
      ]);

      final missing = index.missingFrom([
        release('Kid A', mbid: 'a'),
        release('Amnesiac', mbid: 'b'),
        release('In Rainbows', mbid: 'c'),
        // MusicBrainz catalogues reissues as separate release groups often
        // enough that without deduplication the same missing album is offered
        // twice, with two different download buttons.
        release('In Rainbows', mbid: 'd'),
      ]);

      expect(missing.map((r) => r.title), ['Kid A', 'In Rainbows']);
    });
  });
}
