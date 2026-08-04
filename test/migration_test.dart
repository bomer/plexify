import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/app_database.dart';

/// The v3 migration exists to fix a specific silent failure: an install that
/// synced under v1 has rating columns that a delta sync can never fill, because
/// Plex's `updatedAt` for a track rated months ago has not moved since.
void main() {
  test('v3 rewinds the delta cursor so ratings get backfilled', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            sectionKey: '3',
            serverClientIdentifier: 'server-1',
            lastSyncedUpdatedAt: const Value(999999),
            initialSyncComplete: const Value(true),
          ),
        );

    // Simulate arriving from v2, where the rating columns exist but are empty.
    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 2, 3);

    final state = await db.select(db.syncState).getSingle();
    expect(state.lastSyncedUpdatedAt, 0);

    // Everything else has to survive: rewinding the cursor must cost one extra
    // sync pass, not the whole cache.
    expect(state.initialSyncComplete, isTrue);
    expect(state.serverClientIdentifier, 'server-1');
  });

  test(
    'a fresh database is created at the current version, not migrated',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Touching a v2 column proves the schema is current without asserting on a
      // version number that will keep moving.
      await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              ratingKey: 'b1',
              title: 'Kid A',
              normalisedTitle: 'kid a',
              artistTitle: 'Radiohead',
              normalisedArtist: 'radiohead',
              userRating: const Value(10),
            ),
          );

      expect((await db.select(db.albums).getSingle()).userRating, 10);
      expect(await db.select(db.syncState).get(), isEmpty);
    },
  );
}
