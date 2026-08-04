#ifndef RUNNER_MEDIA_CONTROLS_H_
#define RUNNER_MEDIA_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

// Windows' System Media Transport Controls.
//
// This is what makes the keyboard's play/pause and next/previous keys work.
// Those keys are not delivered to the focused window as ordinary key events --
// Windows routes them to whichever application currently owns a media session
// -- so an app that never registers one simply never hears them, no matter how
// it handles input. Handling them in Dart is not an option for the same reason.
//
// Registering also puts the current track in the volume flyout and on the lock
// screen, which is where the same controls live on Android.
class MediaControls {
 public:
  // Posted to the window when a transport button is pressed.
  //
  // The button callback arrives on an arbitrary thread, and Flutter's channels
  // may only be touched from the platform thread, so presses are bounced
  // through the message loop rather than dispatched where they land.
  static constexpr UINT kButtonMessage = WM_APP + 0x4d43;

  MediaControls(HWND window, flutter::BinaryMessenger* messenger);
  ~MediaControls();

  MediaControls(const MediaControls&) = delete;
  MediaControls& operator=(const MediaControls&) = delete;

  // Forwards a press to Dart. Called on the platform thread when the window
  // receives kButtonMessage.
  void OnButtonMessage(WPARAM button);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_MEDIA_CONTROLS_H_
