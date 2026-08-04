import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Requests the Android notification permission needed for playback controls.
///
/// From Android 13 (API 33), `POST_NOTIFICATIONS` is a runtime permission and
/// `audio_service` does **not** request it — it declares the permission in its
/// manifest but never prompts. Verified on a real device: the app ran fine with
/// `POST_NOTIFICATIONS: granted=false`, which means audio plays but the media
/// notification and lock-screen transport controls never appear.
///
/// Deliberately **not** gating: if the user declines, playback still works, they
/// just lose the notification controls. Refusing to play music because someone
/// said no to notifications would be absurd.
class NotificationPermission {
  const NotificationPermission._();

  static bool _asked = false;

  /// Asks once per process, the first time playback starts.
  ///
  /// Requesting at that moment rather than on cold start means the prompt
  /// arrives when its purpose is obvious — the user just pressed play — which
  /// materially improves the odds of it being granted.
  static Future<void> ensure() async {
    if (!Platform.isAndroid) return;
    if (_asked) return;
    _asked = true;

    try {
      final status = await Permission.notification.status;
      // isPermanentlyDenied means the OS will no longer show a prompt; asking
      // again is a silent no-op, so don't bother.
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } on Object {
      // A permission failure must never prevent playback.
    }
  }
}
