import 'package:flutter/foundation.dart';

import '../plex/plex_models.dart';

/// Something that was listened to, whichever kind of thing it was.
///
/// "Jump back in" used to read albums only, which meant a playlist you put on
/// came back as the albums its tracks happened to belong to — a dozen entries
/// nobody chose, in place of the one thing they did. Playing a playlist now
/// credits the playlist, and this is the type that lets the shelf show it.
///
/// A pair of nullable fields rather than a sealed hierarchy: both branches
/// carry a full Plex model because the screens they open want one, and the
/// shelf only needs four things off the front of either.
@immutable
class RecentlyPlayed {
  const RecentlyPlayed.album(PlexAlbum this.album) : playlist = null;
  const RecentlyPlayed.playlist(PlexPlaylist this.playlist) : album = null;

  final PlexAlbum? album;
  final PlexPlaylist? playlist;

  bool get isPlaylist => playlist != null;

  String get ratingKey => album?.ratingKey ?? playlist!.ratingKey;

  String get title => album?.title ?? playlist!.title;

  String? get thumb => album?.thumb ?? playlist!.thumb;

  /// Zero rather than null for a playlist Plex has never recorded a play for,
  /// so it sorts last instead of throwing off the comparison.
  int get lastViewedAt => album?.lastViewedAt ?? playlist?.lastViewedAt ?? 0;

  /// The second line on a tile. An album says who made it; a playlist has no
  /// artist to name, so it says what it is — which also tells the two apart
  /// at a glance in a mixed row.
  String get subtitle {
    final playlist = this.playlist;
    if (playlist == null) return album!.artist;
    final count = playlist.itemCount;
    return count > 0
        ? 'Playlist · $count ${count == 1 ? 'track' : 'tracks'}'
        : 'Playlist';
  }
}
