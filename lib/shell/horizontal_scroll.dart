import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'layout.dart';

/// Makes a horizontal list scrollable with a mouse.
///
/// A horizontal list is fine on a phone, where you swipe it, and close to
/// unusable on a desktop, where all three of the obvious things fail:
///
/// * **The wheel does nothing.** A mouse wheel produces a vertical delta, and
///   `Scrollable` only applies a delta along its own axis — so the event falls
///   through to whatever vertical list the shelf is sitting in, and the *page*
///   scrolls instead. This maps that vertical delta onto the horizontal axis,
///   which is what every desktop app with a carousel does.
/// * **Dragging does nothing.** Flutter deliberately leaves `mouse` out of
///   `ScrollBehavior.dragDevices`, because on a normally scrollable page
///   click-dragging would fight text selection. On a shelf of album covers
///   there is nothing to select and dragging is the obvious gesture.
/// * **There is no indication it scrolls at all.** Touch platforms teach you by
///   overscroll; a desktop needs to be told, so there is a scrollbar.
///
/// The scrollbar is desktop-only — on a phone it would sit under your thumb
/// and say nothing you did not already know from swiping.
class HorizontalScroll extends StatefulWidget {
  const HorizontalScroll({required this.builder, super.key});

  /// Builds the scrollable, which must use the controller it is handed.
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<HorizontalScroll> createState() => _HorizontalScrollState();
}

class _HorizontalScrollState extends State<HorizontalScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Turns a vertical wheel notch into horizontal movement.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;

    // A trackpad two-finger swipe already carries dx and is handled by
    // `Scrollable` itself; stealing it here would double the movement.
    if (event.scrollDelta.dx != 0) return;

    final target = (_controller.offset + event.scrollDelta.dy).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    if (target == _controller.offset) return;

    // Jumped rather than animated: a wheel produces a stream of notches, and
    // animating each one lands them on top of each other and stutters.
    _controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final compact = isCompactLayout(context);

    Widget child = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          ...ScrollConfiguration.of(context).dragDevices,
          PointerDeviceKind.mouse,
        },
        // The shelf supplies its own below, and a nested one would draw twice.
        scrollbars: false,
      ),
      child: widget.builder(context, _controller),
    );

    if (!compact) {
      child = Scrollbar(
        controller: _controller,
        // Always visible rather than fading in on scroll: it is here to say
        // "this moves" to someone who has not touched it yet, which is exactly
        // the moment a fade-on-scroll bar is invisible.
        thumbVisibility: true,
        child: Padding(
          // Room for the bar, so it never sits over the bottom of a cover.
          padding: const EdgeInsets.only(bottom: 12),
          child: child,
        ),
      );
    }

    return Listener(onPointerSignal: _onPointerSignal, child: child);
  }
}
