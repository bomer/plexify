import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../player/playback_controller.dart';
import '../player/player_providers.dart';
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
  String? artistRatingKey, {
  String? artistName,
}) async {
  final start = ref.read(startRadioProvider);
  // Captured before the round trip: the widget that was tapped can be gone by
  // the time this answers, and a messenger is not a BuildContext.
  final messenger = ScaffoldMessenger.of(context);

  if (start == null) return _say(messenger, RadioFailure.noServer);
  if (artistRatingKey == null) return _say(messenger, RadioFailure.noSeed);

  final failure = await start(artistRatingKey);
  if (failure != null) return _say(messenger, failure);

  // **Success needs saying too, and that is not decoration.** Radio replaces
  // the queue and starts playing, but every screen it can be pressed from
  // stays exactly as it was — so on a page that fills the window the only
  // evidence anything happened is a mini player at the bottom that was already
  // there. Reported as the button appearing to do nothing on a full-screen
  // artist page.
  final expanded = ref.read(nowPlayingExpandedProvider);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          artistName == null
              ? 'Playing radio'
              : 'Playing radio based on $artistName',
        ),
        // Pointless when the player is already open over the top of this.
        action: expanded
            ? null
            : SnackBarAction(
                label: 'Open',
                onPressed: () =>
                    ref.read(nowPlayingExpandedProvider.notifier).state = true,
              ),
      ),
    );
}

void _say(ScaffoldMessengerState messenger, RadioFailure failure) =>
    _tell(messenger, failure.message);

void _tell(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Plays one of the server's own stations.
///
/// **Distinct from artist radio in where the tracks come from.** Artist radio
/// asks Plex who is similar and then builds a queue out of the local cache;
/// a station is chosen entirely by the server, so the only thing to do is ask
/// for it and play what arrives.
///
/// The error is shown rather than swallowed, and that is deliberate for now:
/// nothing about `/playQueues` has been measured against this server, and a
/// station that will not start should say what the server said rather than
/// join the list of buttons that appear to do nothing.
Future<void> playStation(
  BuildContext context,
  WidgetRef ref,
  PlexStation station,
) async {
  final client = ref.read(plexClientProvider);
  final controller = ref.read(playbackControllerProvider);
  final messenger = ScaffoldMessenger.of(context);

  if (client == null || controller == null) {
    return _say(messenger, RadioFailure.noServer);
  }

  try {
    final tracks = await client.playQueueTracks(station.key);
    if (tracks.isEmpty) return _say(messenger, RadioFailure.noNeighbours);

    await controller.playTracks(tracks);
    _tell(messenger, 'Playing ${station.title}');
  } on Object catch (error) {
    _tell(messenger, '${station.title} could not start: $error');
  }
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
  return startRadioForArtist(
    context,
    ref,
    album?.artistRatingKey,
    artistName: album?.artist,
  );
}
