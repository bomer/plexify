import 'package:flutter/material.dart';

import '../../core/plex/plex_models.dart';

/// Five tappable stars.
///
/// Tapping the star that is already the current rating clears it, which is the
/// only way to unrate something without a separate control — and matches how
/// every other star widget people have used behaves.
class StarRating extends StatelessWidget {
  const StarRating({
    required this.rating,
    this.onRate,
    this.size = 20,
    super.key,
  });

  /// Plex's raw 0–10 value, or null when unrated.
  final int? rating;

  /// Null renders the stars read-only.
  final void Function(int stars)? onRate;

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stars = PlexRating.toStars(rating);
    final interactive = onRate != null;

    // Five stars are wider than they look: `IconButton` enforces a minimum
    // tap target regardless of `iconSize`, so a row of them is ~200px however
    // small the icons are. The album header's column is 192px on a 360dp
    // phone, which is where the overflow banner came from.
    //
    // Scaled down rather than gated on a breakpoint, because the constraint
    // that matters is the width of *this* row's parent, not the width of the
    // window — the same widget sits in a grid tile, a list row and a header,
    // and only one of those tracks the screen. `scaleDown` is a no-op wherever
    // there is room.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= PlexRating.maxStars; i++)
            IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints.tightFor(
                width: size + 8,
                height: size + 8,
              ),
              iconSize: size,
              tooltip: interactive
                  ? (i == stars
                        ? 'Clear rating'
                        : '$i ${i == 1 ? 'star' : 'stars'}')
                  : null,
              icon: Icon(
                i <= stars ? Icons.star : Icons.star_border,
                color: i <= stars
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              // Tapping the current rating again removes it.
              onPressed: interactive ? () => onRate!(i == stars ? 0 : i) : null,
            ),
        ],
      ),
    );
  }
}
