import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/core/settings/app_settings.dart';
import 'package:plexify/features/library/album_detail_screen.dart';
import 'package:plexify/features/library/artist_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Getting from an album to the artist who made it.
///
/// The artist name on an album header was plain text, so the artist page — which
/// is now where missing albums live — was reachable only by going back out to
/// Library and finding them again. "What else did they make" was several taps
/// from the album already on screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  const album = PlexAlbum(
    ratingKey: 'al1',
    title: 'Kid A',
    artist: 'Radiohead',
    artistRatingKey: 'ar1',
  );

  Future<void> pumpAlbum(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(
          SettingsStore(await SharedPreferences.getInstance()),
        ),
        tracksProvider.overrideWith(
          (ref, key) => Stream.value(const <PlexTrack>[]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AlbumDetailScreen(album: album)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the artist name opens the artist', (tester) async {
    await db
        .into(db.artists)
        .insert(
          ArtistsCompanion.insert(
            ratingKey: 'ar1',
            title: 'Radiohead',
            normalisedTitle: 'radiohead',
          ),
        );

    await pumpAlbum(tester);
    await tester.tap(find.text('Radiohead'));
    await tester.pumpAndSettle();

    expect(find.byType(ArtistDetailScreen), findsOneWidget);
  });

  testWidgets('an artist the cache has not reached stays plain text', (
    tester,
  ) async {
    // No artist row. Following the same rule as Now Playing: a link that opens
    // an empty page is worse than a label, and this happens for real — an album
    // browsed before sync has walked the artists, or one Plex filed with no
    // parent at all.
    await pumpAlbum(tester);
    await tester.tap(find.text('Radiohead'));
    await tester.pumpAndSettle();

    expect(find.byType(ArtistDetailScreen), findsNothing);
    expect(find.byType(AlbumDetailScreen), findsOneWidget);
  });

  testWidgets('the link follows the cache, not the pushed snapshot', (
    tester,
  ) async {
    // Plex renames artists, and the album was pushed with whatever string the
    // grid held at the time. Reading the row back means the header agrees with
    // the page it opens rather than with a stale copy.
    await db
        .into(db.artists)
        .insert(
          ArtistsCompanion.insert(
            ratingKey: 'ar1',
            title: 'Radiohead (UK)',
            normalisedTitle: 'radiohead uk',
            userRating: const Value(8),
          ),
        );

    await pumpAlbum(tester);

    expect(find.text('Radiohead (UK)'), findsOneWidget);
    expect(find.text('Radiohead'), findsNothing);
  });
}
