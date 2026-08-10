import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import 'autoplay.dart';

/// Starts a station from [seed] and says so when it cannot.
///
/// One helper rather than the same six lines on the album, the artist and the
/// track sheet. The failure is the part worth sharing: "nothing sounds like
/// this" is almost always an unanalysed library rather than an unusual song,
/// and a button that appears to do nothing is the worst way to say that.
Future<void> startRadioFrom(
  BuildContext context,
  WidgetRef ref,
  PlexTrack seed,
) async {
  final start = ref.read(startRadioProvider);
  if (start == null) return;

  final messenger = ScaffoldMessenger.of(context);
  final started = await start(seed);
  if (started) return;

  messenger.showSnackBar(
    const SnackBar(content: Text(radioUnavailableMessage)),
  );
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
  if (seed == null) return;
  if (!context.mounted) return;
  return startRadioFrom(context, ref, seed);
}
