import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/db/normalise.dart';

/// Ordering the playlist list, and the one rule that is not obvious.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> insert(String title, {bool smart = false, int? lastViewedAt}) =>
      db
          .into(db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              ratingKey: title,
              title: title,
              normalisedTitle: normalise(title),
              smart: Value(smart),
              lastViewedAt: Value(lastViewedAt),
            ),
          );

  Future<List<String>> titles(PlaylistSort sort, {int? limit}) async => [
    for (final row in await db.watchPlaylists(sort: sort, limit: limit).first)
      row.title,
  ];

  test('recent puts what you opened last at the top', () async {
    await insert('Old', lastViewedAt: 100);
    await insert('Newest', lastViewedAt: 900);
    await insert('Middle', lastViewedAt: 500);

    expect(await titles(PlaylistSort.recent), ['Newest', 'Middle', 'Old']);
  });

  test('a playlist never opened sorts below every one that has been', () async {
    // Nulls last, or the whole list of things you have never touched sits
    // above the one you were listening to an hour ago.
    await insert('Never');
    await insert('Yesterday', lastViewedAt: 100);

    expect(await titles(PlaylistSort.recent), ['Yesterday', 'Never']);
  });

  test('recent does not group smart playlists', () async {
    // Recent is already an order of relevance. Grouping by kind on top of it
    // would fight the only thing it is for.
    await insert('Hand made', lastViewedAt: 900);
    await insert('Generated', smart: true, lastViewedAt: 100);

    expect(await titles(PlaylistSort.recent), ['Hand made', 'Generated']);
  });

  group('by name', () {
    Future<void> seed() async {
      await insert('Beta');
      await insert('Alpha');
      await insert('Zulu');
      await insert('Smart B', smart: true);
      await insert('Smart A', smart: true);
    }

    test(
      'smart playlists come first, alphabetically within themselves',
      () async {
        await seed();
        expect(await titles(PlaylistSort.titleAsc), [
          'Smart A',
          'Smart B',
          'Alpha',
          'Beta',
          'Zulu',
        ]);
      },
    );

    test('Z to A reverses the alphabet, not the grouping', () async {
      // The easy mistake, and it looks deliberate when it happens: flipping
      // the whole ordering sends smart playlists to the bottom, so the group
      // you asked to have at the top is exactly where it is not.
      await seed();
      expect(await titles(PlaylistSort.titleDesc), [
        'Smart B',
        'Smart A',
        'Zulu',
        'Beta',
        'Alpha',
      ]);
    });

    test('sorting is punctuation-blind, like everywhere else', () async {
      await insert('the beths');
      await insert('A Playlist');

      expect(await titles(PlaylistSort.titleAsc), ['A Playlist', 'the beths']);
    });
  });

  test(
    'the sidebar takes the most recent, whatever the screen is sorted by',
    () async {
      await insert('Aaa', lastViewedAt: 100);
      await insert('Zzz', lastViewedAt: 900);

      // The sidebar asks for its own order rather than slicing the list the
      // Playlists screen is showing. Taking the first few of an A to Z list
      // would turn the sidebar into an alphabetical stub the moment someone
      // changed the sort somewhere else.
      expect(await titles(PlaylistSort.recent, limit: 1), ['Zzz']);
    },
  );
}
