import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import 'autoplay.dart';

/// Why a station could not be started.
///
/// **Three causes rather than one message**, because they are indistinguishable
/// from the outside and the first build of this treated them as one. A button
/// that appears to do nothing is the worst possible reading of any of them, and
/// "no similar tracks" pointed at library analysis when the real answer might be
/// that the server was unreachable.
enum RadioFailure {
  /// No server connection yet. Signing in is the fix.
  noServer,

  /// The seed track could not be found in the cache or on the server.
  noSeed,

  /// The server answered and had nothing sonically near it.
  noNeighbours;

  String get message => switch (this) {
    noServer => 'Not connected to Plex yet.',
    noSeed => 'Could not find that track on the server.',
    noNeighbours =>
      'No similar tracks. Plex builds these during library analysis '
          '(Settings, Library, Analyze) — it may not have run yet.',
  };
}

/// Starts a station from [seed] and says why when it cannot.
///
/// One helper rather than the same six lines on Now Playing, the album and the
/// track sheet.
Future<void> startRadioFrom(
  BuildContext context,
  WidgetRef ref,
  PlexTrack seed,
) async {
  final start = ref.read(startRadioProvider);
  // Captured before the round trip: the widget that was tapped can be gone by
  // the time this answers, and a messenger is not a BuildContext.
  final messenger = ScaffoldMessenger.of(context);

  if (start == null) return _say(messenger, RadioFailure.noServer);

  final failure = await start(seed);
  if (failure != null) _say(messenger, failure);
}

void _say(ScaffoldMessengerState messenger, RadioFailure failure) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(failure.message)));
}

/// Starts a station from a track known only by its ratingKey.
///
/// What Now Playing has. A `MediaItem` carries the ratingKey and the strings
/// needed to draw a player, not the `partKey` and duration a station's first
/// track needs, so the track itself has to be found.
///
/// **The cache is asked first and Plex second**, rather than the cache only.
/// Almost always the cache has it — it is playing, so it came from somewhere —
/// but a queue restored on a fresh install plays before the first sync
/// finishes, and that is exactly when a dead button would be least explicable.
Future<void> startRadioFromNowPlaying(
  BuildContext context,
  WidgetRef ref,
  String ratingKey,
) async {
  final messenger = ScaffoldMessenger.of(context);

  // Asked before the lookup rather than after it. Without a client the cache
  // read still runs, misses on a library that has not synced, and the fallback
  // has nothing to ask — so the failure surfaced as "could not find that track
  // on the server" when the truth was that there was no server.
  if (ref.read(plexClientProvider) == null) {
    return _say(messenger, RadioFailure.noServer);
  }

  final seed =
      await ref.read(trackByKeyProvider(ratingKey).future) ??
      await _fromPlex(ref, ratingKey);

  if (seed == null) return _say(messenger, RadioFailure.noSeed);
  if (!context.mounted) return;
  return startRadioFrom(context, ref, seed);
}

Future<PlexTrack?> _fromPlex(WidgetRef ref, String ratingKey) async {
  final client = ref.read(plexClientProvider);
  if (client == null) return null;
  try {
    final json = await client.metadataItem(ratingKey);
    return json == null ? null : PlexTrack.fromJson(json);
  } on Object {
    return null;
  }
}

/// Starts a station from the first playable track of [tracks].
///
/// **A station needs a track, never an album.** Plex measures sonic similarity
/// per track, so seeding from a container is a question with no defined answer.
/// The opening track is the one an album is most identified by, and it is what
/// pressing play would have started anyway.
Future<void> startRadioFromFirstOf(
  BuildContext context,
  WidgetRef ref,
  List<PlexTrack> tracks,
) async {
  final seed = tracks.where((track) => track.isPlayable).firstOrNull;
  if (seed == null) {
    return _say(ScaffoldMessenger.of(context), RadioFailure.noSeed);
  }
  return startRadioFrom(context, ref, seed);
}
