import 'package:flutter/material.dart';

/// Back, floating over the top-left of a detail page.
///
/// **Replaces an `AppBar` rather than sitting inside one.** A detail page's bar
/// carried one useful control and a copy of the title printed six lines above
/// it, and it cost a full band of chrome plus a hard horizontal line straight
/// across the gradient — which is the one thing on the page actually worth
/// looking at. Floating the control keeps the wash unbroken from the very top
/// of the window.
///
/// Pinned rather than scrolled away with the header. Back is the control you
/// reach for at any point down a long track list, and having to scroll up to
/// find it would be worse than the bar it replaced.
///
/// Its own scrim because it has to stay legible over whatever the artwork
/// happens to be behind it, which on a light sleeve is white.
class DetailBack extends StatelessWidget {
  const DetailBack({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 0, 0),
      child: Material(
        shape: const CircleBorder(),
        color: scheme.surface.withValues(alpha: 0.55),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          // maybePop rather than pop: this is inside a nested navigator whose
          // first route has nothing under it, and popping that would leave the
          // tab empty rather than doing nothing.
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
    );
  }
}

/// Space a detail header leaves so [DetailBack] does not sit on top of it.
///
/// Slightly less than the app bar it replaces, so the change reclaims a little
/// room as well as removing the line.
const double detailHeaderTop = 52;
