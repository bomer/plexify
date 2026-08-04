import 'dart:io';

import 'package:flutter/services.dart';

/// Host-window operations that Flutter does not expose directly.
class AppWindow {
  const AppWindow._();

  static const _channel = MethodChannel('plexify/app');

  /// Sends the app to the background without destroying it.
  ///
  /// Android's default back behaviour at the root route *finishes* the
  /// activity, which tears down the Flutter engine and stops playback. For a
  /// music player that is the wrong outcome — pressing back should minimise,
  /// exactly as it does in every other music app, leaving audio running under
  /// the foreground service.
  ///
  /// No-op on platforms where it does not apply.
  static Future<void> moveToBackground() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('moveToBackground');
    } on PlatformException {
      // If the channel is unavailable, do nothing rather than crash — the
      // worst case is the old behaviour.
    }
  }
}
