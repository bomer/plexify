#ifndef RUNNER_WINDOW_STATE_H_
#define RUNNER_WINDOW_STATE_H_

#include <windows.h>

// Remembers where the window was, across runs.
//
// Flutter's desktop runner opens at a fixed 1280x720 at (10, 10) every launch
// and keeps nothing, because there is no cross-platform place for it to keep
// anything. On Windows the natural store is the registry, and doing it here
// rather than in Dart means the size is right in the very first frame instead
// of the window jumping once the engine has started and read a preference.
struct SavedWindow {
  // False when nothing has been stored yet, or when what was stored no longer
  // describes anywhere a window could be seen.
  bool valid = false;

  // The *restored* frame in physical pixels, even when the window was closed
  // maximised. Storing the maximised rect as the normal one is what makes an
  // app un-restore to full screen for ever after.
  RECT frame = {};

  bool maximized = false;
};

// Reads the stored geometry, or returns an invalid one.
SavedWindow LoadWindowState();

// Stores the window's current geometry. Cheap enough to call on close.
void SaveWindowState(HWND window);

// Moves `window` to `state`, if `state` is usable.
//
// Does nothing for an invalid state, so the caller does not have to branch, and
// the runner keeps its own defaults for a first launch.
void ApplyWindowState(HWND window, const SavedWindow& state);

#endif  // RUNNER_WINDOW_STATE_H_
