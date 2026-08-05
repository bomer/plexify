import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/sync/library_writer.dart';

/// The point of the normalised columns, finally used for what they were added
/// for. Searching is where a cache is most tempting to trust and most damaging
/// to trust: it must answer instantly from what it has, and must never be the
/// reason something is missing.
void main() {
  late AppDatabase db;
  late LibraryWriter writer;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    writer = LibraryWriter(db);

    await writer.writeArtists([
      const PlexArtist(ratingKey: 'ar1', title: 'Radiohead'),
      const PlexArtist(ratingKey: 'ar2', title: 'The Beatles'),
    ]);
    await writer.writeAlbums([
      const PlexAlbum(ratingKey: 'al1', title: 'Kid A', artist: 'Radiohead'),
      const PlexAlbum(
        ratingKey: 'al2',
        title: "Don't Look Back In Anger",
        artist: 'Oasis',
      ),
    ]);
    await writer.writeTracks([
      const PlexTrack(
        ratingKey: 't1',
        title: 'Idioteque',
        index: 1,
        durationMs: 1000,
        album: 'Kid A',
        artist: 'Radiohead',
      ),
    ]);
  });
  tearDown(() => db.close());

  test('finds the artist and their albums from an artist name', () async {
    final matches = await db.search('radiohead');

    // One query, sections kept apart: an artist is not competing with a track
    // for the same slot.
    expect(matches.artists.single.title, 'Radiohead');
    expect(matches.albums.single.title, 'Kid A');
  });

  test('a track is found by its own title', () async {
    expect((await db.search('idioteque')).tracks.single.title, 'Idioteque');
  });

  test('an artist name does not pull in their every track', () async {
    // A real limitation rather than a decision: `Tracks` has a normalised
    // title but no normalised artist, so there is nothing folded to match an
    // artist name against. Searching an artist gives the artist and their
    // albums, which is where you would go anyway; adding a
    // `normalisedArtist` column to `Tracks` is what would change this.
    expect((await db.search('radiohead')).tracks, isEmpty);
  });

  test('ignores case and punctuation', () async {
    // The whole reason the normalised columns exist. Nobody types the
    // apostrophe, and making them would be a search that only works for
    // people who already know the answer.
    expect((await db.search('dont look back')).albums, hasLength(1));
    expect((await db.search('DONT LOOK BACK')).albums, hasLength(1));
  });

  test('matches a word from the middle, not just the start', () async {
    // People search for the word they remember, not the first one. This is
    // what costs the index and buys the feature.
    expect((await db.search('anger')).albums, hasLength(1));
    expect((await db.search('beatles')).artists, hasLength(1));
  });

  test('finds an album by its artist as well as its title', () async {
    final matches = await db.search('oasis');

    expect(matches.albums.single.title, "Don't Look Back In Anger");
  });

  test('an empty query returns nothing rather than everything', () async {
    // A blank box matching the whole library would render fifty thousand rows
    // on the first frame of the screen.
    expect((await db.search('')).isEmpty, isTrue);
    expect((await db.search('   ')).isEmpty, isTrue);
  });

  test('a query matching nothing is empty, not an error', () async {
    expect((await db.search('zzzzz')).isEmpty, isTrue);
  });

  test('results are capped', () async {
    await writer.writeAlbums([
      for (var i = 0; i < 50; i++)
        PlexAlbum(ratingKey: 'x$i', title: 'Test $i', artist: 'Various'),
    ]);

    // Unbounded, a common word would build a list widget per matching row on
    // every keystroke.
    expect((await db.search('test', limit: 20)).albums, hasLength(20));
  });
}
