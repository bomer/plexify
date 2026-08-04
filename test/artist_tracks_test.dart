import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/db/normalise.dart';

/// The artist track list is joined through albums rather than read off the
/// track, so ordering and membership both depend on the join being right.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> album(String key, String title, String artistKey, {int? year}) {
    return db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            ratingKey: key,
            title: title,
            normalisedTitle: normalise(title),
            artistRatingKey: Value(artistKey),
            artistTitle: 'Radiohead',
            normalisedArtist: normalise('Radiohead'),
            year: Value(year),
          ),
        );
  }

  Future<void> track(
    String key,
    String albumKey, {
    int disc = 1,
    int index = 1,
  }) {
    return db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            ratingKey: key,
            title: 'Track $key',
            normalisedTitle: normalise('Track $key'),
            albumRatingKey: Value(albumKey),
            discIndex: Value(disc),
            trackIndex: Value(index),
          ),
        );
  }

  test('returns every track by the artist, album-chronologically', () async {
    await album('b2', 'Amnesiac', 'a1', year: 2001);
    await album('b1', 'Kid A', 'a1', year: 2000);
    await track('t3', 'b2', index: 1);
    await track('t1', 'b1', index: 1);
    await track('t2', 'b1', index: 2);

    final rows = await db.watchTracksForArtist('a1').first;

    // Kid A (2000) before Amnesiac (2001), and within an album by track number
    // — a discography, not an arbitrary pile.
    expect(rows.map((t) => t.ratingKey), ['t1', 't2', 't3']);
  });

  test('excludes tracks belonging to other artists', () async {
    await album('b1', 'Kid A', 'a1', year: 2000);
    await album('b9', 'Debut', 'a2', year: 1993);
    await track('mine', 'b1');
    await track('theirs', 'b9');

    final rows = await db.watchTracksForArtist('a1').first;

    expect(rows.map((t) => t.ratingKey), ['mine']);
  });

  test('orders multi-disc releases by disc before track', () async {
    await album('b1', 'Long One', 'a1', year: 2000);
    await track('d2t1', 'b1', disc: 2, index: 1);
    await track('d1t2', 'b1', disc: 1, index: 2);
    await track('d1t1', 'b1', disc: 1, index: 1);

    final rows = await db.watchTracksForArtist('a1').first;

    expect(rows.map((t) => t.ratingKey), ['d1t1', 'd1t2', 'd2t1']);
  });

  test('albums with no year sort last rather than first', () async {
    await album('b1', 'Dated', 'a1', year: 2000);
    await album('b2', 'Undated', 'a1');
    await track('dated', 'b1');
    await track('undated', 'b2');

    final rows = await db.watchTracksForArtist('a1').first;

    // SQLite would otherwise put the NULL year first and head the list with
    // whatever Plex happened not to know the date of.
    expect(rows.map((t) => t.ratingKey), ['dated', 'undated']);
  });

  test('a track whose album is not cached is simply absent', () async {
    // The join cannot resolve an orphan. Acceptable because a full sync stores
    // albums before tracks, but worth pinning so the behaviour is known.
    await track('orphan', 'missing-album');

    expect(await db.watchTracksForArtist('a1').first, isEmpty);
  });
}
