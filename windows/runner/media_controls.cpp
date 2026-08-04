#include "media_controls.h"

#include <unknwn.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>

#include <string>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs;

constexpr char kChannelName[] = "plexify/media_controls";

const EncodableMap* ArgumentsOf(const flutter::MethodCall<EncodableValue>& call) {
  return std::get_if<EncodableMap>(call.arguments());
}

std::string StringArg(const EncodableMap& args, const char* key) {
  const auto it = args.find(EncodableValue(key));
  if (it == args.end()) return "";
  const auto* value = std::get_if<std::string>(&it->second);
  return value ? *value : "";
}

bool BoolArg(const EncodableMap& args, const char* key, bool fallback) {
  const auto it = args.find(EncodableValue(key));
  if (it == args.end()) return fallback;
  const auto* value = std::get_if<bool>(&it->second);
  return value ? *value : fallback;
}

// Dart strings arrive as UTF-8; WinRT wants UTF-16. Track and artist names are
// full of accented characters, so this cannot be a narrowing cast.
std::wstring Widen(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int length = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring wide(static_cast<size_t>(length), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                        static_cast<int>(utf8.size()), wide.data(), length);
  return wide;
}

}  // namespace

struct MediaControls::Impl {
  SystemMediaTransportControls controls{nullptr};
  winrt::event_token button_token{};
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
};

MediaControls::MediaControls(HWND window, flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>()) {
  impl_->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());

  try {
    // SMTC is a WinRT type with no public activation for desktop apps; the
    // interop factory is the only way to bind one to an HWND.
    auto interop = winrt::get_activation_factory<
        SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(
        window, winrt::guid_of<SystemMediaTransportControls>(),
        winrt::put_abi(impl_->controls)));
  } catch (const winrt::hresult_error&) {
    // Nothing here is load-bearing for playback. Losing media keys is worth a
    // great deal less than failing to start.
    impl_->controls = nullptr;
    return;
  }

  auto controls = impl_->controls;
  controls.IsEnabled(true);
  controls.IsPlayEnabled(true);
  controls.IsPauseEnabled(true);
  controls.IsNextEnabled(true);
  controls.IsPreviousEnabled(true);
  // Stop would show a button that ends the session outright. Every other music
  // player treats the media keys as play/pause and skip only.
  controls.IsStopEnabled(false);
  controls.PlaybackStatus(MediaPlaybackStatus::Closed);

  impl_->button_token = controls.ButtonPressed(
      [window](SystemMediaTransportControls const&,
               SystemMediaTransportControlsButtonPressedEventArgs const& args) {
        ::PostMessageW(window, MediaControls::kButtonMessage,
                       static_cast<WPARAM>(args.Button()), 0);
      });

  impl_->channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        auto controls = impl_->controls;
        if (!controls) {
          result->Success();
          return;
        }

        const EncodableMap* args = ArgumentsOf(call);
        if (args == nullptr) {
          result->Error("bad_args", "Expected a map");
          return;
        }

        if (call.method_name() == "updatePlayback") {
          const bool active = BoolArg(*args, "active", false);
          const bool playing = BoolArg(*args, "playing", false);
          controls.PlaybackStatus(
              !active ? MediaPlaybackStatus::Closed
                      : playing ? MediaPlaybackStatus::Playing
                                : MediaPlaybackStatus::Paused);
          controls.IsNextEnabled(BoolArg(*args, "hasNext", true));
          controls.IsPreviousEnabled(BoolArg(*args, "hasPrevious", true));
          result->Success();
          return;
        }

        if (call.method_name() == "updateMetadata") {
          auto updater = controls.DisplayUpdater();
          updater.Type(MediaPlaybackType::Music);
          auto music = updater.MusicProperties();
          music.Title(Widen(StringArg(*args, "title")));
          music.Artist(Widen(StringArg(*args, "artist")));
          music.AlbumTitle(Widen(StringArg(*args, "album")));
          updater.Update();
          result->Success();
          return;
        }

        result->NotImplemented();
      });
}

MediaControls::~MediaControls() {
  if (impl_->controls) {
    impl_->controls.ButtonPressed(impl_->button_token);
    impl_->controls.IsEnabled(false);
  }
}

void MediaControls::OnButtonMessage(WPARAM button) {
  const char* method = nullptr;
  switch (static_cast<SystemMediaTransportControlsButton>(button)) {
    case SystemMediaTransportControlsButton::Play:
      method = "play";
      break;
    case SystemMediaTransportControlsButton::Pause:
      method = "pause";
      break;
    case SystemMediaTransportControlsButton::Next:
      method = "next";
      break;
    case SystemMediaTransportControlsButton::Previous:
      method = "previous";
      break;
    case SystemMediaTransportControlsButton::Stop:
      method = "stop";
      break;
    default:
      return;
  }
  impl_->channel->InvokeMethod(method, nullptr);
}
