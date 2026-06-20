#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "auto_start_manager.h"
#include "desktop_widget_window.h"
#include "global_hotkey_manager.h"
#include "tray_manager.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Native always-on-top desktop widget controlled by Flutter state.
  std::unique_ptr<DesktopWidgetWindow> desktop_widget_window_;

  // Native global hotkeys controlled by Flutter settings.
  std::unique_ptr<GlobalHotkeyManager> global_hotkey_manager_;

  // Native Windows tray icon and close-to-tray behavior.
  std::unique_ptr<TrayManager> tray_manager_;

  // Native current-user Windows startup entry controlled by Flutter settings.
  std::unique_ptr<AutoStartManager> auto_start_manager_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
