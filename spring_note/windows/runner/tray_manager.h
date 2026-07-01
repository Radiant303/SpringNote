#ifndef RUNNER_TRAY_MANAGER_H_
#define RUNNER_TRAY_MANAGER_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

class TrayManager {
 public:
  TrayManager(flutter::BinaryMessenger* messenger, HWND main_window);
  ~TrayManager();

  TrayManager(const TrayManager&) = delete;
  TrayManager& operator=(const TrayManager&) = delete;

  bool HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  bool ShouldCloseToTray() const;
  void PrepareForApplicationExit();
  UINT QuitForUpdateMessage() const;
  void ShowMainWindow();

 private:
  void RegisterChannelHandler();
  void Configure(bool show_tray_icon, bool close_to_tray);
  void ShowTrayIcon();
  void HideTrayIcon();
  void ShowContextMenu();
  void ExitApplication();

  flutter::BinaryMessenger* messenger_ = nullptr;
  HWND main_window_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool tray_icon_visible_ = false;
  bool close_to_tray_ = false;
  bool exiting_ = false;
};

#endif  // RUNNER_TRAY_MANAGER_H_
