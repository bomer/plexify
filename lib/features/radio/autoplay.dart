import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_client.dart';
import '../../core/plex/plex_models.dart';
import '../../core/audio/playback_handler.dart';
import '../../core/providers.dart';
import '../../core/radio/sonic_radio.dart';
import '../../core/settings/app_settings.dart';
import '../player/playback_controller.dart';
import 'radio_action.dart';

/// Starts a station from one track, replacing whatever was playing.
///
/// Null until there is a server to ask. Returns null on success and a
/// [RadioFailure] otherwise, so the caller can say which of the several
/// indistinguishable reasons applied.
typedef StartRadio = Future<RadioFailure?> Function(PlexTrack seed);

final startRadioProvider = Provider<StartRadio?>((ref) {
  final client = ref.watch(plexClientProvider);
  final controller = ref.watch(playbackControllerProvider);
  if (client == null || controller == null) return null;

  return (seed) async {
    final tracks = await const SonicRadio().start(client, seed);
    // One track back means the seed and nothing else, which is not a station.
    // Playing it anyway would look like the button played a single song, which
    // is a different feature the user did not press.
    if (tracks.length < 2) return RadioFailure.noNeighbours;

    await controller.playTracks(tracks);
    return null;
  };
});

/// Keeps a queue that is about to end running, when the setting allows it.
///
/// **Refills before the last track rather than after it**, which is the whole
/// reason this hangs off `onQueueRunningLow` and not `onQueueExhausted`. The
/// engine is given the entire queue up front so it can buffer across a track
/// boundary; music appended once playback has already stopped arrives after a
/// silence and needs an explicit skip to reach it. Arriving three tracks early
/// means the join sounds like any other track change.
///
/// Nothing reads its value — it exists for its side effects, so [AppShell]
/// watches it to keep it alive for the session.
final autoplayProvider = Provider<void>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final client = ref.watch(plexClientProvider);
  final controller = ref.watch(playbackControllerProvider);
  if (client == null || controller == null) return;

  final autoplay = _Autoplay(
    handler: handler,
    client: client,
    controller: controller,
    // Read at the moment a refill is considered rather than watched: this
    // provider must not be torn down and rebuilt because someone toggled a
    // switch, and the answer is only needed at that instant anyway.
    enabled: () => ref.read(settingsProvider).autoplayRadio,
  );

  handler.onQueueRunningLow = autoplay.refill;
  ref.onDispose(() {
    // Only if it is still ours. A replacement provider has already installed
    // its own by the time this runs on a client change, and clearing that
    // would leave autoplay silently dead for the rest of the session.
    if (handler.onQueueRunningLow == autoplay.refill) {
      handler.onQueueRunningLow = null;
    }
  });
});

class _Autoplay {
  _Autoplay({
    required PlexifyAudioHandler handler,
    required PlexClient client,
    required PlaybackController controller,
    required bool Function() enabled,
  }) : _handler = handler,
       _client = client,
       _controller = controller,
       _enabled = enabled;

  final PlexifyAudioHandler _handler;
  final PlexClient _client;
  final PlaybackController _controller;
  final bool Function() _enabled;

  /// One refill at a time.
  ///
  /// The trigger fires on every advance inside the last three tracks, so
  /// without this a slow round trip would be asked the same question three
  /// times and append three batches. Cleared in a `finally` so a failed refill
  /// does not wedge autoplay for the session.
  bool _busy = false;

  late final Future<void> Function() refill = _refill;

  Future<void> _refill() async {
    if (_busy || !_enabled()) return;

    final queue = _handler.queue.value;
    if (queue.isEmpty) return;

    // Seeded from the end of the queue rather than what is playing, so a
    // station drifts with where the queue has reached. Also the only choice
    // that is stable across the three advances this can fire on.
    final seed = queue.last.extras?['ratingKey'] as String?;
    if (seed == null) return;

    _busy = true;
    try {
      final more = await const SonicRadio().extend(
        _client,
        seedRatingKey: seed,
        // The queue is the station's memory. Everything already in it is
        // excluded, which stops a refill replaying the album that has been
        // playing for the last forty minutes.
        exclude: {
          for (final item in queue)
            if (item.extras?['ratingKey'] case final key?) key as String,
        },
      );
      if (more.isEmpty) return;

      // Re-read rather than trusting what was captured before the round trip.
      // A user who started something else while this was in flight must not
      // have twenty tracks stapled onto the end of it.
      if (!identical(_handler.queue.value, queue)) return;

      await _controller.appendTracks(more);
    } on Object {
      // A station that cannot refill simply ends, which is what the queue was
      // going to do anyway. Nothing here is worth interrupting playback for.
    } finally {
      _busy = false;
    }
  }
}
