import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../radio/radio_action.dart';

/// Gives a track row a right-click menu on the desktop.
///
/// **The desktop half of the phone's long press.** Track rows offer their extra
/// actions through `showTrackRatingSheet`, and every call site guards it with
/// `compact ? … : null` — correct, because a sheet is a phone gesture and the
/// desktop shows its stars inline instead. The cost was that anything added to
/// that sheet existed on one platform only, which is how "Start radio" ended up
/// unreachable on Windows.
///
/// Returns [child] untouched on a compact layout, where the long press already
/// covers this and a second gesture would only be a way to disagree with it.
Widget withTrackMenu({
  required WidgetRef ref,
  required PlexTrack track,
  required bool compact,
  required Widget child,
}) {
  if (compact) return child;

  return Builder(
    builder: (context) => GestureDetector(
      // Down rather than up, because that is when the pointer position is the
      // one the user aimed with, and it is where every desktop menu opens.
      onSecondaryTapDown: (details) =>
          _show(context, ref, track, details.globalPosition),
      child: child,
    ),
  );
}

/// One item, and deliberately built as a menu anyway.
///
/// A single-entry context menu looks thin, but the alternative is a bare button
/// somewhere in a row that is already carrying a title, an artist, stars and a
/// duration. This is where the next per-track action goes.
Future<void> _show(
  BuildContext context,
  WidgetRef ref,
  PlexTrack track,
  Offset at,
) async {
  final overlay = Overlay.of(context).context.findRenderObject();
  if (overlay is! RenderBox) return;

  final choice = await showMenu<_TrackAction>(
    context: context,
    position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
    items: [
      PopupMenuItem(
        value: _TrackAction.radio,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.radio),
          title: const Text('Start radio'),
          subtitle: Text(
            track.artist.isEmpty
                ? 'Music like this artist'
                : 'Music like ${track.artist}',
          ),
        ),
      ),
    ],
  );

  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _TrackAction.radio:
      await startRadioForAlbum(context, ref, track.albumRatingKey);
  }
}

enum _TrackAction { radio }
