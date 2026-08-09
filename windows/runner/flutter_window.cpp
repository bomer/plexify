#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "window_state.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Bound to this window, because that is what the OS hands media keys to.
  media_controls_ = std::make_unique<MediaControls>(
      GetHandle(), flutter_controller_->engine()->messenger());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // Maximised here rather than at creation, so the window that appears is
    // already the right shape and already has something in it. Win32Window::Show
    // hard-codes SW_SHOWNORMAL, which would un-maximise a restored window on
    // every launch.
    ShowWindow(GetHandle(),
               start_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Released before the engine: it holds a channel onto the messenger.
  media_controls_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      // Saved here rather than in OnDestroy, which runs after WM_DESTROY has
      // already cleared the handle: by then there is no window left to ask
      // where it was. This is the last message at which the answer exists.
      SaveWindowState(hwnd);
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case MediaControls::kButtonMessage:
      // Posted from the SMTC callback thread; this is the platform thread,
      // which is the only one allowed to touch a Flutter channel.
      if (media_controls_) {
        media_controls_->OnButtonMessage(wparam);
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
