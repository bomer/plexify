#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "media_controls.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Opens maximised once Flutter has a frame to show.
  //
  // Kept here rather than applied at creation because the window is
  // deliberately hidden until then, and maximising it early would show an
  // empty one for the length of the engine's startup.
  void SetStartMaximized(bool maximized) { start_maximized_ = maximized; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  bool start_maximized_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Owns the media session that receives the keyboard's media keys.
  std::unique_ptr<MediaControls> media_controls_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
