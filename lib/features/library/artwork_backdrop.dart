import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// A wash of colour taken from a piece of artwork, behind everything else.
///
/// The cheapest beauty available to this app, and the only one that cannot look
/// generic: the source is the record you are looking at, so every page is
/// coloured by its own content rather than by a palette somebody chose once.
/// It is also why the chrome everywhere else is deliberately neutral — two
/// sources of colour would fight, and the artwork should win.
///
/// The colour arrives asynchronously and is null until it does, and null again
/// for a cover that is genuinely monochrome, so this has to look deliberate
/// with no colour at all rather than merely unfinished. It fades in over a
/// third of a second, because appearing instantly on every navigation reads as
/// a flicker and the eye notices a hard cut in a large flat area far more than
/// a slow one.
///
/// Stops well short of the bottom. A full-height tint is a coloured screen
/// rather than a lit one, and the lists underneath need ordinary contrast to
/// stay readable.
class ArtworkBackdrop extends ConsumerWidget {
  const ArtworkBackdrop({
    required this.thumb,
    required this.child,
    this.strength = 0.38,
    this.stop = 0.65,
    super.key,
  });

  final String? thumb;
  final Widget child;

  /// How much of the artwork's colour reaches the top of the page.
  ///
  /// Kept well under half. The sleeve's own colour at full strength fights the
  /// artwork it came from, and a light cover would leave white text on a pale
  /// wash.
  final double strength;

  /// Where the tint has finished fading into the plain surface, as a fraction
  /// of the page's height.
  final double stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final path = thumb;
    final colour = path == null || path.isEmpty
        ? null
        : ref.watch(artworkColourProvider(path)).valueOrNull;

    final tint = colour == null
        ? theme.colorScheme.surface
        : Color.alphaBlend(
            colour.withValues(alpha: strength),
            theme.colorScheme.surface,
          );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint, theme.colorScheme.surface],
          stops: [0, stop],
        ),
      ),
      child: child,
    );
  }
}
