import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final url = ref
        .watch(plexClientProvider)
        ?.artworkUrl(thumb, width: size, height: size);

    Widget placeholder() => Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        icon,
        size: size / 6,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    if (url == null) return placeholder();

    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => placeholder(),
    );
  }
}
