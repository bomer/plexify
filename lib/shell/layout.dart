import 'package:flutter/widgets.dart';

/// Width below which the shell switches to its one-column, phone-shaped layout.
///
/// A single number so "compact" means the same thing everywhere. It is a width,
/// not a platform check, so a narrow window on the desktop gets the same
/// treatment — which is the point: the constraint is space, not hardware.
const double compactLayoutBreakpoint = 800;

/// True when there is not enough width for desktop affordances.
bool isCompactLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width < compactLayoutBreakpoint;
