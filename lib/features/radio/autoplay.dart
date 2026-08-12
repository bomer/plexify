import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/playback_handler.dart';
import '../../core/db/app_database.dart';
import '../../core/db/mappers.dart';
import '../../core/plex/plex_client.dart';
import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../../core/radio/sonic_radio.dart';
import '../../core/settings/app_settings.dart';
import '../player/playback_controller.dart';
import 'radio_action.dart';

/// Assembles a station: similar artists from Plex, their tracks from the cache.
class RadioBuilder {
  const RadioBuilder({
    required PlexClient client,
    required AppDatabase db,
    SonicRadio radio = const SonicRadio(),
  }) : _client = client,
       _db = db,
       _radio = radio;

  final PlexClient _client;
  final AppDatabase _db;
  final SonicRadio _radio;

  /// Tracks for a station seeded on [artistRatingKey].
  ///
  /// The seed artist leads and whoever Plex named follows. Empty means no
  /// station could be built, which has two causes: the server named nobody, or
  /// it named artists this library does not hold.
  Future<List<PlexTrack>> tracksFor(
    String artistRatingKey, {
    Set<String> exclude = const {},
  }) async {
    final similar = await _client.similarArtists(artistRatingKey);

    final byArtist = <List<PlexTrack>>[];
    for (final key in [artistRatingKey, ...similar.map((a) => a.ratingKey)]) {
      final rows = await _db.tracksForArtist(key);
      // An artist Plex named but this library does not hold contributes
      // nothing, rather than an empty slot the round-robin steps over on every
      // pass.
      if (rows.isNotEmpty) byArtist.add([for (final r in rows) r.toDomain()]);
    }
    if (byArtist.isEmpty) return const [];

    return _radio.build(byArtist: byArtist, exclude: exclude);
  }
}

final radioBuilderProvider = Provider<RadioBuilder?>((ref) {
  final client = ref.watch(plexClientProvider);
  if (client == null) return null;
  return RadioBuilder(client: client, db: ref.watch(databaseProvider));
});

/// Starts a station from an artist, replacing whatever was playing.
///
/// Null until there is a server to ask. Returns null on success and a
/// [RadioFailure] otherwise, so the caller can say which of the several
/// indistinguishable reasons applied.
typedef StartRadio = Future<RadioFailure?> Function(String artistRatingKey);

final startRadioProvider = Provider<StartRadio?>((ref) {
  final builder = ref.watch(radioBuilderProvider);
  final controller = ref.watch(playbackControllerProvider);
  if (builder == null || controller == null) return null;

  return (artistRatingKey) async {
    final tracks = await builder.tracksFor(artistRatingKey);
    // One track is not a station. Playing it anyway would look like the button
    // played a single song, which is a different feature nobody pressed.
    if (tracks.length < 2) return RadioFailure.noNeighbours;

    await controller.playTracks(tracks);
    return null;
  };
});

/// Keeps a queue that is about to end running, when the setting allows it.
///
/// **Refills before the last track rather than after it**, which is why this
/// hangs off `onQueueRunningLow` and not `onQueueExhausted`. The engine is given
/// the whole queue up front so it can buffer across a track boundary; music
/// appended once playback has stopped arrives after a silence and needs an
/// explicit skip to reach. Arriving three tracks early makes the join sound
/// like any other track change.
///
/// Nothing reads its value — it exists for its side effects, so [AppShell]
/// watches it to keep it alive for the session.
final autoplayProvider = Provider<void>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final builder = ref.watch(radioBuilderProvider);
  final controller = ref.watch(playbackControllerProvider);
  if (builder == null || controller == null) return;

  final autoplay = _Autoplay(
    handler: handler,
    builder: builder,
    controller: controller,
    db: ref.watch(databaseProvider),
    // Read when a refill is considered rather than watched: this provider must
    // not be torn down because someone toggled a switch, and the answer is only
    // needed at that instant.
    enabled: () => ref.read(settingsProvider).autoplayRadio,
  );

  handler.onQueueRunningLow = autoplay.refill;
  ref.onDispose(() {
    // Only if it is still ours. A replacement has already installed its own by
    // the time this runs on a client change, and clearing that would leave
    // autoplay silently dead for the rest of the session.
    if (handler.onQueueRunningLow == autoplay.refill) {
      handler.onQueueRunningLow = null;
    }
  });
});

class _Autoplay {
  _Autoplay({
    required PlexifyAudioHandler handler,
    required RadioBuilder builder,
    required PlaybackController controller,
    required AppDatabase db,
    required bool Function() enabled,
  }) : _handler = handler,
       _builder = builder,
       _controller = controller,
       _db = db,
       _enabled = enabled;

  final PlexifyAudioHandler _handler;
  final RadioBuilder _builder;
  final PlaybackController _controller;
  final AppDatabase _db;
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
    final album = queue.last.extras?['albumRatingKey'] as String?;
    if (album == null) return;

    _busy = true;
    try {
      final artist = await _artistOf(album);
      if (artist == null) return;

      final more = await _builder.tracksFor(
        artist,
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
      // Someone who started something else while this was in flight must not
      // have two dozen tracks stapled onto the end of it.
      if (!identical(_handler.queue.value, queue)) return;

      await _controller.appendTracks(more);
    } on Object {
      // A station that cannot refill simply ends, which is what the queue was
      // going to do anyway. Nothing here is worth interrupting playback for.
    } finally {
      _busy = false;
    }
  }

  Future<String?> _artistOf(String albumRatingKey) async {
    final rows = await _db.albumsByKeys([albumRatingKey]);
    return rows.firstOrNull?.artistRatingKey;
  }
}
