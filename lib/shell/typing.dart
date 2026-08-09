import 'package:flutter/widgets.dart';

/// Whether the caret is currently in a text field.
///
/// The guard on the space-to-play shortcut, and a top-level function rather
/// than a method on the shell so it can be tested against a real focused
/// `TextField` — which is the only way to catch the mistake it replaced.
///
/// **It walks *up* from the focused node, and that is the whole point.** The
/// first version asked whether the focused widget *was* an [EditableText]:
///
/// ```dart
/// if (FocusManager.instance.primaryFocus?.context?.widget is EditableText)
/// ```
///
/// That can never be true. `EditableText` builds a `Focus` internally and hands
/// it the field's focus node, so the node's context belongs to that `Focus` and
/// the type test compares against the wrong widget every time. It read as a
/// careful guard and did nothing at all, which is the worst combination.
///
/// Note the test environment does not exercise this: with no real text input
/// connection, the framework stops a plain key below the shell before the
/// shortcut is consulted. On Windows with a live connection it does not, which
/// is why typing a space in the search box paused the music.
bool isTypingSomewhere() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context != null &&
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}
