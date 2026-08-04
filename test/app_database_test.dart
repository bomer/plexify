// drift exports an `isNull` query helper that collides with matcher's.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/db/normalise.dart';

/// Exercises the schema against a real in-memory SQLite database, so a broken
/// table definition or index fails here rather than on someone's phone.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('creates the schema and round-trips an album', () async {
    await db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            ratingKey: '45820',
            title: 'Kid A',
            normalisedTitle: normalise('Kid A'),
            artistTitle: 'Radiohead',
            normalisedArtist: normalise('Radiohead'),
            year: const Value(2000),
          ),
        );

    final stored = await db.select(db.albums).getSingle();
    expect(stored.title, 'Kid A');
    expect(stored.artistTitle, 'Radiohead');
    expect(stored.year, 2000);
    // Defaults must apply without being passed explicitly.
    expect(stored.mbid, isNull);
  });

  test('ratingKey is the primary key, so re-syncing an item replaces it',
      () async {
    Future<void> upsert(String title) => db
        .into(db.albums)
        .insertOnConflictUpdate(
          AlbumsCompanion.insert(
            ratingKey: '1',
            title: title,
            normalisedTitle: normalise(title),
            artistTitle: 'Radiohead',
            normalisedArtist: normalise('Radiohead'),
          ),
        );

    await upsert('Kid A');
    await upsert('Kid A (Remastered)');

    // A delta sync re-delivering a changed row must update it, not duplicate.
    final all = await db.select(db.albums).get();
    expect(all, hasLength(1));
    expect(all.single.title, 'Kid A (Remastered)');
  });

  test('normalised columns support prefix search', () async {
    for (final (key, title) in [
      ('1', "Don't Look Back"),
      ('2', 'Kid A'),
      ('3', 'Kidnapped'),
    ]) {
      await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              ratingKey: key,
              title: title,
              normalisedTitle: normalise(title),
              artistTitle: 'Various',
              normalisedArtist: normalise('Various'),
            ),
          );
    }

    final query = db.select(db.albums)
      ..where((a) => a.normalisedTitle.like('kid%'));
    final results = await query.get();

    expect(results.map((a) => a.title), containsAll(['Kid A', 'Kidnapped']));
    expect(results, hasLength(2));

    // Punctuation-free typing finds the apostrophe title.
    final apostrophe = db.select(db.albums)
      ..where((a) => a.normalisedTitle.like('dont%'));
    expect((await apostrophe.get()).single.title, "Don't Look Back");
  });

  test('playlist items keep explicit ordering', () async {
    await db.into(db.playlists).insert(
          PlaylistsCompanion.insert(
            ratingKey: 'p1',
            title: 'Focus',
            normalisedTitle: normalise('Focus'),
          ),
        );

    for (final (position, track) in [(2, 'c'), (0, 'a'), (1, 'b')]) {
      await db.into(db.playlistItems).insert(
            PlaylistItemsCompanion.insert(
              playlistRatingKey: 'p1',
              trackRatingKey: track,
              position: position,
            ),
          );
    }

    final query = db.select(db.playlistItems)
      ..orderBy([(t) => OrderingTerm.asc(t.position)]);
    final ordered = await query.get();

    // Playlists are arranged, not sorted — insertion order must not matter.
    expect(ordered.map((i) => i.trackRatingKey), ['a', 'b', 'c']);
  });

  test('clearLibrary empties every table', () async {
    await db.into(db.artists).insert(
          ArtistsCompanion.insert(
            ratingKey: 'a1',
            title: 'Radiohead',
            normalisedTitle: normalise('Radiohead'),
          ),
        );
    await db.into(db.syncState).insert(
          SyncStateCompanion.insert(
            sectionKey: '3',
            serverClientIdentifier: 'server-abc',
          ),
        );

    await db.clearLibrary();

    // Switching servers must not leave rows behind: Plex ratingKeys are only
    // unique within a server, so stale rows would blend two libraries.
    expect(await db.select(db.artists).get(), isEmpty);
    expect(await db.select(db.syncState).get(), isEmpty);
  });

  test('sync state defaults mark the initial sync incomplete', () async {
    await db.into(db.syncState).insert(
          SyncStateCompanion.insert(
            sectionKey: '3',
            serverClientIdentifier: 'server-abc',
          ),
        );

    final state = await db.select(db.syncState).getSingle();
    // An interrupted first pass must be distinguishable from an up-to-date
    // cache, or resuming would be mistaken for being done.
    expect(state.initialSyncComplete, isFalse);
    expect(state.lastSyncedUpdatedAt, 0);
  });
}
