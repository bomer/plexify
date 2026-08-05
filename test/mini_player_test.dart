import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/audio/playback_handler.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/features/player/mini_player.dart';

import 'support/fake_just_audio.dart';

/// The mini player is the one widget on screen at all times, so anything
/// wasteful about it is wasteful everywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(FakeJustAudio.install);

  /// A phone-shaped viewport with a gesture-bar inset, which is the condition
  /// the height bug needed — on a device with no inset it looked fine.
  Future<double> pumpHeight(
    WidgetTester tester, {
    required bool aboveNavigationBar,
    double bottomInset = 34,
    Stream<bool>? reconnecting,
  }) async {
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
            size: const Size(400, 900),
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
}
