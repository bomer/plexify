import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/db/normalise.dart';

/// Sorting is read straight off indexed normalised columns, so these also
/// guard that the indexes stay aligned with what the UI asks for.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> add(
    String key,
    String title,
    String artist, {
    int? addedAt,
    int? year,
  }) {
    return db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            ratingKey: key,
            title: title,
            normalisedTitle: normalise(title),
            artistTitle: artist,
            normalisedArtist: normalise(artist),
            addedAt: Value(addedAt),
            year: Value(year),
          ),
        );
  }

  test('recently added puts the newest first', () async {
    await add('1', 'Old', 'A', addedAt: 100);
    await add('2', 'New', 'B', addedAt: 300);
    await add('3', 'Middle', 'C', addedAt: 200);

    final rows = await db.watchAlbums(sort: AlbumSort.recentlyAdded).first;

    expect(rows.map((a) => a.title), ['New', 'Middle', 'Old']);
  });

  test('title sort ignores punctuation and case', () async {
    await add('1', 'the beatles', 'X');
    await add('2', "'Allo", 'Y');
    await add('3', 'Zebra', 'Z');

    final rows = await db.watchAlbums(sort: AlbumSort.title).first;

    // Sorting on the normalised column means a leading apostrophe does not
    // strand "'Allo" before everything else the way raw ASCII ordering would.
    expect(rows.map((a) => a.title), ['\'Allo', 'the beatles', 'Zebra']);
  });

  test(
    'artist sort groups an artist and orders their albums by year',
    () async {
      await add('1', 'Amnesiac', 'Radiohead', year: 2001);
      await add('2', 'Kid A', 'Radiohead', year: 2000);
      await add('3', 'Debut', 'Björk', year: 1993);

      final rows = await db.watchAlbums(sort: AlbumSort.artist).first;

      // Björk normalises to "bjork", so it sorts before Radiohead.
      expect(rows.map((a) => a.title), ['Debut', 'Kid A', 'Amnesiac']);
    },
  );

  test('the stream re-emits as sync writes rows', () async {
    final emissions = <int>[];
    final sub = db.watchAlbums().listen((rows) => emissions.add(rows.length));

    await add('1', 'One', 'A');
    await add('2', 'Two', 'B');
    // Let drift deliver the updates.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    // The grid must fill progressively during the first sync rather than
    // appearing all at once when it finishes.
    expect(emissions.last, 2);
    expect(emissions.length, greaterThan(1));
  });

  test('counts reflect what is actually cached', () async {
    expect(await db.countAlbums(), 0);
    await add('1', 'One', 'A');
    await add('2', 'Two', 'B');
    expect(await db.countAlbums(), 2);
  });

  test('tracks come back in disc then track order', () async {
    Future<void> track(String key, int disc, int index) => db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            ratingKey: key,
            title: 'Track $key',
            normalisedTitle: normalise('Track $key'),
            albumRatingKey: const Value('album1'),
            discIndex: Value(disc),
            trackIndex: Value(index),
          ),
        );

    await track('c', 2, 1);
    await track('a', 1, 1);
    await track('b', 1, 2);

    final rows = await db.watchTracksForAlbum('album1').first;

    // A two-disc release must not interleave; disc ordering wins.
    expect(rows.map((t) => t.ratingKey), ['a', 'b', 'c']);
  });
}
