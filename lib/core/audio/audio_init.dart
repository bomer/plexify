import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'playback_handler.dart';

/// One-time audio setup. Must run before any player is constructed.
///
/// Two platform realities are being reconciled here:
///
/// * **Android** has a native just_audio backend (ExoPlayer), but needs
///   `audio_service` to run playback in a foreground service or the OS kills it
///   the moment the app is backgrounded.
/// * **Windows** has no native just_audio backend at all. `just_audio_media_kit`
///   supplies one via libmpv, and it must be initialised first or constructing
///   an [AudioPlayer] throws.
Future<PlexifyAudioHandler> initAudio() async {
  if (Platform.isWindows || Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized(windows: true, linux: true);

    // libmpv keeps a decoded buffer per player; the default is tuned for video
    // and is wasteful for audio-only playback.
    JustAudioMediaKit.bufferSize = 8 * 1024 * 1024;
    JustAudioMediaKit.title = 'Plexify';
  }

  return AudioService.init(
    builder: PlexifyAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.jamesotoole.plexify.audio',
      androidNotificationChannelName: 'Playback',
      androidNotificationChannelDescription: 'Music playback controls',

      // Both of these were previously true, which is wrong for a music player.
      //
      // androidStopForegroundOnPause: true tears the notification down the
      // instant you pause — so the lock-screen and quick-settings controls
      // vanish at exactly the moment you reach for them to resume. Setting it
      // false keeps the media session visible while paused, which is what every
      // other music app does.
      //
      // androidNotificationOngoing must then be false: audio_service asserts
      // that ongoing requires stopForegroundOnPause, and an ongoing
      // notification that survives pausing would be undismissable.
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );
}
