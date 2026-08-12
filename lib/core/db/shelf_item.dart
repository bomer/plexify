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
      artist = null,
      station = null;
  const ShelfItem.playlist(PlexPlaylist this.playlist, this.startedAt)
    : album = null,
      artist = null,
      station = null;

  /// An artist, which only ever comes from a Plex hub.
  ///
  /// Nothing local produces one: this app records what was *started*, and an
  /// artist is not something you start. `music.recent.played` is the server's
  /// own recently-played row and it is artists, which is why the branch exists.
  const ShelfItem.artist(PlexArtist this.artist, this.startedAt)
    : album = null,
      playlist = null,
      station = null;

  /// One of the server's own stations, which only ever comes from a Plex hub.
  ///
  /// **The one branch that is not a destination.** Every other tile opens a
  /// screen; a station has no screen to open, because its key cannot be fetched
  /// at all. Tapping it creates a play queue and starts playing.
  const ShelfItem.station(PlexStation this.station, this.startedAt)
    : album = null,
      playlist = null,
      artist = null;

  /// When *this device* started it, from `PlaybackHistory`, or zero for a row
  /// that has its own order and never sorts on time.
  ///
  /// Deliberately not Plex's `lastViewedAt`, which every sync rewrites and
  /// which is only stamped at the 90% scrobble mark.
  final int startedAt;

  final PlexAlbum? album;
  final PlexPlaylist? playlist;
  final PlexArtist? artist;
  final PlexStation? station;

  bool get isPlaylist => playlist != null;
  bool get isArtist => artist != null;
  bool get isStation => station != null;

  /// A station's key is a path rather than a rating key, and nothing sorts or
  /// dedupes stations, so it stands in here unchanged.
  String get ratingKey =>
      album?.ratingKey ??
      playlist?.ratingKey ??
      artist?.ratingKey ??
      station!.key;

  String get title =>
      album?.title ?? playlist?.title ?? artist?.title ?? station!.title;

  String? get thumb =>
      album?.thumb ?? playlist?.thumb ?? artist?.thumb ?? station!.thumb;

  /// The second line on a tile.
  ///
  /// An album says who made it. A playlist has no artist to name, so it says
  /// what it is, which also tells the two apart at a glance in a mixed row. An
  /// artist has nothing to add and says nothing rather than repeating its own
  /// name a size smaller.
  String get subtitle {
    if (album case final album?) return album.artist;
    if (artist != null) return '';
    // Says what it is, because a station tile is the only one in a row that
    // plays on tap rather than opening something.
    if (station != null) return 'Radio';

    final count = playlist!.itemCount;
    return count > 0
        ? 'Playlist · $count ${count == 1 ? 'track' : 'tracks'}'
        : 'Playlist';
  }
}
