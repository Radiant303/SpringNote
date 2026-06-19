#ifndef RUNNER_DESKTOP_WIDGET_WINDOW_H_
#define RUNNER_DESKTOP_WIDGET_WINDOW_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

class DesktopWidgetWindow {
 public:
  DesktopWidgetWindow(flutter::BinaryMessenger* messenger, HWND main_window);
  ~DesktopWidgetWindow();

  DesktopWidgetWindow(const DesktopWidgetWindow&) = delete;
  DesktopWidgetWindow& operator=(const DesktopWidgetWindow&) = delete;

  void ShowOrUpdate(const flutter::EncodableMap& arguments);
  void Hide();

 private:
  struct WidgetState {
    bool running = true;
    int work_seconds = 0;
    double coins = 0.0;
    double coin_rate_per_second = 0.0;
    int level = 1;
    int experience_percent = 0;
    double progress = 0.0;
  };

  bool EnsureWindow();
  void RegisterChannelHandler();
  void Paint();
  void MoveToDefaultPosition();
  void InvokeFlutterMethod(const std::string& method);
  void OpenMainWindow();
  std::wstring FormatDuration() const;
  static LRESULT CALLBACK WindowProc(HWND hwnd,
                                     UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam);
  LRESULT HandleMessage(HWND hwnd,
                        UINT message,
                        WPARAM wparam,
                        LPARAM lparam);

  flutter::BinaryMessenger* messenger_ = nullptr;
  HWND main_window_ = nullptr;
  HWND window_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  WidgetState state_;
  bool positioned_ = false;
  bool dragging_ = false;
  bool moved_while_pressed_ = false;
  POINT drag_start_screen_{};
  RECT drag_start_rect_{};
};

#endif  // RUNNER_DESKTOP_WIDGET_WINDOW_H_
