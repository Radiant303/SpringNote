#ifndef RUNNER_DESKTOP_WIDGET_WINDOW_H_
#define RUNNER_DESKTOP_WIDGET_WINDOW_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <mutex>
#include <optional>
#include <string>

// Forward-declare Gdiplus::Image so this header doesn't need to pull in the
// full <gdiplus.h> (which transitively includes a lot of COM/Win32 machinery).
// Pointer members to incomplete types are well-defined C++.
namespace Gdiplus {
class Bitmap;
class Image;
}  // namespace Gdiplus

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
    std::wstring font_family = L"Segoe UI Variable";
    double font_scale_factor = 1.0;
    bool orb_mode = false;
    int wallpaper_mode = 0;       // 0=defaultWhite, 1=solid, 2=image
    COLORREF wallpaper_color = RGB(255, 255, 255);
    std::wstring wallpaper_image_path;
    double wallpaper_opacity = 1.0;
    bool dark_mode = false;
  };

  struct WidgetPosition {
    std::string screen_id;
    int x = 0;
    int y = 0;
  };

  struct RenderedWallpaperCache {
    Gdiplus::Bitmap* bitmap = nullptr;
    std::wstring path;
    int width = 0;
    int height = 0;
    double opacity = -1.0;
    COLORREF base_color = RGB(0, 0, 0);
  };

  bool EnsureWindow();
  void RegisterChannelHandler();
  void Paint();
  void MoveToDefaultPosition();
  void MoveToSavedOrDefaultPosition();
  int CurrentWidth() const;
  int CurrentHeight() const;
  int CurrentCornerRadius() const;
  void ApplyWindowShapeAndSize(bool preserve_bottom_right);
  bool UpdateWindowRegion(int width, int height, bool redraw);
  void SetExpanded(bool expanded);
  void TrackMouseLeave();
  RECT WorkAreaForMonitor(HMONITOR monitor) const;
  HMONITOR MonitorForPosition(const WidgetPosition& position) const;
  static BOOL CALLBACK FindMonitorById(HMONITOR monitor,
                                       HDC device_context,
                                       LPRECT monitor_rect,
                                       LPARAM data);
  RECT ClampedRectForOrigin(int x, int y, HMONITOR preferred_monitor) const;
  void SetBoundedWindowOrigin(int x, int y);
  void ClampWindowToVisibleMonitor(bool notify);
  WidgetPosition CaptureCurrentPosition() const;
  void NotifyPositionChanged();
  void SavePositionToRegistry();
  std::optional<WidgetPosition> LoadPositionFromRegistry();
  void UpdateSavedPosition(const flutter::EncodableMap& arguments);
  void InvokeFlutterMethod(const std::string& method);
  void OpenMainWindow();
  std::wstring FormatDuration() const;
  void EnsureGdiplus();
  void ShutdownGdiplus();
  Gdiplus::Image* GetOrLoadWallpaperImage(const std::wstring& path);
  Gdiplus::Bitmap* GetOrRenderWallpaperBitmap(const std::wstring& path,
                                              int width,
                                              int height,
                                              double opacity,
                                              COLORREF base_color);
  void ClearWallpaperCache();
  void ClearRenderedWallpaperCache();
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
  std::optional<WidgetPosition> saved_position_;
  bool positioned_ = false;
  bool expanded_ = true;
  bool tracking_mouse_leave_ = false;
  bool dragging_ = false;
  bool moved_while_pressed_ = false;
  POINT drag_start_screen_{};
  RECT drag_start_rect_{};
  int region_width_ = -1;
  int region_height_ = -1;
  int region_radius_ = -1;
  ULONG_PTR gdiplus_token_ = 0;
  bool gdiplus_initialized_ = false;
  // Cached wallpaper image. Wallpaper imports are copied to unique filenames,
  // so the path is enough to invalidate the cache. This keeps WM_PAINT off
  // synchronous filesystem metadata reads during orb/card transitions.
  Gdiplus::Image* cached_wallpaper_image_ = nullptr;
  std::wstring cached_wallpaper_path_;
  RenderedWallpaperCache cached_wallpaper_renders_[2];
  std::mutex gdiplus_mutex_;
};

#endif  // RUNNER_DESKTOP_WIDGET_WINDOW_H_
