import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/features/library/album_detail_screen.dart';
import 'package:plexify/features/library/rating_controller.dart';
import 'package:plexify/features/library/star_rating.dart';

/// Star rows are the single widest thing in a track list. On a phone they push
/// the title into an ellipsis, so they are desktop-only and long press stands in
/// for them.
void main() {
  const album = PlexAlbum(
    ratingKey: 'b1',
    title: 'Kid A',
    artist: 'Radiohead',
    userRating: 8,
  );

  final tracks = [
    for (var i = 1; i <= 3; i++)
      PlexTrack(
        ratingKey: 't$i',
        title: 'Track $i',
        index: i,
        durationMs: 200000,
        album: 'Kid A',
        artist: 'Radiohead',
        partKey: '/library/parts/$i/file.flac',
      ),
  ];

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          plexClientProvider.overrideWithValue(null),
          ratingControllerProvider.overrideWithValue(null),
          albumsProvider.overrideWith((ref) => Stream.value([album])),
          tracksProvider.overrideWith((ref, key) => Stream.value(tracks)),
        ],
        child: const MaterialApp(home: AlbumDetailScreen(album: album)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a phone-width album page shows no per-track stars', (
    tester,
  ) async {
    await pumpAt(tester, const Size(400, 900));

    // One star row remains: the album's own, in the header. Removing that too
    // would leave no way to rate anything from this screen.
    expect(find.byType(StarRating), findsOneWidget);
  });

  testWidgets('a desktop-width album page rates tracks inline', (tester) async {
    await pumpAt(tester, const Size(1200, 900));

    // The header plus one per track.
    expect(find.byType(StarRating), findsNWidgets(1 + tracks.length));
  });

  testWidgets('long press rates a track on a phone', (tester) async {
    await pumpAt(tester, const Size(400, 900));

    await tester.longPress(find.text('Track 2'));
    await tester.pumpAndSettle();

    // The sheet is the only route to a track rating on a narrow layout, so it
    // has to actually open.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(StarRating), findsNWidgets(2));
  });

  testWidgets('a narrow phone album header does not overflow', (tester) async {
    // 360dp is the common Android width; the header was only ever eyeballed
    // at 400. An overflow is a thrown exception in tests, so this fails
    // loudly rather than needing someone to spot a yellow banner.
    await pumpAt(tester, const Size(360, 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a very narrow phone album header does not overflow', (
    tester,
  ) async {
    await pumpAt(tester, const Size(320, 700));
    expect(tester.takeException(), isNull);
  });
}
