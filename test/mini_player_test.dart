import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/audio/playback_handler.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/features/player/mini_player.dart';
import 'package:plexify/features/player/player_providers.dart';

import 'support/fake_just_audio.dart';

/// The mini player is the one widget on screen at all times, so anything
/// wasteful about it is wasteful everywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(FakeJustAudio.install);

  /// A phone-shaped viewport with a gesture-bar inset, which is the condition
  /// the height bug needed — on a device with no inset it looked fine.
  ///
  /// [width] decides which of the bar's two shapes is built, since the split is
  /// on available width rather than on platform.
  Future<double> pumpHeight(
    WidgetTester tester, {
    required bool aboveNavigationBar,
    double bottomInset = 34,
    Stream<bool>? reconnecting,
    double width = 400,
  }) async {
    // **The surface has to be resized, not just the MediaQuery.** Overriding
    // MediaQuery alone decides which shape gets built and leaves it laid out
    // in the default 800x600 window, so a "1200px" test measured a 800px bar
    // and the first centring assertion failed against a number that was right.
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Built inside `runAsync` because `AudioPlayer`'s initialisation waits on
    // locks that never resolve in `testWidgets`' fake-async zone — the whole
    // test hangs rather than failing.
    late final PlexifyAudioHandler handler;
    await tester.runAsync(() async => handler = PlexifyAudioHandler());
    addTearDown(handler.dispose);
    handler.mediaItem.add(
      const MediaItem(
        id: 'https://tower.example/stream',
        title: 'Everything In Its Right Place',
        artist: 'Radiohead',
        duration: Duration(minutes: 4),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          reconnectingProvider.overrideWith(
            (ref) => reconnecting ?? Stream.value(false),
          ),
        ],
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            padding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: const SizedBox.shrink(),
              bottomNavigationBar: MiniPlayer(
                aboveNavigationBar: aboveNavigationBar,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    return tester.getSize(find.byType(MiniPlayer)).height;
  }

  testWidgets('does not reserve the system inset when a nav bar is below it', (
    tester,
  ) async {
    final height = await pumpHeight(tester, aboveNavigationBar: true);

    // 64 for the row, 2 for the progress hairline. The gesture-bar inset
    // belongs to the NavigationBar underneath; claiming it here pads for a
    // screen edge two widgets away and visibly doubles the bar.
    expect(height, 66);
  });

  testWidgets('does reserve it when it is the bottom-most thing', (
    tester,
  ) async {
    final height = await pumpHeight(tester, aboveNavigationBar: false);

    // On a wide layout the sidebar carries navigation, so nothing sits below
    // and the inset is genuinely this widget's to honour.
    expect(height, 66 + 34);
  });

  testWidgets('says so while reconnecting', (tester) async {
    await pumpHeight(
      tester,
      aboveNavigationBar: true,
      reconnecting: Stream.value(true),
    );

    // A reconnect takes seconds and playback has usually just stopped, so
    // without this the player sits silent and looks broken.
    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.text('Radiohead'), findsNothing);
  });

  testWidgets('shows the artist the rest of the time', (tester) async {
    await pumpHeight(tester, aboveNavigationBar: true);

    expect(find.text('Radiohead'), findsOneWidget);
    expect(find.text('Reconnecting…'), findsNothing);
  });

  testWidgets('reconnecting does not change the height', (tester) async {
    final settled = await pumpHeight(tester, aboveNavigationBar: true);
    final during = await pumpHeight(
      tester,
      aboveNavigationBar: true,
      reconnecting: Stream.value(true),
    );

    // The status shares the artist line rather than adding one. A bar that
    // grew and shrank as the connection came and went would shift everything
    // above it.
    expect(during, settled);
  });

  /// The desktop bar, which is a different widget tree rather than the phone
  /// one stretched. Width decides which is built, so a narrow window on a
  /// desktop gets the phone shape and these are all width tests.
  group('with room for the full transport', () {
    const wide = 1200.0;

    testWidgets('scrubbing is on the bar itself, not only in Now Playing', (
      tester,
    ) async {
      await pumpHeight(tester, aboveNavigationBar: false, width: wide);

      // The whole point of the desktop shape. A pointer makes a thin scrub bar
      // usable, so the track position stops being something you have to open a
      // window to change.
      expect(find.byType(Slider), findsOneWidget);
      // Elapsed and total, the way Spotify reads. Four minutes exactly here.
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('4:00'), findsOneWidget);
    });

    testWidgets('the phone bar has no scrub bar', (tester) async {
      await pumpHeight(tester, aboveNavigationBar: true);

      // Deliberate rather than missing: a 2px-tall target is not something a
      // thumb can hit, and getting it wrong stops playback where it is.
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shuffle and repeat reach the bar', (tester) async {
      await pumpHeight(tester, aboveNavigationBar: false, width: wide);

      // Both were expanded-player-only, which meant turning shuffle on was
      // three interactions from a screen that had the room for one.
      expect(find.byIcon(Icons.shuffle), findsOneWidget);
      expect(find.byIcon(Icons.repeat), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous), findsOneWidget);
      expect(find.byIcon(Icons.skip_next), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('the phone bar keeps its three buttons and no more', (
      tester,
    ) async {
      await pumpHeight(tester, aboveNavigationBar: true);

      expect(find.byIcon(Icons.shuffle), findsNothing);
      expect(find.byIcon(Icons.repeat), findsNothing);
      expect(find.byIcon(Icons.queue_music), findsNothing);
    });

    testWidgets('the queue button opens Now Playing, where the queue is', (
      tester,
    ) async {
      await pumpHeight(tester, aboveNavigationBar: false, width: wide);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MiniPlayer)),
      );
      expect(container.read(nowPlayingExpandedProvider), isFalse);

      await tester.tap(find.byIcon(Icons.queue_music));
      await tester.pump();

      // Up Next has always lived inside the expanded player. This is a way in
      // that says so, rather than a second copy of the list to keep in step.
      expect(container.read(nowPlayingExpandedProvider), isTrue);
    });

    testWidgets('the transport stays centred whatever the title is', (
      tester,
    ) async {
      await pumpHeight(tester, aboveNavigationBar: false, width: wide);

      // Left and right carry equal flex for this reason. Centred against
      // what is left over after the title takes what it wants, the play
      // button would sit visibly off to one side and move on every track
      // change.
      final play = tester.getCenter(find.byIcon(Icons.play_arrow));
      final bar = tester.getRect(find.byType(MiniPlayer));
      expect(play.dx, closeTo(bar.center.dx, 1));
    });

    testWidgets('nothing overflows at the narrowest desktop width', (
      tester,
    ) async {
      // One pixel above the breakpoint, where the three columns have least to
      // work with and the centre one still has to fit five buttons, two
      // timestamps and a slider.
      await pumpHeight(tester, aboveNavigationBar: false, width: 801);
      expect(tester.takeException(), isNull);
    });
  });
}
