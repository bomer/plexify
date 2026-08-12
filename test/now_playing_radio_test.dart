import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/audio/playback_handler.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/core/settings/app_settings.dart';
import 'package:plexify/features/player/now_playing_screen.dart';
import 'package:plexify/features/radio/radio_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_just_audio.dart';

/// The radio button in the Now Playing header.
///
/// Worth pinning because it lives where a spacer used to, and a spacer is
/// exactly the kind of thing a later layout change reinstates without anyone
/// noticing the button went with it. Now Playing is also the only screen that
/// always knows which song is meant, which makes it the entry point that has to
/// survive: the artist page needs navigating to, the track sheet is phone-only,
/// and this one is neither.
///
/// Seeded through the *album* key rather than the track's own, because
/// similarity on this server relates artists to artists and an album is how a
/// MediaItem names who made it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late PlexifyAudioHandler handler;

  setUp(() async {
    FakeJustAudio.install();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await handler.dispose();
    await db.close();
  });

  Future<void> pumpNowPlaying(WidgetTester tester, MediaItem item) async {
    // `AudioPlayer` initialisation waits on locks that never resolve inside
    // `testWidgets`' fake-async zone, so it has to be built in real async.
    await tester.runAsync(() async => handler = PlexifyAudioHandler());
    handler.mediaItem.add(item);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioHandlerProvider.overrideWithValue(handler),
        plexIdentityProvider.overrideWithValue(PlexIdentity.forTesting()),
        settingsStoreProvider.overrideWithValue(
          SettingsStore(await SharedPreferences.getInstance()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: NowPlayingScreen(openPage: (_) {})),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers a station from whatever is playing', (tester) async {
    await pumpNowPlaying(
      tester,
      const MediaItem(
        id: 'https://tower/1',
        title: 'Idioteque',
        extras: {'albumRatingKey': 'b1'},
      ),
    );

    expect(find.byIcon(Icons.radio), findsOneWidget);
  });

  testWidgets('can show a message over itself, not under the shell', (
    tester,
  ) async {
    // The bug this exists for. Now Playing is a sibling layer in the shell's
    // Stack and is painted *above* the Scaffold, so a snackbar from the
    // app-level messenger renders underneath it and is never seen. Every way
    // radio could fail then looked exactly like a button that did nothing,
    // which is how it was reported.
    //
    // Asserting on the messenger rather than on pixels: what went wrong was
    // which messenger owned the message, and that is the thing to pin.
    await pumpNowPlaying(
      tester,
      const MediaItem(
        id: 'https://tower/1',
        title: 'Idioteque',
        extras: {'albumRatingKey': 'b1'},
      ),
    );

    // No Plex connection in this container, so pressing it fails at the first
    // step and has something to say.
    await tester.tap(find.byIcon(Icons.radio));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(NowPlayingScreen),
        matching: find.text(RadioFailure.noServer.message),
      ),
      findsOneWidget,
      reason:
          'the message has to render inside Now Playing, because the '
          'shell Scaffold that would otherwise own it is painted underneath',
    );
  });

  testWidgets('keeps the grab handle centred when there is no key', (
    tester,
  ) async {
    // A restored session can publish an item the queue built before extras
    // were carried. Radio needs the album to find the artist behind it, so with
    // no album key there is nothing to seed from, and the header still has to
    // balance rather than shifting the handle off centre.
    await pumpNowPlaying(
      tester,
      const MediaItem(id: 'https://tower/1', title: 'Idioteque'),
    );

    expect(find.byIcon(Icons.radio), findsNothing);

    final handle = tester.getCenter(
      find.byWidgetPredicate(
        (widget) => widget is Container && widget.constraints?.maxWidth == 36,
      ),
    );
    expect(handle.dx, closeTo(tester.getCenter(find.byType(Row).first).dx, 1));
  });
}
