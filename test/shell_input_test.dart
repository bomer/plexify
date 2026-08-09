import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/audio/playback_handler.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/core/settings/app_settings.dart';
import 'package:plexify/features/library/album_detail_screen.dart';
import 'package:plexify/features/player/player_providers.dart';
import 'package:plexify/shell/app_shell.dart';
import 'package:plexify/shell/shell_destination.dart';
import 'package:plexify/shell/typing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_just_audio.dart';

/// Keyboard and mouse, at the shell.
///
/// The space shortcut is the interesting one, because the first version of it
/// broke typing and the guard that was supposed to prevent that could never
/// have run. `CallbackShortcuts` consumes a key the moment it matches a
/// binding, before the callback decides anything — and a key the framework has
/// marked handled is never forwarded to the text input system. So no amount of
/// checking inside the callback could have let a space reach a search box.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeJustAudio audio;

  /// Null in the tests that never build a shell — the `isTypingSomewhere`
  /// group needs neither an audio engine nor a provider graph.
  PlexifyAudioHandler? handler;

  const album = PlexAlbum(
    ratingKey: 'al1',
    title: 'Kid A',
    artist: 'Radiohead',
    artistRatingKey: 'ar1',
  );

  setUp(() {
    audio = FakeJustAudio.install();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await handler?.dispose();
    handler = null;
    await db.close();
  });

  Future<ProviderContainer> pumpShell(WidgetTester tester) async {
    // `AudioPlayer` waits on locks that never resolve inside the fake-async
    // zone, so it has to be built — and loaded — in real async.
    //
    // A real queue rather than a bare `mediaItem`, because the fake engine only
    // creates a player when one is loaded, and "did the space reach the engine"
    // is the question these tests ask.
    //
    // Paused afterwards, which is also the state a launch restores into and so
    // the one you are most likely to press space in. The delay is not padding:
    // `playbackState` is fed from the player through `pipe`, and the shortcut
    // reads it to decide which way to toggle — without letting that arrive, the
    // key would read a stale "playing" and pause an already-paused player.
    await tester.runAsync(() async {
      final built = PlexifyAudioHandler();
      handler = built;
      await built.setQueueAndPlay([
        const MediaItem(id: 'https://tower/1', title: 'Idioteque'),
      ]);
      await built.pause();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioHandlerProvider.overrideWithValue(handler!),
        plexIdentityProvider.overrideWithValue(PlexIdentity.forTesting()),
        settingsStoreProvider.overrideWithValue(
          SettingsStore(await SharedPreferences.getInstance()),
        ),
        networkChangesProvider.overrideWithValue(const Stream<void>.empty()),
        albumsProvider.overrideWith((ref) => Stream.value([album])),
        tracksProvider.overrideWith(
          (ref, key) => Stream.value(const <PlexTrack>[]),
        ),
      ],
    );
    addTearDown(container.dispose);

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

  /// Presses space and reports whether the framework claimed it.
  ///
  /// Run in real async because `just_audio`'s own `play()` waits on futures
  /// that never resolve inside `testWidgets`' fake-async zone — the same reason
  /// the handler itself has to be built there.
  Future<bool> pressSpace(WidgetTester tester) async {
    var handled = false;
    await tester.runAsync(() async {
      handled = await simulateKeyDownEvent(LogicalKeyboardKey.space);
      await simulateKeyUpEvent(LogicalKeyboardKey.space);
    });
    await tester.pump();
    return handled;
  }

  group('space', () {
    testWidgets('toggles playback when nothing is being typed into', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(audio.player.playing, isFalse, reason: 'precondition');

      final handled = await pressSpace(tester);

      // Claimed, which is what stops the space also scrolling a list.
      expect(handled, isTrue);
      // Asserted against the engine rather than `playbackState`, which is fed
      // from the player through `pipe` and has not caught up within a frame.
      expect(audio.player.playing, isTrue);

      // Stopped again before the test ends. `just_audio` runs a periodic
      // position timer while playing, and `testWidgets` fails a test that
      // leaves one pending — which reads as a hang rather than as tidying up
      // left undone.
      await tester.runAsync(() async => handler!.pause());
      await tester.pump();
    });

    // Guards the *outcome* rather than the guard. In this environment the
    // framework already stops a plain key below the shell, so removing
    // `isTypingSomewhere` does not fail this — see `isTypingSomewhere` in
    // shell/typing.dart for the case that only exists with a live text input
    // connection, and the test below it that does discriminate.
    testWidgets('typing a space in search neither pauses nor is swallowed', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(shellDestinationProvider.notifier).state =
          ShellDestination.search;
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      final handled = await pressSpace(tester);

      // Reporting it unhandled is the entire mechanism: the engine only turns a
      // key into a character once the framework says nobody wanted it. Asserted
      // directly rather than by checking the field's contents, because text
      // arrives over the input channel and not through this path at all.
      //
      // The old `CallbackShortcuts` would have claimed it here, because that
      // widget consumes a key the moment it matches a binding.
      expect(handled, isFalse);
      // Untouched. Typing a space in a search box must neither be swallowed nor
      // reach the player, which is the complaint that started this.
      expect(audio.player.playing, isFalse);
    });

    testWidgets('is left alone with no track loaded', (tester) async {
      await pumpShell(tester);
      handler!.mediaItem.add(null);
      await tester.pump();

      final handled = await pressSpace(tester);

      // Claiming a key in order to do nothing with it is worse than not
      // claiming it — whatever else wanted the space never gets a turn.
      expect(handled, isFalse);
    });
  });

  group('isTypingSomewhere', () {
    testWidgets('sees a focused text field', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextField(focusNode: node)),
        ),
      );
      expect(isTypingSomewhere(), isFalse, reason: 'nothing focused yet');

      node.requestFocus();
      await tester.pump();

      // The check this replaced asked whether the focused *widget* was an
      // EditableText, which can never be true: EditableText builds a Focus
      // internally and hands it the field's node, so the node's context belongs
      // to that Focus. It read as a careful guard and did nothing.
      expect(isTypingSomewhere(), isTrue);
    });

    testWidgets('does not see an ordinary focused button', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              focusNode: node,
              onPressed: () {},
              child: const Text('Play'),
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();

      // Space has to keep working from a focused button, which is where it will
      // be most of the time on a desktop.
      expect(isTypingSomewhere(), isFalse);
    });
  });

  group('the mouse back button', () {
    /// Presses button four, the one every browser binds to Back.
    Future<void> pressBack(WidgetTester tester) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.down(const Offset(600, 400), buttons: kBackMouseButton),
      );
      await tester.sendEventToBinding(pointer.up());
      await tester.pumpAndSettle();
    }

    testWidgets('pops the page you are on', (tester) async {
      final container = await pumpShell(tester);
      container.read(shellDestinationProvider.notifier).state =
          ShellDestination.library;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kid A').first);
      await tester.pumpAndSettle();
      expect(find.byType(AlbumDetailScreen), findsOneWidget);

      await pressBack(tester);

      expect(find.byType(AlbumDetailScreen), findsNothing);
    });

    testWidgets('collapses Now Playing before popping anything', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(shellDestinationProvider.notifier).state =
          ShellDestination.library;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kid A').first);
      await tester.pumpAndSettle();

      container.read(nowPlayingExpandedProvider.notifier).state = true;
      await tester.pumpAndSettle();

      await pressBack(tester);

      // One definition of "back", shared with the Android gesture and the app
      // bar arrow: the topmost thing on screen goes first. Popping the album
      // out from under an overlay that is still up would leave you looking at
      // the player with a different page behind it.
      expect(container.read(nowPlayingExpandedProvider), isFalse);
      expect(find.byType(AlbumDetailScreen), findsOneWidget);
    });

    testWidgets('an ordinary click is not a back press', (tester) async {
      final container = await pumpShell(tester);
      container.read(shellDestinationProvider.notifier).state =
          ShellDestination.library;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kid A').first);
      await tester.pumpAndSettle();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.down(const Offset(600, 400), buttons: kPrimaryMouseButton),
      );
      await tester.sendEventToBinding(pointer.up());
      await tester.pumpAndSettle();

      // The listener sees every pointer down, so the button test is the only
      // thing standing between this and every left click navigating away.
      expect(find.byType(AlbumDetailScreen), findsOneWidget);
    });
  });
}
