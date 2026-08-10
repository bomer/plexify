import 'package:flutter/foundation.dart';

import '../plex/plex_models.dart';

/// One tile on a Home shelf, whichever kind of thing it is.
///
/// Named for its first use, which was "Jump back in", and now carries every
/// row: a shelf may hold albums, the playlists you actually put on, or the
/// artists a Plex hub named. The three branches exist because the tile needs
/// four things off the front of any of them and the screens they open want the
/// whole model.
///
/// **"Jump back in" is why the playlist branch exists.** It used to read albums
/// only, so a playlist you put on came back as the dozen albums its tracks
/// happened to belong to, in place of the one thing you chose. Playing a
/// playlist now credits the playlist.
///
/// Three nullable fields rather than a sealed hierarchy: each branch carries a
/// full Plex model because the screens they open want one, and a sealed type
/// would mean a switch at every call site for an answer that is always the
/// same shape.
@immutable
class ShelfItem {
  const ShelfItem.album(PlexAlbum this.album, this.startedAt)
    : playlist = null,
      artist = null;
  const ShelfItem.playlist(PlexPlaylist this.playlist, this.startedAt)
    : album = null,
      artist = null;

  /// An artist, which only ever comes from a Plex hub.
  ///
  /// Nothing local produces one: this app records what was *started*, and an
  /// artist is not something you start. `music.recent.played` is the server's
  /// own recently-played row and it is artists, which is why the branch exists.
  const ShelfItem.artist(PlexArtist this.artist, this.startedAt)
    : album = null,
      playlist = null;

  /// When *this device* started it, from `PlaybackHistory`, or zero for a row
  /// that has its own order and never sorts on time.
  ///
  /// Deliberately not Plex's `lastViewedAt`, which every sync rewrites and
  /// which is only stamped at the 90% scrobble mark.
  final int startedAt;

  final PlexAlbum? album;
  final PlexPlaylist? playlist;
  final PlexArtist? artist;

  bool get isPlaylist => playlist != null;
  bool get isArtist => artist != null;

  String get ratingKey =>
      album?.ratingKey ?? playlist?.ratingKey ?? artist!.ratingKey;

  String get title => album?.title ?? playlist?.title ?? artist!.title;

  String? get thumb => album?.thumb ?? playlist?.thumb ?? artist!.thumb;

  /// The second line on a tile.
  ///
  /// An album says who made it. A playlist has no artist to name, so it says
  /// what it is, which also tells the two apart at a glance in a mixed row. An
  /// artist has nothing to add and says nothing rather than repeating its own
  /// name a size smaller.
  String get subtitle {
    if (album case final album?) return album.artist;
    if (artist != null) return '';

    final count = playlist!.itemCount;
    return count > 0
        ? 'Playlist · $count ${count == 1 ? 'track' : 'tracks'}'
        : 'Playlist';
  }
}
