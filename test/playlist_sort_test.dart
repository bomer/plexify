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

  /// Records that this device started the playlist, which is what
  /// `LibraryWriter.markStarted` does when you press play.
  Future<void> played(String ratingKey, int at) => db
      .into(db.playbackHistory)
      .insert(
        PlaybackHistoryCompanion.insert(
          kind: 'playlist',
          ratingKey: ratingKey,
          startedAt: at,
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

  group('played here, not just viewed on the server', () {
    test('putting a playlist on moves it to the top', () async {
      // The bug this join exists for. Plexify reports playback against the
      // *track*, so Plex never learns a playlist was involved and its own
      // lastViewedAt never moves — the sidebar sat frozen however much you
      // listened.
      await insert('Never touched', lastViewedAt: 900);
      await insert('Played here');
      await played('Played here', 950);

      expect(await titles(PlaylistSort.recent), [
        'Played here',
        'Never touched',
      ]);
    });

    test('the server still wins when it is the newer of the two', () async {
      // A max rather than a coalesce. Played in Plexamp this morning and here
      // a month ago, the morning is the honest answer.
      await insert('Plexamp today', lastViewedAt: 2000);
      await insert('Here last month');
      await played('Here last month', 1000);

      expect(await titles(PlaylistSort.recent), [
        'Plexamp today',
        'Here last month',
      ]);
    });

    test('an album never lends its play time to a playlist', () async {
      // Both kinds share one table and ratingKeys are only unique per type, so
      // an unfiltered join would hand this playlist an album's listening.
      await insert('7');
      await insert('Genuinely recent', lastViewedAt: 500);
      await db
          .into(db.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              kind: 'album',
              ratingKey: '7',
              startedAt: 9999,
            ),
          );

      expect(await titles(PlaylistSort.recent), ['Genuinely recent', '7']);
    });

    test('one row per playlist, however it is joined', () async {
      await insert('Only once');
      await played('Only once', 100);

      expect(await titles(PlaylistSort.recent), ['Only once']);
    });
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
