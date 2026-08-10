import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/db/normalise.dart';

/// How the Favourites shelf is ordered.
///
/// Alphabetical within a rating tier reads as sensible and is not: most
/// favourites end up at the same four or five stars, so the row degenerates to
/// whichever artists happen to start with A and never moves again.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> insert(
    String title, {
    required int rating,
    required String artist,
    int? addedAt,
  }) => db
      .into(db.albums)
      .insert(
        AlbumsCompanion.insert(
          ratingKey: title,
          title: title,
          normalisedTitle: normalise(title),
          artistTitle: artist,
          normalisedArtist: normalise(artist),
          userRating: Value(rating),
          addedAt: Value(addedAt),
        ),
      );

  Future<List<String>> titles() async => [
    for (final row in await db.watchFavouriteAlbums().first) row.title,
  ];

  test('five stars come before four', () async {
    await insert('Four', rating: 8, artist: 'Aardvark', addedAt: 900);
    await insert('Five', rating: 10, artist: 'Zebra', addedAt: 100);

    expect(await titles(), ['Five', 'Four']);
  });

  test('newest first within a rating, not alphabetical', () async {
    await insert('Old', rating: 10, artist: 'Aardvark', addedAt: 100);
    await insert('New', rating: 10, artist: 'Zebra', addedAt: 900);

    // Alphabetically 'Aardvark' wins, and that is the behaviour being
    // replaced: an album rated last week should be visible without scrolling
    // past two hundred that were not.
    expect(await titles(), ['New', 'Old']);
  });

  test('an album with no added date sorts last, not first', () async {
    await insert('Dated', rating: 10, artist: 'Zebra', addedAt: 100);
    await insert('Undated', rating: 10, artist: 'Aardvark');

    expect(await titles(), ['Dated', 'Undated']);
  });

  test('nothing below four stars is a favourite', () async {
    await insert('Three', rating: 6, artist: 'A', addedAt: 900);
    await insert('Four', rating: 8, artist: 'B', addedAt: 100);

    expect(await titles(), ['Four']);
  });

  test('a full tie is still deterministic', () async {
    // Same rating and same added date. Without a final tiebreak the row would
    // reshuffle between rebuilds for no reason a reader could see.
    await insert('Zed', rating: 10, artist: 'Zebra', addedAt: 500);
    await insert('Ann', rating: 10, artist: 'Aardvark', addedAt: 500);

    expect(await titles(), ['Ann', 'Zed']);
  });
}
