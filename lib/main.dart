import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/audio/audio_init.dart';
import 'core/plex/plex_auth.dart';
import 'core/plex/plex_identity.dart';
import 'core/audio/playback_state_store.dart';
import 'core/providers.dart';
import 'features/player/playback_controller.dart';
import 'core/settings/app_settings.dart';
import 'shell/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Identity must load before anything talks to Plex — the client identifier is
  // part of every request, and the auth token is bound to it.
  final identity = await PlexIdentity.load();

  // Audio must be initialised before any player is constructed. On Windows this
  // loads libmpv; on Android it starts the media session.
  final audioHandler = await initAudio();

  // Seed the token from secure storage so a returning user skips the link flow.
  final storedToken = await PlexAuth(identity: identity).readToken();

  // Loaded before the first frame so the app never paints the default theme and
  // then corrects itself.
  final settings = await SettingsStore.load();
  final playbackState = await PlaybackStateStore.load();

  runApp(
    ProviderScope(
      overrides: [
        plexIdentityProvider.overrideWithValue(identity),
        audioHandlerProvider.overrideWithValue(audioHandler),
        settingsStoreProvider.overrideWithValue(settings),
        playbackStateStoreProvider.overrideWithValue(playbackState),
        authTokenProvider.overrideWith((ref) => storedToken),
      ],
      child: const PlexifyApp(),
    ),
  );
}
