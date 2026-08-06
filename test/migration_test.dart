import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/app_database.dart';

/// Each migration here exists to fix a specific silent failure, so each test
/// asserts the fix rather than the mechanics.
///
/// One constraint shapes all of them: `NativeDatabase.memory()` creates the
/// schema at **head**, not at the version being migrated *from*. Running
/// `onUpgrade` against it therefore re-runs DDL for columns that already
/// exist. Where a migration adds a column, the test drops it first — that is
/// what makes the ALTER genuinely exercised rather than skipped over.
///
/// The `to` argument is always [AppDatabase.schemaVersion]'s current value.
/// Passing an intermediate version would be fiction: drift only ever calls
/// this with the real head, and the branches inside test `from`, so an
/// install arriving from v2 runs the v3 *and* v4 bodies in one pass.
void main() {
  /// Puts a head-schema database back into the shape it had before the
  /// migrations under test.
  ///
  /// `NativeDatabase.memory()` creates the schema at head, so every DDL
  /// migration would otherwise re-add a column that is already there. Each
  /// test drops whatever the branches it triggers will add, which is what
  /// makes the ALTER genuinely exercised rather than skipped over.
  ///
  /// Indexes go too: `createIndex` is not idempotent against one that exists.
  Future<void> dropPartSizeColumn(AppDatabase db) =>
      db.customStatement('ALTER TABLE tracks DROP COLUMN part_size_bytes');

  Future<void> dropArtistRating(AppDatabase db) async {
    await db.customStatement('DROP INDEX IF EXISTS idx_artists_rating');
    await db.customStatement('ALTER TABLE artists DROP COLUMN user_rating');
  }

  test(
    'arriving from v2 rewinds the delta cursor so ratings get backfilled',
    () async {
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

      // Simulate arriving from v2, where the rating columns exist but are empty
      // and the part size does not exist at all.
      await dropPartSizeColumn(db);
      await dropArtistRating(db);
      final migrator = db.createMigrator();
      await db.migration.onUpgrade(migrator, 2, 6);

      final state = await db.select(db.syncState).getSingle();
      expect(state.lastSyncedUpdatedAt, 0);

      // Everything else has to survive: rewinding the cursor must cost one extra
      // sync pass, not the whole cache.
      expect(state.initialSyncComplete, isTrue);
      expect(state.serverClientIdentifier, 'server-1');
    },
  );

  test('v4 adds the part size without disturbing existing rows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            ratingKey: 't1',
            title: 'Everything In Its Right Place',
            normalisedTitle: 'everything in its right place',
            durationMs: const Value(251946),
            partKey: const Value('/library/parts/9931/file.flac'),
          ),
        );

    await dropPartSizeColumn(db);
    await dropArtistRating(db);
    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 3, 6);

    // Unlike v3 this deliberately does *not* rewind the sync cursor: a null
    // part size degrades to "nothing measured", which QualityPolicy treats
    // exactly as it behaved before the column existed. The row survives, and
    // the next sync that touches this track fills it in.
    final row = await db.select(db.tracks).getSingle();
    expect(row.partSizeBytes, isNull);
    expect(row.partKey, '/library/parts/9931/file.flac');
    expect(row.durationMs, 251946);
  });

  test('an install already at head is left alone', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            sectionKey: '3',
            serverClientIdentifier: 'server-1',
            lastSyncedUpdatedAt: const Value(999999),
          ),
        );

    // No branch should fire, so nothing should move. In particular the cursor
    // must not be rewound a second time, which would cost a full sync pass on
    // every launch.
    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 6, 6);

    final state = await db.select(db.syncState).getSingle();
    expect(state.lastSyncedUpdatedAt, 999999);
  });

  test(
    'a fresh database is created at the current version, not migrated',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Touching the newest column proves the schema is current without
      // asserting on a version number that will keep moving.
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              ratingKey: 't1',
              title: 'Kid A',
              normalisedTitle: 'kid a',
              partSizeBytes: const Value(3000000),
            ),
          );

      expect((await db.select(db.tracks).getSingle()).partSizeBytes, 3000000);
      expect(await db.select(db.syncState).get(), isEmpty);
    },
  );

  test('v6 adds the artist rating without disturbing existing rows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.artists)
        .insert(
          ArtistsCompanion.insert(
            ratingKey: 'ar1',
            title: 'Radiohead',
            normalisedTitle: 'radiohead',
          ),
        );

    await dropArtistRating(db);
    final migrator = db.createMigrator();
    await db.migration.onUpgrade(migrator, 5, 6);

    // No cursor rewind, unlike v3: an unrated artist and one whose rating has
    // not synced yet look identical to the filter, and the next pass that
    // touches the row fills it in.
    final row = await db.select(db.artists).getSingle();
    expect(row.userRating, isNull);
    expect(row.title, 'Radiohead');
  });
}
