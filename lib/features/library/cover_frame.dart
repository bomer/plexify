import 'package:flutter/material.dart';

/// Puts an album cover on the page rather than in it.
///
/// Three things, none of them individually visible and all of them together
/// the difference between a grid of artwork and a spreadsheet with pictures in
/// the cells:
///
/// - **A shadow**, so the cover reads as an object sitting on the surface. This
///   is the one that matters. Flat artwork on a flat background has no edge the
///   eye can find, and a wall of it reads as texture rather than as a set of
///   things you can pick from.
/// - **A hairline border** at low opacity, which does the same job for the
///   covers a shadow cannot help: anything with white or near-white edges,
///   where the artwork simply merges into a light background.
/// - **One radius**, defined here, so shelves, grids and headers agree without
///   each of them carrying the number.
///
/// Deliberately not a hover effect. The lift is permanent, because the point is
/// to make the library legible at rest rather than to reward pointing at it,
/// and there is no hover on a phone at all.
class CoverFrame extends StatelessWidget {
  const CoverFrame({required this.child, this.radius = 6, super.key});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final corner = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corner,
        boxShadow: [
          BoxShadow(
            // Heavier in the dark theme. A shadow on a near-black background
            // has almost nothing to darken, so the same values that read as
            // subtle on white are invisible here.
            color: Colors.black.withValues(alpha: dark ? 0.55 : 0.22),
            blurRadius: dark ? 14 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: corner,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            child,
            // Inside the clip and drawn over the artwork, so it follows the
            // rounded corners exactly. A Border on the DecoratedBox above would
            // sit outside the clip and show a hairline of background at each
            // corner.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: corner,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: dark ? 0.07 : 0.10),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
