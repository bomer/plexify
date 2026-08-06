import '../artwork/artwork_cache.dart';

/// Cover art for records the library does not hold.
///
/// Plex artwork goes through the photo transcoder and is keyed on the thumb
/// path; a catalog release has neither. The Cover Art Archive serves art by the
/// same MusicBrainz ids the rest of this layer already uses, which makes the
/// MBID a natural cache key — stable, not a URL, and unaffected by which server
/// the app happens to be talking to (invariant 4).
///
/// Deliberately reuses [ArtworkCache] rather than adding a second image cache.
/// That class was written against Plex but nothing in it is Plex-specific: it
/// takes a key and a URL, holds bytes on disk, and evicts least-recently-used.
/// A parallel cache would mean a second budget, a second eviction policy and a
/// second thing to clear on sign-out.
abstract final class CoverArt {
  static const _base = 'https://coverartarchive.org/release-group';

  /// The prefix that keeps catalog entries from colliding with Plex thumb paths
  /// in the shared cache. Plex paths always start `/library/`, so this could
  /// not collide by accident, but relying on that would make the two caches
  /// share a namespace by luck rather than by design.
  static const keyPrefix = 'coverart:';

  /// Sizes the archive actually serves. Asking for anything else 404s, which
  /// presents as an album with no art rather than as a mistake.
  static const sizes = [250, 500, 1200];

  /// The front cover for a release group, at the nearest served size.
  ///
  /// Answers a redirect to archive.org, which `http` follows on its own. A
  /// release group with no uploaded art answers 404, and the cache treats that
  /// the same as any other miss: the placeholder shows, nothing is stored, and
  /// nothing is retried in a loop.
  static String url(String mbid, {int size = 500}) =>
      '$_base/$mbid/front-${_nearestSize(size)}';

  static ArtworkKey key(String mbid, {int size = 500}) =>
      ArtworkKey('$keyPrefix$mbid', _nearestSize(size));

  static int _nearestSize(int wanted) {
    for (final size in sizes) {
      if (wanted <= size) return size;
    }
    return sizes.last;
  }
}
