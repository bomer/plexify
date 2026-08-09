import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/audio/playback_handler.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/core/settings/app_settings.dart';
import 'package:plexify/features/library/album_detail_screen.dart';
import 'package:plexify/features/library/library_screen.dart';
import 'package:plexify/features/player/now_playing_screen.dart';
import 'package:plexify/features/player/player_providers.dart';
import 'package:plexify/shell/app_shell.dart';
import 'package:plexify/shell/shell_destination.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_just_audio.dart';

/// docs/PLAN.md calls this invariant non-retrofittable, and it is the reason
/// the shell is shaped the way it is: Now Playing is a sibling layer in a
/// [Stack], not a pushed route, so the screen underneath is never unmounted.
///
/// Nothing enforced it. Expanding the player over a pushed route would look
/// perfectly fine on the way in, and only show itself on the way back out,
/// when the album you were reading has been replaced by the top of the grid
/// and your place in it is gone. That is the exact bug the routing was
/// restructured to kill in #12, and every change to the shell since has been
/// able to reintroduce it silently.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late PlexifyAudioHandler handler;

  const album = PlexAlbum(ratingKey: 'b1', title: 'Kid A', artist: 'Radiohead');

  /// Enough tracks that the detail list is taller than the viewport, which is
  /// what makes a scroll position exist to preserve.
  final tracks = [
    for (var i = 1; i <= 40; i++)
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

  setUp(() async {
    FakeJustAudio.install();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await handler.dispose();
    await db.close();
  });

  Future<ProviderContainer> pumpShell(WidgetTester tester) async {
    // `AudioPlayer` initialisation waits on locks that never resolve inside
    // `testWidgets`' fake-async zone, so it has to be built in real async.
    await tester.runAsync(() async => handler = PlexifyAudioHandler());
    handler.mediaItem.add(
      const MediaItem(id: 'https://tower/1', title: 'Idioteque'),
    );

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioHandlerProvider.overrideWithValue(handler),
        plexIdentityProvider.overrideWithValue(PlexIdentity.forTesting()),
        settingsStoreProvider.overrideWithValue(
          SettingsStore(await SharedPreferences.getInstance()),
        ),
        // The OS transport stream is a platform channel; the shell only wants
        // it as a prompt to re-check, and there is nothing to re-check here.
        networkChangesProvider.overrideWithValue(const Stream<void>.empty()),
        albumsProvider.overrideWith((ref) => Stream.value([album])),
        tracksProvider.overrideWith((ref, key) => Stream.value(tracks)),
      ],
    );
    addTearDown(container.dispose);

    // Desktop width, so the sidebar carries navigation and the bottom bar is
    // out of the way of the finders below.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// The album page's own scroll view, not whichever `Scrollable` happens to
  /// be last in the tree, which on a wide layout is the sidebar's.
  double albumScrollOffset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(AlbumDetailScreen, skipOffstage: false),
              matching: find.byType(Scrollable),
              skipOffstage: false,
            )
            .first,
      )
      .position
      .pixels;

  /// Opens Library, taps into the album, and scrolls its track list.
  Future<double> openAlbumAndScroll(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    container.read(shellDestinationProvider.notifier).state =
        ShellDestination.library;
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kid A').first);
    await tester.pumpAndSettle();
    expect(find.byType(AlbumDetailScreen), findsOneWidget);

    await tester.drag(find.text('Track 3'), const Offset(0, -400));
    await tester.pumpAndSettle();

    final position = albumScrollOffset(tester);
    expect(position, greaterThan(0), reason: 'nothing scrolled to preserve');
    return position;
  }

  testWidgets('the page underneath stays mounted while Now Playing is open', (
    tester,
  ) async {
    final container = await pumpShell(tester);
    await openAlbumAndScroll(tester, container);

    container.read(nowPlayingExpandedProvider.notifier).state = true;
    await tester.pumpAndSettle();

    // Both at once is the whole point. A pushed route would have replaced the
    // album page rather than covering it, and this is the assertion that
    // tells the two apart.
    expect(find.byType(NowPlayingScreen), findsOneWidget);
    expect(find.byType(AlbumDetailScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('dismissing it returns you exactly where you were', (
    tester,
  ) async {
    final container = await pumpShell(tester);
    final before = await openAlbumAndScroll(tester, container);

    container.read(nowPlayingExpandedProvider.notifier).state = true;
    await tester.pumpAndSettle();
    container.read(nowPlayingExpandedProvider.notifier).state = false;
    await tester.pumpAndSettle();

    // Still on the album, and still at the same place in it. Losing the
    // scroll offset is how an unmount shows itself even when the route
    // happens to be rebuilt correctly.
    expect(find.byType(AlbumDetailScreen), findsOneWidget);
    expect(albumScrollOffset(tester), before);
  });

  testWidgets('switching tabs underneath it does not lose the album', (
    tester,
  ) async {
    final container = await pumpShell(tester);
    final before = await openAlbumAndScroll(tester, container);

    container.read(shellDestinationProvider.notifier).state =
        ShellDestination.home;
    await tester.pumpAndSettle();
    container.read(shellDestinationProvider.notifier).state =
        ShellDestination.library;
    await tester.pumpAndSettle();

    // Each destination keeps its own navigator in an IndexedStack, so leaving
    // and coming back must land back inside the album rather than at the top
    // of the grid.
    expect(find.byType(AlbumDetailScreen), findsOneWidget);
    expect(albumScrollOffset(tester), before);
  });

  testWidgets('the library grid is still there beneath the album', (
    tester,
  ) async {
    final container = await pumpShell(tester);
    await openAlbumAndScroll(tester, container);

    // The album is a pushed route inside the tab's own navigator, so the grid
    // it came from is offstage rather than gone. If this ever finds nothing,
    // the nested navigator has been flattened onto the root one and the mini
    // player is about to start getting covered again.
    expect(find.byType(LibraryScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('tapping the tab you are already on goes back to its root', (
    tester,
  ) async {
    final container = await pumpShell(tester);
    await openAlbumAndScroll(tester, container);

    // Reported as "Home doesn't take me home if I'm in an album". Each tab
    // keeps its own navigator, so an album opened from a shelf lives on *that*
    // tab's stack — and pressing the tab changed no state, so nothing moved.
    // The app bar's back arrow was the only way out.
    await tester.tap(find.text(ShellDestination.library.label));
    await tester.pumpAndSettle();

    expect(find.byType(AlbumDetailScreen), findsNothing);
    expect(find.byType(LibraryScreen), findsOneWidget);
  });

  testWidgets('switching to a different tab leaves its stack alone', (
    tester,
  ) async {
    final container = await pumpShell(tester);
    final before = await openAlbumAndScroll(tester, container);

    // The other half of the rule, and the one that would be easy to break
    // while fixing the first: only the *current* destination pops. Coming back
    // to a half-read album is the whole point of per-tab navigators, and
    // resetting on the way in would throw it away.
    await tester.tap(find.text(ShellDestination.home.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ShellDestination.library.label));
    await tester.pumpAndSettle();

    expect(find.byType(AlbumDetailScreen), findsOneWidget);
    expect(albumScrollOffset(tester), before);
  });
}
