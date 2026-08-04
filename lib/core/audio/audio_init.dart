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
      // Keep the notification up while playing so Android treats us as a
      // foreground service and doesn't reclaim us mid-track.
      androidNotificationOngoing: true,
      // ...but drop out of the foreground on pause, otherwise the notification
      // becomes undismissable and users rightly find that obnoxious.
      androidStopForegroundOnPause: true,
    ),
  );
}
