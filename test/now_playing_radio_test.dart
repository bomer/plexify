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
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_just_audio.dart';

/// The radio button in the Now Playing header.
///
/// Worth pinning because it lives where a spacer used to, and a spacer is
/// exactly the kind of thing a later layout change reinstates without anyone
/// noticing the button went with it. Now Playing is also the only screen that
/// always knows which song is meant, which makes it the entry point that has to
/// survive: the album button covers a record, the track sheet is phone-only,
/// and this one is neither.
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
        child: const MaterialApp(home: NowPlayingScreen()),
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
        extras: {'ratingKey': 't1'},
      ),
    );

    expect(find.byIcon(Icons.radio), findsOneWidget);
  });

  testWidgets('keeps the grab handle centred when there is no key', (
    tester,
  ) async {
    // A restored session can publish an item the queue built before extras
    // were carried. The button has nothing to seed from, and the header still
    // has to balance rather than shifting the handle off centre.
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
