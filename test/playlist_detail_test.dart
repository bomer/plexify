import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/core/settings/app_settings.dart';
import 'package:plexify/features/library/cover_frame.dart';
import 'package:plexify/features/library/detail_back.dart';
import 'package:plexify/features/library/playlist_detail_screen.dart';
import 'package:plexify/features/library/star_rating.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The playlist page, which was a bare list and is now shaped like the album
/// page.
///
/// Worth testing rather than eyeballing: the sidebar shows a playlist's mosaic,
/// so opening one and landing on a page with no artwork read as the wrong
/// screen having loaded, and "the header is there" is exactly the kind of thing
/// that is obvious in a screenshot and invisible in a diff.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  const playlist = PlexPlaylist(
    ratingKey: 'pl1',
    title: 'SockRocking',
    thumb: '/library/metadata/pl1/composite/1',
    itemCount: 2,
  );

  PlexTrack track(String title, int ms) => PlexTrack(
    ratingKey: title,
    title: title,
    index: 1,
    durationMs: ms,
    album: 'Howl Sessions',
    artist: 'Black Rebel Motorcycle Club',
    partKey: '/library/parts/1/file.mp3',
  );

  /// [width] decides whether per-row stars are offered, which is a layout
  /// decision rather than a platform one.
  Future<void> pump(
    WidgetTester tester, {
    List<PlexTrack> tracks = const [],
    double width = 1400,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(
          SettingsStore(await SharedPreferences.getInstance()),
        ),
        playlistTracksProvider.overrideWith((ref, key) => Stream.value(tracks)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PlaylistDetailScreen(playlist: playlist),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the mosaic, the title and what it holds', (tester) async {
    await pump(
      tester,
      tracks: [track('Mercy', 210000), track('La Da Da', 195000)],
    );

    // The header is the whole point of the change. A playlist has artwork in
    // the sidebar and had none on its own page.
    expect(find.byType(CoverFrame), findsOneWidget);
    // Once, not twice. The app bar printed the title a second time six lines
    // above the header that already said it, and cost a band of chrome and a
    // hard line across the gradient to do it.
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('SockRocking'), findsOneWidget);
    expect(find.text('Playlist'), findsOneWidget);
    expect(find.text('2 songs · 6 min 45 sec'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);
  });

  testWidgets('rows are numbered by position in the playlist', (tester) async {
    await pump(
      tester,
      tracks: [track('Mercy', 210000), track('La Da Da', 195000)],
    );

    // Playlist order is an arrangement, so the number is the position here and
    // not the track number it happens to carry on its own album — both of
    // these are `index: 1`.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('every row carries its length', (tester) async {
    await pump(tester, tracks: [track('Mercy', 210000)]);
    expect(find.text('3:30'), findsOneWidget);
  });

  testWidgets('stars are offered with room and withheld without', (
    tester,
  ) async {
    await pump(tester, tracks: [track('Mercy', 210000)]);
    expect(find.byType(StarRating), findsOneWidget);

    // Five stars per row eats most of a phone's width and pushes the title
    // into an ellipsis, so there a long press opens the same rating.
    await pump(tester, tracks: [track('Mercy', 210000)], width: 500);
    expect(find.byType(StarRating), findsNothing);
  });

  testWidgets('an empty playlist still says which one it is', (tester) async {
    await pump(tester);

    // The header stays. A bare sentence in the middle of the screen gives no
    // clue what you opened, and an empty playlist is a real thing to look at.
    expect(find.byType(CoverFrame), findsOneWidget);
    expect(find.text('This playlist is empty.'), findsOneWidget);
    expect(find.text('0 songs · 0 sec'), findsOneWidget);
  });

  testWidgets('back is reachable without scrolling to the top', (tester) async {
    await pump(
      tester,
      tracks: [for (var i = 0; i < 60; i++) track('Track $i', 200000)],
    );

    // Pinned rather than scrolled away with the header: back is the control
    // you reach for at any point down a long list, and having to scroll up to
    // find it would be worse than the bar it replaced.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();

    expect(find.byType(DetailBack), findsOneWidget);
    expect(find.text('SockRocking'), findsNothing);
  });

  testWidgets('a smart playlist says so, because its contents move', (
    tester,
  ) async {
    const smart = PlexPlaylist(
      ratingKey: 'pl2',
      title: 'My Top Rated',
      smart: true,
    );

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(
          SettingsStore(await SharedPreferences.getInstance()),
        ),
        playlistTracksProvider.overrideWith(
          (ref, key) => Stream.value([track('Mercy', 210000)]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PlaylistDetailScreen(playlist: smart)),
      ),
    );
    await tester.pumpAndSettle();

    // The one fact that changes how to read the page: what is here today is
    // not necessarily what was here last week.
    expect(find.text('Smart playlist'), findsOneWidget);
    expect(find.text('Playlist'), findsNothing);
  });
}
