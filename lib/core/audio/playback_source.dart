import 'package:flutter/foundation.dart';

/// What a queue was started *from*.
///
/// A queue is a flat list of tracks and remembers nothing about where it came
/// from, which turns out to be the wrong amount of forgetting in two places.
/// "Jump back in" showed the album a track belonged to rather than the
/// playlist that was actually put on, so an evening with one playlist filled
/// the shelf with albums nobody chose; and a restored session could say what
/// was playing but not what you were listening *to*.
///
/// Deliberately a `(kind, ratingKey)` pair and nothing else. The title and
/// artwork are looked up from the cache when needed, so a playlist renamed
/// between sessions comes back with its new name rather than a stale copy.
@immutable
class PlaybackSource {
  const PlaybackSource(this.kind, this.ratingKey);

  final PlaybackSourceKind kind;
  final String ratingKey;

  static const _separator = ':';

  /// Flattened for `MediaItem.extras`, which must hold values the platform
  /// channel can carry — so a string, not an object.
  String encode() => '${kind.name}$_separator$ratingKey';

  static PlaybackSource? decode(Object? value) {
    if (value is! String) return null;
    final at = value.indexOf(_separator);
    if (at <= 0 || at == value.length - 1) return null;
    final name = value.substring(0, at);
    for (final kind in PlaybackSourceKind.values) {
      if (kind.name == name) {
        return PlaybackSource(kind, value.substring(at + 1));
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackSource &&
      other.kind == kind &&
      other.ratingKey == ratingKey;

  @override
  int get hashCode => Object.hash(kind, ratingKey);

  @override
  String toString() => 'PlaybackSource(${encode()})';
}

enum PlaybackSourceKind {
  album,
  playlist,

  /// Everything by an artist, played from their page. Not a container Plex
  /// has a play history for, so it is recorded here and nowhere else.
  artist,
}
