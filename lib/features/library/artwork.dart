import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/artwork/artwork_image.dart';
import '../../core/providers.dart';

/// Plex artwork with a consistent placeholder.
///
/// Centralised because every grid, shelf and header needs the same three
/// behaviours — resolve the thumb through the photo transcoder, show a
/// placeholder when there is no artwork, and show the *same* placeholder when
/// the image fails to load rather than a broken-image glyph.
///
/// [size] is passed to Plex's transcoder, so list cells fetch small images
/// instead of pulling full-resolution art over the network.
///
/// Images come from [PlexArtwork], which caches to disk keyed on the thumb and
/// size. That is what makes a second launch instant, and it is why this widget
/// still draws a full grid while disconnected: a cached image needs no URL.
class Artwork extends ConsumerWidget {
  const Artwork({
    required this.thumb,
    this.size = 300,
    this.icon = Icons.album,
    super.key,
  });

  final String? thumb;
  final int size;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    Widget placeholder() => Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        icon,
        size: size / 6,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    final path = thumb;
    if (path == null || path.isEmpty) return placeholder();

    // Null while disconnected, which is not a reason to give up: the cache is
    // consulted first and only needs this on a miss.
    final url = ref
        .watch(plexClientProvider)
        ?.artworkUrl(path, width: size, height: size);

    return Image(
      image: PlexArtwork(
        thumb: path,
        size: size,
        cache: ref.watch(artworkCacheProvider),
        url: url,
      ),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // The placeholder stands in while loading too, so a scrolling grid shows
      // album-shaped tiles rather than holes that fill in one by one.
      frameBuilder: (context, child, frame, wasSynchronous) {
        if (wasSynchronous || frame != null) return child;
        return placeholder();
      },
      errorBuilder: (_, _, _) => placeholder(),
    );
  }
}
