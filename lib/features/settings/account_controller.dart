import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../player/playback_controller.dart';
import '../../core/settings/app_settings.dart';

/// Leaving a server — either for the login screen, or for a different one.
///
/// Both are the same operation with a different last step, so they share one
/// teardown rather than having one each. The teardown is the part with an
/// order that matters; the last step is a single line.
///
/// **Why the cache is wiped here rather than left to the next sync.**
/// `LibrarySync` already resets when it notices the server changed, but it only
/// notices *during* a sync. Between switching and that sync finishing, the album
/// grid streams the previous server's rows — and because the cache is non-empty
/// it does not fall through to a live read, so you browse a library that is not
/// there and every tap 404s. Wiping eagerly is what closes that window.
class AccountController {
  AccountController(this._ref);

  final Ref _ref;

  /// How long the goodbye to Plex may take before we stop waiting for it.
  ///
  /// The server that has stopped answering is exactly the one you sign out of,
  /// and that is the case where this request is slowest.
  static const _goodbyeTimeout = Duration(seconds: 2);

  /// Forgets the token and returns to the login screen.
  Future<void> signOut() async {
    await _leave();
    await _ref.read(plexAuthProvider).signOut();
    // Nulling the token collapses the whole graph — client, socket, scheduler
    // and reporter all hang off it — so nothing else needs tearing down by
    // hand.
    _ref.read(authTokenProvider.notifier).state = null;
  }

  /// Binds the app to a different server on the same account, or with null
  /// releases it to take whichever answers first.
  ///
  /// The token is untouched: this is one account with more than one server, not
  /// a different login.
  Future<void> switchTo(String? clientIdentifier) async {
    await _leave();
    // `connectServerProvider` watches this, so the reconnect happens on its
    // own. Invalidating as well would race the two against each other.
    _ref.read(settingsProvider.notifier).setPreferredServer(clientIdentifier);
  }

  /// Everything both paths do, in the order they have to do it.
  Future<void> _leave() async {
    // 1. Say goodbye while the client still works. After this the server keeps
    //    showing Plexify as playing until it times the session out.
    try {
      await _ref
          .read(timelineReporterProvider)
          ?.reportStopped()
          .timeout(_goodbyeTimeout);
    } on Object {
      // Nothing useful to do on the way out.
    }

    // 2. Stop playback and forget the queue. Nothing in the provider graph does
    //    this: the audio handler is a root object that outlives every
    //    connection, so a plain sign-out would leave the last track on screen
    //    in the mini player, pointing at a URL that no longer resolves.
    await _ref.read(audioHandlerProvider).clearQueue();

    // 3. Silence both writers before wiping, not for tidiness — either one can
    //    write a row *after* the wipe. The scheduler may be mid-pass, and the
    //    socket can deliver a change at any moment. Left running, they would
    //    put the old server's rows straight back into a cache that is supposed
    //    to be empty.
    await _ref.read(syncSchedulerProvider)?.stop();
    _ref.read(plexNotificationSocketProvider)?.stop();

    // 4. Now the caches can go. Artwork too: thumb paths are server-scoped, so
    //    the same path on another server is different art entirely.
    await _ref.read(databaseProvider).clearLibrary();
    await _ref.read(artworkCacheProvider).clear();
    // The saved session belongs to the server being left. Restored against
    // the next one it would be ratingKeys from one library used against
    // another — the same collision `clearLibrary` exists to prevent.
    await _ref.read(playbackStateStoreProvider).clear();
  }
}

final accountControllerProvider = Provider<AccountController>(
  AccountController.new,
);
