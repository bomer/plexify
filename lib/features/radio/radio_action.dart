import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'autoplay.dart';

/// Why a station could not be started.
///
/// **Three causes rather than one message**, because they are indistinguishable
/// from the outside and the first build of this treated them as one. A button
/// that appears to do nothing is the worst possible reading of any of them.
enum RadioFailure {
  /// No server connection yet. Signing in is the fix.
  noServer,

  /// The artist behind the tap could not be worked out.
  noSeed,

  /// The server answered and named nobody similar, or named artists this
  /// library does not hold.
  noNeighbours;

  String get message => switch (this) {
    noServer => 'Not connected to Plex yet.',
    noSeed => 'Could not work out which artist to start from.',
    noNeighbours =>
      'Plex has nothing similar to this artist in your library yet.',
  };
}

/// Starts a station from [artistRatingKey] and says why when it cannot.
///
/// One helper rather than the same six lines on Now Playing, the artist page,
/// the album and the track sheet.
Future<void> startRadioForArtist(
  BuildContext context,
  WidgetRef ref,
  String? artistRatingKey,
) async {
  final start = ref.read(startRadioProvider);
  // Captured before the round trip: the widget that was tapped can be gone by
  // the time this answers, and a messenger is not a BuildContext.
  final messenger = ScaffoldMessenger.of(context);

  if (start == null) return _say(messenger, RadioFailure.noServer);
  if (artistRatingKey == null) return _say(messenger, RadioFailure.noSeed);

  final failure = await start(artistRatingKey);
  if (failure != null) _say(messenger, failure);
}

void _say(ScaffoldMessengerState messenger, RadioFailure failure) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(failure.message)));
}

/// Starts a station from the artist who made [albumRatingKey].
///
/// **Everywhere radio is offered, it resolves to an artist**, because that is
/// the only thing this server holds similarity data for. A tap on an album or a
/// song is therefore a tap on whoever made it, which is also what Plexamp does:
/// its sonic radio is greyed out on a song and offered on an artist.
Future<void> startRadioForAlbum(
  BuildContext context,
  WidgetRef ref,
  String? albumRatingKey,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (albumRatingKey == null) return _say(messenger, RadioFailure.noSeed);

  final album = await ref.read(albumByKeyProvider(albumRatingKey).future);
  if (!context.mounted) return;
  return startRadioForArtist(context, ref, album?.artistRatingKey);
}
