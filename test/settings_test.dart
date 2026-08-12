import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/acquire/download_source.dart';
import 'package:plexify/core/audio/quality_policy.dart';
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

  group('catalog and downloads', () {
    test('looking up albums you do not own is off until asked for', () async {
      final (store, _) = await freshStore();

      // Off is a real default rather than a soft launch. It turns on a
      // third-party lookup on the search path and a section on every artist
      // page, which on a phone is noise.
      expect(store.read().catalogEnabled, isFalse);
    });

    test('the catalog switch round-trips', () async {
      final (store, prefs) = await freshStore();
      final c = await container(store);

      c.read(settingsProvider.notifier).setCatalogEnabled(true);
      await pumpEventQueue();

      expect(prefs.getBool('settings_catalog_enabled'), isTrue);
      expect(store.read().catalogEnabled, isTrue);
    });

    test('a trailing slash is stripped from the qBittorrent address', () async {
      final (store, _) = await freshStore();
      final c = await container(store);

      c.read(settingsProvider.notifier).setQbitUrl('https://box.local:8080/');

      // Left on, every request path becomes double-slashed and the Referer
      // stops matching Host — which qBittorrent answers with a 403 that reads
      // as a wrong password rather than as a typo.
      expect(c.read(settingsProvider).qbitUrl, 'https://box.local:8080');
    });

    test('clearing the address removes the key rather than storing ""', () async {
      final (store, prefs) = await freshStore();
      final c = await container(store);

      c.read(settingsProvider.notifier).setQbitUrl('https://box.local:8080');
      await pumpEventQueue();
      c.read(settingsProvider.notifier).setQbitUrl('   ');
      await pumpEventQueue();

      // An empty string would read back as a configured server whose address is
      // nothing, and every request against it would fail for an unguessable
      // reason.
      expect(prefs.getString('settings_qbit_url'), isNull);
      expect(store.read().qbitUrl, isNull);
    });
  });

  group('choosing a download source', () {
    test('an existing install keeps downloading from qBittorrent', () async {
      // The upgrade path, and the reason the default is not "whichever is
      // configured". Someone who has only ever used torrents must not find
      // their next download coming from somewhere else because a new option
      // appeared.
      final (store, _) = await freshStore();
      expect(store.read().downloadSource, DownloadSourceKind.qbittorrent);
    });

    test('the choice round-trips', () async {
      final (store, prefs) = await freshStore();
      final c = await container(store);

      c.read(settingsProvider.notifier).setDownloadSource(
        DownloadSourceKind.soulseek,
      );
      await pumpEventQueue();

      // Stored by name, not by index.
      expect(prefs.getString('settings_download_source'), 'soulseek');
      expect(store.read().downloadSource, DownloadSourceKind.soulseek);
    });

    test('an unrecognised stored value falls back rather than throwing', () async {
      // A value written by a future version, or a corrupted preferences file.
      // Refusing to start over one string would be a poor trade.
      final (store, _) = await freshStore({
        'settings_download_source': 'gnutella',
      });
      expect(store.read().downloadSource, DownloadSourceKind.qbittorrent);
    });

    test('the slskd address round-trips and loses its trailing slash', () async {
      final (store, prefs) = await freshStore();
      final c = await container(store);

      c.read(settingsProvider.notifier).setSlskdUrl('https://nas.local:5031/');
      await pumpEventQueue();

      // slskd tolerates a doubled slash; a reverse proxy in front of it very
      // often does not, and the resulting 404 names nothing useful.
      expect(prefs.getString('settings_slskd_url'), 'https://nas.local:5031');
      expect(store.read().slskdUrl, 'https://nas.local:5031');
    });

    test('clearing the slskd address removes the key', () async {
      final (store, prefs) = await freshStore();
      final c = await container(store);

      c.read(settingsProvider.notifier).setSlskdUrl('https://nas.local:5031');
      await pumpEventQueue();
      c.read(settingsProvider.notifier).setSlskdUrl('  ');
      await pumpEventQueue();

      expect(prefs.getString('settings_slskd_url'), isNull);
      expect(store.read().slskdUrl, isNull);
    });
  });

  group('playback and storage settings', () {
    test(
      'quality overrides round-trip, and clearing removes the key',
      () async {
        final (store, prefs) = await freshStore();

        await store.write(
          const AppSettings(
            qualityUnmetered: QualityDecision.directPlay,
            qualityMetered: QualityDecision.transcode,
          ),
        );

        expect(store.read().qualityUnmetered, QualityDecision.directPlay);
        expect(store.read().qualityMetered, QualityDecision.transcode);

        await store.write(const AppSettings());

        // Removed, not written empty. Null here means "decide automatically",
        // and a stored '' would read back as a decision nobody chose, so the
        // automatic path would become unreachable once either had been set.
        expect(prefs.containsKey('settings_quality_unmetered'), isFalse);
        expect(store.read().qualityUnmetered, isNull);
        expect(store.read().qualityMetered, isNull);
      },
    );

    test('the override applies to the connection it was chosen for', () {
      const settings = AppSettings(
        qualityUnmetered: QualityDecision.directPlay,
        qualityMetered: QualityDecision.transcode,
      );

      // Reads as trivial, and is the exact thing a swap makes invisible:
      // both fields hold a valid decision either way round, so nothing else
      // in the app would complain.
      expect(
        settings.qualityOverrideFor(unmetered: true),
        QualityDecision.directPlay,
      );
      expect(
        settings.qualityOverrideFor(unmetered: false),
        QualityDecision.transcode,
      );
    });

    test(
      'cache budgets round-trip, and null means the platform default',
      () async {
        final (store, prefs) = await freshStore();

        await store.write(
          const AppSettings(
            audioCacheMaxBytes: 512 * 1024 * 1024,
            artworkCacheMaxBytes: 128 * 1024 * 1024,
          ),
        );
        expect(store.read().audioCacheMaxBytes, 512 * 1024 * 1024);
        expect(store.read().artworkCacheMaxBytes, 128 * 1024 * 1024);

        await store.write(const AppSettings());
        // Not zero. A budget of zero would be a real, valid, and catastrophic
        // setting: everything evicted the moment it was written.
        expect(prefs.containsKey('settings_audio_cache_max_bytes'), isFalse);
        expect(store.read().audioCacheMaxBytes, isNull);
      },
    );

    test(
      'a budget change reaches the live cache without replacing it',
      () async {
        final (store, _) = await freshStore();
        final c = await container(store);

        final cache = c.read(audioCacheProvider);
        c
            .read(settingsProvider.notifier)
            .setAudioCacheMaxBytes(512 * 1024 * 1024);
        await pumpEventQueue();

        // Both halves matter. The budget has to arrive, or the setting is
        // decorative until the next launch. And it has to arrive *on the same
        // instance*: a rebuilt cache starts with an empty in-use set, so its
        // first eviction pass could delete the file the engine is streaming
        // from and stop the track mid-play.
        expect(cache.maxBytes, 512 * 1024 * 1024);
        expect(identical(c.read(audioCacheProvider), cache), isTrue);
      },
    );
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

    /// The screen is now taller than the test viewport, and the `ListView`
    /// builds lazily, so anything below Storage genuinely does not exist until
    /// it is scrolled to. A finder that fails for that reason looks exactly
    /// like a section that was deleted.
    Future<void> scrollTo(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
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
      await scrollTo(tester, find.text('Sync status'));
      expect(find.text('Sync status'), findsOneWidget);
    });

    testWidgets('choosing a theme persists it', (tester) async {
      final (store, prefs) = await freshStore();
      final c = await container(store);
      await pump(tester, c);

      await scrollTo(tester, find.text('Light'));
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(c.read(settingsProvider).themeMode, ThemeMode.light);
      expect(prefs.getString('settings_theme_mode'), 'light');
    });

    testWidgets('each quality dropdown shows its own setting', (tester) async {
      final (store, _) = await freshStore({
        'settings_quality_unmetered': 'directPlay',
        'settings_quality_metered': 'transcode',
      });
      await pump(tester, await container(store));
      await scrollTo(tester, find.text('On mobile data'));

      // Both dropdowns wired to one field is a plausible copy-paste result,
      // and it reads as the wifi setting refusing to change. Rendering catches
      // it: one label would appear twice and the other not at all.
      //
      // Deliberately asserts what is *drawn* rather than driving the dropdown.
      // Opening a DropdownButton's menu in this tree never reaches a quiescent
      // frame, so `pumpAndSettle` sits there for its full ten-minute timeout.
      // What tapping would have added over this is covered without a widget at
      // all, by `qualityOverrideFor` above and by the playback controller's own
      // override tests.
      expect(find.text('Original file'), findsOneWidget);
      expect(find.text('Transcoded'), findsOneWidget);
    });
  });

  group('sidebar playlist count', () {
    test('defaults to twelve and survives a round trip', () async {
      final (store, _) = await freshStore();
      expect(store.read().sidebarPlaylists, 12);

      await store.write(const AppSettings(sidebarPlaylists: 4));
      expect(store.read().sidebarPlaylists, 4);
    });

    test('zero is a real choice, not a missing value', () async {
      // It hides the section, which is a reasonable thing to want. Falling back
      // to the default here would make the setting impossible to turn off.
      final (store, _) = await freshStore();
      await store.write(const AppSettings(sidebarPlaylists: 0));
      expect(store.read().sidebarPlaylists, 0);
    });
  });
}
