#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

bool IsCloseFromSpringNoteWindow(HWND hwnd) {
  HWND foreground = GetForegroundWindow();
  if (!foreground) {
    return true;
  }
  if (foreground == hwnd || GetAncestor(foreground, GA_ROOT) == hwnd) {
    return true;
  }

  DWORD foreground_process_id = 0;
  GetWindowThreadProcessId(foreground, &foreground_process_id);
  return foreground_process_id == GetCurrentProcessId();
}

}  // namespace

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
  auto_start_manager_ = std::make_unique<AutoStartManager>(
      flutter_controller_->engine()->messenger());
  clipboard_image_manager_ = std::make_unique<ClipboardImageManager>(
      flutter_controller_->engine()->messenger());
  desktop_widget_window_ = std::make_unique<DesktopWidgetWindow>(
      flutter_controller_->engine()->messenger(), GetHandle());
  global_hotkey_manager_ = std::make_unique<GlobalHotkeyManager>(
      flutter_controller_->engine()->messenger(), GetHandle());
  tray_manager_ = std::make_unique<TrayManager>(
      flutter_controller_->engine()->messenger(), GetHandle());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  auto_start_manager_ = nullptr;
  tray_manager_ = nullptr;
  global_hotkey_manager_ = nullptr;
  clipboard_image_manager_ = nullptr;
  desktop_widget_window_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (tray_manager_ &&
      tray_manager_->HandleMessage(hwnd, message, wparam, lparam)) {
    return 0;
  }

  if (message == WM_CLOSE && tray_manager_ &&
      tray_manager_->ShouldCloseToTray()) {
    if (IsCloseFromSpringNoteWindow(hwnd)) {
      ShowWindow(hwnd, SW_HIDE);
      return 0;
    }
    tray_manager_->PrepareForApplicationExit();
  }

  if (tray_manager_ && message == tray_manager_->QuitForUpdateMessage()) {
    tray_manager_->PrepareForApplicationExit();
    DestroyWindow(hwnd);
    return 0;
  }

  if (message == WM_QUERYENDSESSION) {
    if (tray_manager_) {
      tray_manager_->PrepareForApplicationExit();
    }
    return TRUE;
  }

  if (message == WM_ENDSESSION && wparam != FALSE && tray_manager_) {
    tray_manager_->PrepareForApplicationExit();
  }

  if (global_hotkey_manager_ &&
      global_hotkey_manager_->HandleMessage(hwnd, message, wparam, lparam)) {
    return 0;
  }

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
