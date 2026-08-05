import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/core/settings/app_settings.dart';
import 'package:plexify/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings have one failure mode worth guarding, and it is not visual: a
/// preference that changes the UI but never reaches disk works perfectly until
/// the next launch, and then looks like the app forgot. Most of what follows is
/// about that round trip rather than about the screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(SettingsStore, SharedPreferences)> freshStore([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    return (SettingsStore(prefs), prefs);
  }

  const server = PlexServer(
    name: 'Basement',
    baseUrl: 'https://10-0-0-4.abc.plex.direct:32400',
    token: 't',
    isLocal: true,
    isRelay: false,
  );

  Future<ProviderContainer> container(SettingsStore store) async {
    final c = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        plexServerProvider.overrideWith((ref) => server),
        plexIdentityProvider.overrideWithValue(PlexIdentity.forTesting()),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('storage', () {
    test('defaults to dark when nothing has been stored', () async {
      final (store, _) = await freshStore();

      // The app is designed dark-first; following the system would put a new
      // install into a theme that was never the intent.
      expect(store.read().themeMode, ThemeMode.dark);
    });

    test('a stored preference is read back', () async {
      final (store, prefs) = await freshStore();

      await store.write(const AppSettings(themeMode: ThemeMode.light));

      expect(store.read().themeMode, ThemeMode.light);
      // Stored by name, not by index. An index would silently change everyone's
      // theme if ThemeMode ever gained a value or reordered.
      expect(prefs.getString('settings_theme_mode'), 'light');
    });

    test('a value it does not recognise falls back to the default', () async {
      final (store, _) = await freshStore({'settings_theme_mode': 'sepia'});

      // Written by a newer build, or corrupted. Either way the app has to
      // start.
      expect(store.read().themeMode, ThemeMode.dark);
    });
  });

  group('controller', () {
    test('changing a setting persists it', () async {
      final (store, prefs) = await freshStore();
      final c = await container(store);

      c.read(settingsProvider.notifier).setThemeMode(ThemeMode.light);

      // The state changes immediately; the write is not awaited by the caller.
      expect(c.read(settingsProvider).themeMode, ThemeMode.light);
      await pumpEventQueue();
      expect(prefs.getString('settings_theme_mode'), 'light');
    });

    test('the opening state comes from storage, not the default', () async {
      final (store, _) = await freshStore({'settings_theme_mode': 'system'});
      final c = await container(store);

      expect(c.read(settingsProvider).themeMode, ThemeMode.system);
    });
  });

  group('screen', () {
    Future<void> pump(WidgetTester tester, ProviderContainer c) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows which server is connected and how', (tester) async {
      final (store, _) = await freshStore();
      await pump(tester, await container(store));

      expect(find.text('Basement'), findsOneWidget);
      // Which of the three routes is in use explains most of what anyone
      // notices about speed, so it is the fact worth showing.
      expect(find.text('Local network'), findsOneWidget);
    });

    testWidgets('is the way to reach sync status', (tester) async {
      final (store, _) = await freshStore();
      await pump(tester, await container(store));

      // It used to be an app-bar icon on Home. This screen is now the only
      // route to it, so losing the tile would strand it entirely.
      expect(find.text('Sync status'), findsOneWidget);
    });

    testWidgets('choosing a theme persists it', (tester) async {
      final (store, prefs) = await freshStore();
      final c = await container(store);
      await pump(tester, c);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(c.read(settingsProvider).themeMode, ThemeMode.light);
      expect(prefs.getString('settings_theme_mode'), 'light');
    });
  });
}
