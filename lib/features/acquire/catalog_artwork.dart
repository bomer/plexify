import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/artwork/artwork_image.dart';
import '../../core/catalog/cover_art.dart';
import '../../core/providers.dart';

/// Cover art for a record the library does not hold.
///
/// The catalog counterpart of [Artwork], and it goes through exactly the same
/// disk cache (invariant 3) — the key is the MusicBrainz id rather than a Plex
/// thumb path, which is a different namespace in the same store. A second image
/// cache would have meant a second budget, a second eviction policy and a second
/// thing to clear.
///
/// A missing cover is the ordinary case here, not a failure: plenty of release
/// groups have nothing uploaded to the Cover Art Archive, and the placeholder is
/// the right answer rather than an error.
class CatalogArtwork extends ConsumerWidget {
  const CatalogArtwork({required this.mbid, this.size = 300, super.key});

  final String mbid;
  final int size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    Widget placeholder() => Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.album_outlined,
        size: size / 6,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    if (mbid.isEmpty) return placeholder();

    return Image(
      image: PlexArtwork(
        thumb: CoverArt.key(mbid, size: size).thumb,
        size: CoverArt.key(mbid, size: size).size,
        cache: ref.watch(artworkCacheProvider),
        url: CoverArt.url(mbid, size: size),
      ),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      frameBuilder: (context, child, frame, wasSynchronous) {
        if (wasSynchronous || frame != null) return child;
        return placeholder();
      },
      errorBuilder: (_, _, _) => placeholder(),
    );
  }
}
