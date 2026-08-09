#include "window_state.h"

namespace {

constexpr wchar_t kKeyPath[] = L"Software\\Plexify\\Window";
constexpr wchar_t kX[] = L"X";
constexpr wchar_t kY[] = L"Y";
constexpr wchar_t kWidth[] = L"Width";
constexpr wchar_t kHeight[] = L"Height";
constexpr wchar_t kMaximized[] = L"Maximized";

// Smallest window worth restoring to.
//
// A stored size below this is treated as no stored size at all. Zero and near
// zero are the shapes a crash mid-write leaves behind, and restoring one gives
// a window with no way to grab its edges.
constexpr LONG kMinimumEdge = 320;

bool ReadDword(HKEY key, const wchar_t* name, DWORD* out) {
  DWORD type = 0;
  DWORD size = sizeof(DWORD);
  return RegQueryValueExW(key, name, nullptr, &type,
                          reinterpret_cast<LPBYTE>(out), &size) ==
             ERROR_SUCCESS &&
         type == REG_DWORD;
}

void WriteDword(HKEY key, const wchar_t* name, DWORD value) {
  RegSetValueExW(key, name, 0, REG_DWORD, reinterpret_cast<const BYTE*>(&value),
                 sizeof(value));
}

// Whether any part of `frame` lands on a monitor that currently exists.
//
// **This is the case that makes the difference between a nice touch and a bug
// report.** A window closed on a second monitor, or on a laptop docked to a
// screen that is not there this morning, restores to coordinates nothing can
// display: the app appears to launch and then be invisible, with no way to
// reach it but a registry edit. Falling back to the default position costs one
// mis-placed launch; getting it wrong costs the whole session.
bool IsOnAScreen(const RECT& frame) {
  HMONITOR monitor = MonitorFromRect(&frame, MONITOR_DEFAULTTONULL);
  if (monitor == nullptr) {
    return false;
  }

  // On a screen is not enough on its own: a window whose title bar is above the
  // work area cannot be dragged back down. Require the top edge to be inside
  // it.
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) {
    return true;
  }
  return frame.top >= info.rcWork.top - 8 && frame.top < info.rcWork.bottom;
}

}  // namespace

SavedWindow LoadWindowState() {
  SavedWindow state;

  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kKeyPath, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return state;
  }

  DWORD x = 0, y = 0, width = 0, height = 0, maximized = 0;
  const bool complete = ReadDword(key, kX, &x) && ReadDword(key, kY, &y) &&
                        ReadDword(key, kWidth, &width) &&
                        ReadDword(key, kHeight, &height);
  ReadDword(key, kMaximized, &maximized);
  RegCloseKey(key);

  if (!complete) {
    return state;
  }

  // Signed, deliberately. A window on a monitor left of the primary one has a
  // negative x, and reading these back as unsigned puts it four billion pixels
  // away, which then fails the on-screen check and silently loses the position
  // every time.
  state.frame.left = static_cast<LONG>(static_cast<INT32>(x));
  state.frame.top = static_cast<LONG>(static_cast<INT32>(y));
  state.frame.right = state.frame.left + static_cast<LONG>(width);
  state.frame.bottom = state.frame.top + static_cast<LONG>(height);
  state.maximized = maximized != 0;

  if (static_cast<LONG>(width) < kMinimumEdge ||
      static_cast<LONG>(height) < kMinimumEdge || !IsOnAScreen(state.frame)) {
    return state;
  }

  state.valid = true;
  return state;
}

void SaveWindowState(HWND window) {
  if (window == nullptr) {
    return;
  }

  // GetWindowPlacement rather than GetWindowRect, because it reports the
  // restored frame even while the window is maximised. GetWindowRect would
  // store the screen-sized rect as the normal one, and un-maximising after a
  // restart would then do nothing visible.
  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(window, &placement)) {
    return;
  }

  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kKeyPath, 0, nullptr,
                      REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &key,
                      nullptr) != ERROR_SUCCESS) {
    return;
  }

  const RECT& normal = placement.rcNormalPosition;
  WriteDword(key, kX, static_cast<DWORD>(normal.left));
  WriteDword(key, kY, static_cast<DWORD>(normal.top));
  WriteDword(key, kWidth, static_cast<DWORD>(normal.right - normal.left));
  WriteDword(key, kHeight, static_cast<DWORD>(normal.bottom - normal.top));
  // Minimised is not worth remembering: nobody wants to launch an app straight
  // into the taskbar, so it restores to whatever it was before being minimised.
  WriteDword(key, kMaximized,
             placement.showCmd == SW_SHOWMAXIMIZED ? 1u : 0u);

  RegCloseKey(key);
}

void ApplyWindowState(HWND window, const SavedWindow& state) {
  if (window == nullptr || !state.valid) {
    return;
  }

  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(placement);
  placement.rcNormalPosition = state.frame;
  // **SW_HIDE even when the window was maximised.** The runner keeps the window
  // hidden until Flutter reports its first frame, and any SW_SHOW* here would
  // put an empty white rectangle on screen for the whole of the engine's
  // startup. Maximising is left to the moment it is shown; see
  // FlutterWindow::SetStartMaximized.
  placement.showCmd = SW_HIDE;

  SetWindowPlacement(window, &placement);
}
