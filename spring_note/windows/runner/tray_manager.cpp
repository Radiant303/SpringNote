#include "tray_manager.h"

#include <shellapi.h>

#include <string>

#include "resource.h"

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 0x42;
constexpr UINT kQuitForUpdateMessage = WM_APP + 0x43;
constexpr UINT kTrayIconId = 0x5352;
constexpr UINT kOpenMenuId = 0x1001;
constexpr UINT kExitMenuId = 0x1002;

bool ReadBool(const flutter::EncodableMap& map,
              const char* key,
              bool fallback = false) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end() || !std::holds_alternative<bool>(it->second)) {
    return fallback;
  }
  return std::get<bool>(it->second);
}

NOTIFYICONDATA BuildIconData(HWND window) {
  NOTIFYICONDATA data{};
  data.cbSize = sizeof(NOTIFYICONDATA);
  data.hWnd = window;
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayCallbackMessage;
  data.hIcon = static_cast<HICON>(
      LoadImage(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON),
                IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
                GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR));
  wcscpy_s(data.szTip, L"SpringNote");
  return data;
}

}  // namespace

TrayManager::TrayManager(flutter::BinaryMessenger* messenger, HWND main_window)
    : messenger_(messenger), main_window_(main_window) {
  if (messenger_) {
    RegisterChannelHandler();
  }
}

TrayManager::~TrayManager() {
  HideTrayIcon();
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

bool TrayManager::ShouldCloseToTray() const {
  return !exiting_ && tray_icon_visible_ && close_to_tray_;
}

void TrayManager::PrepareForApplicationExit() {
  exiting_ = true;
  close_to_tray_ = false;
  HideTrayIcon();
}

UINT TrayManager::QuitForUpdateMessage() const {
  return kQuitForUpdateMessage;
}

void TrayManager::RegisterChannelHandler() {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger_, "spring_note/tray",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "configure") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (!arguments) {
            result->Error("bad_args", "configure expects a map");
            return;
          }
          Configure(ReadBool(*arguments, "showTrayIcon"),
                    ReadBool(*arguments, "closeToTray"));
          result->Success();
          return;
        }

        if (call.method_name() == "dispose") {
          HideTrayIcon();
          close_to_tray_ = false;
          result->Success();
          return;
        }

        if (call.method_name() == "prepareForApplicationExit") {
          PrepareForApplicationExit();
          result->Success();
          return;
        }

        if (call.method_name() == "quitForUpdate") {
          PrepareForApplicationExit();
          result->Success();
          if (main_window_) {
            PostMessage(main_window_, kQuitForUpdateMessage, 0, 0);
          }
          return;
        }

        result->NotImplemented();
      });
}

void TrayManager::Configure(bool show_tray_icon, bool close_to_tray) {
  close_to_tray_ = show_tray_icon && close_to_tray;
  if (show_tray_icon) {
    ShowTrayIcon();
  } else {
    HideTrayIcon();
  }
}

void TrayManager::ShowTrayIcon() {
  if (!main_window_) {
    return;
  }

  NOTIFYICONDATA data = BuildIconData(main_window_);
  const BOOL result =
      Shell_NotifyIcon(tray_icon_visible_ ? NIM_MODIFY : NIM_ADD, &data);
  tray_icon_visible_ = result != FALSE;
  if (data.hIcon) {
    DestroyIcon(data.hIcon);
  }
}

void TrayManager::HideTrayIcon() {
  if (!tray_icon_visible_ || !main_window_) {
    return;
  }

  NOTIFYICONDATA data{};
  data.cbSize = sizeof(NOTIFYICONDATA);
  data.hWnd = main_window_;
  data.uID = kTrayIconId;
  Shell_NotifyIcon(NIM_DELETE, &data);
  tray_icon_visible_ = false;
}

bool TrayManager::HandleMessage(HWND hwnd,
                                UINT message,
                                WPARAM wparam,
                                LPARAM lparam) {
  if (hwnd != main_window_) {
    return false;
  }

  if (message == kTrayCallbackMessage &&
      static_cast<UINT>(wparam) == kTrayIconId) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP:
      case WM_LBUTTONDBLCLK:
        ShowMainWindow();
        return true;
      case WM_RBUTTONUP:
        ShowContextMenu();
        return true;
      default:
        return false;
    }
  }

  if (message == WM_COMMAND) {
    switch (LOWORD(wparam)) {
      case kOpenMenuId:
        ShowMainWindow();
        return true;
      case kExitMenuId:
        ExitApplication();
        return true;
      default:
        return false;
    }
  }

  return false;
}

void TrayManager::ShowMainWindow() {
  if (!main_window_) {
    return;
  }

  if (IsIconic(main_window_)) {
    ShowWindow(main_window_, SW_RESTORE);
  } else {
    ShowWindow(main_window_, SW_SHOW);
  }
  SetForegroundWindow(main_window_);
}

void TrayManager::ShowContextMenu() {
  if (!main_window_) {
    return;
  }

  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }

  AppendMenu(menu, MF_STRING, kOpenMenuId, L"\u6253\u5f00 SpringNote");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kExitMenuId, L"\u9000\u51fa");

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(main_window_);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_LEFTALIGN,
                 cursor.x, cursor.y, 0, main_window_, nullptr);
  DestroyMenu(menu);
}

void TrayManager::ExitApplication() {
  PrepareForApplicationExit();
  HideTrayIcon();
  if (main_window_) {
    PostMessage(main_window_, WM_CLOSE, 0, 0);
  }
}
