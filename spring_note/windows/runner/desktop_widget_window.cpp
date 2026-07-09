#include "desktop_widget_window.h"

#include <flutter/standard_method_codec.h>
#include <windowsx.h>

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <limits>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#include <gdiplus.h>
#include <gdipluscolormatrix.h>

namespace {

constexpr wchar_t kWidgetWindowClassName[] = L"SPRING_NOTE_DESKTOP_WIDGET";
constexpr wchar_t kRegistryPath[] = L"Software\\SpringNote\\DesktopWidget";
constexpr wchar_t kRegistryScreenId[] = L"screen_id";
constexpr wchar_t kRegistryX[] = L"x";
constexpr wchar_t kRegistryY[] = L"y";

// RAII wrapper that guarantees RegCloseKey on destruction or early return.
class RegKey {
 public:
  RegKey() = default;
  ~RegKey() { Close(); }
  RegKey(const RegKey&) = delete;
  RegKey& operator=(const RegKey&) = delete;

  HKEY get() const { return key_; }
  bool valid() const { return key_ != nullptr; }

  LSTATUS Create(HKEY root, const wchar_t* sub_key, REGSAM access) {
    Close();
    return RegCreateKeyExW(root, sub_key, 0, nullptr, 0, access, nullptr,
                           &key_, nullptr);
  }

  LSTATUS Open(HKEY root, const wchar_t* sub_key, REGSAM access) {
    Close();
    return RegOpenKeyExW(root, sub_key, 0, access, &key_);
  }

  void Close() {
    if (key_) {
      RegCloseKey(key_);
      key_ = nullptr;
    }
  }

 private:
  HKEY key_ = nullptr;
};

void LogRegistryError(const wchar_t* operation, LSTATUS status) {
  std::wstringstream stream;
  stream << L"SpringNote: desktop widget registry " << operation
         << L" failed with status " << status << L".\n";
  OutputDebugStringW(stream.str().c_str());
}

constexpr int kExpandedWindowWidth = 260;
constexpr int kExpandedWindowHeight = 140;
constexpr int kExpandedCornerRadius = 16;
constexpr int kOrbWindowSize = 64;

struct MonitorSearchContext {
  const std::string* target_id;
  HMONITOR monitor = nullptr;
};

bool PointInRoundRectRegion(const POINT& client_point,
                            int width,
                            int height,
                            int radius) {
  HRGN region =
      CreateRoundRectRgn(0, 0, width + 1, height + 1, radius * 2, radius * 2);
  if (!region) {
    return client_point.x >= 0 && client_point.x < width &&
           client_point.y >= 0 && client_point.y < height;
  }
  const bool inside = PtInRegion(region, client_point.x, client_point.y) != 0;
  DeleteObject(region);
  return inside;
}

int ReadInt(const flutter::EncodableMap& map,
            const char* key,
            int fallback = 0) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return fallback;
  }
  if (std::holds_alternative<int32_t>(it->second)) {
    return std::get<int32_t>(it->second);
  }
  if (std::holds_alternative<int64_t>(it->second)) {
    return static_cast<int>(std::get<int64_t>(it->second));
  }
  return fallback;
}

int64_t ReadInt64(const flutter::EncodableMap& map,
                  const char* key,
                  int64_t fallback = 0) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return fallback;
  }
  if (std::holds_alternative<int32_t>(it->second)) {
    return std::get<int32_t>(it->second);
  }
  if (std::holds_alternative<int64_t>(it->second)) {
    return std::get<int64_t>(it->second);
  }
  return fallback;
}

double ReadDouble(const flutter::EncodableMap& map,
                  const char* key,
                  double fallback = 0.0) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return fallback;
  }
  if (std::holds_alternative<double>(it->second)) {
    return std::get<double>(it->second);
  }
  if (std::holds_alternative<int32_t>(it->second)) {
    return static_cast<double>(std::get<int32_t>(it->second));
  }
  if (std::holds_alternative<int64_t>(it->second)) {
    return static_cast<double>(std::get<int64_t>(it->second));
  }
  return fallback;
}

bool ReadBool(const flutter::EncodableMap& map,
              const char* key,
              bool fallback = false) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end() || !std::holds_alternative<bool>(it->second)) {
    return fallback;
  }
  return std::get<bool>(it->second);
}

std::string ReadString(const flutter::EncodableMap& map,
                       const char* key,
                       const std::string& fallback = "") {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end() || !std::holds_alternative<std::string>(it->second)) {
    return fallback;
  }
  return std::get<std::string>(it->second);
}

const flutter::EncodableMap* ReadMap(const flutter::EncodableMap& map,
                                     const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(&it->second);
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return L"";
  }
  const int required_size =
      MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                          static_cast<int>(value.size()), nullptr, 0);
  if (required_size <= 0) {
    return L"";
  }
  std::wstring result(required_size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(),
                      required_size);
  return result;
}

std::string WideToUtf8(const wchar_t* value) {
  if (!value) {
    return "";
  }
  const int wide_length = lstrlenW(value);
  if (wide_length <= 0) {
    return "";
  }
  const int required_size = WideCharToMultiByte(
      CP_UTF8, 0, value, wide_length, nullptr, 0, nullptr, nullptr);
  if (required_size <= 0) {
    return "";
  }
  std::string result(required_size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, wide_length, result.data(),
                      required_size, nullptr, nullptr);
  return result;
}

std::wstring ResolveFontFamily(const std::string& app_font) {
  if (app_font.empty() || app_font == "system") {
    return L"Segoe UI Variable";
  }
  const std::wstring font_family = Utf8ToWide(app_font);
  return font_family.empty() ? L"Segoe UI Variable" : font_family;
}

void FillRoundRect(HDC dc, const RECT& rect, int radius, COLORREF color) {
  HBRUSH brush = CreateSolidBrush(color);
  HBRUSH old_brush = static_cast<HBRUSH>(SelectObject(dc, brush));
  HPEN pen = CreatePen(PS_SOLID, 1, color);
  HPEN old_pen = static_cast<HPEN>(SelectObject(dc, pen));
  RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, radius, radius);
  SelectObject(dc, old_pen);
  SelectObject(dc, old_brush);
  DeleteObject(pen);
  DeleteObject(brush);
}

void DrawTextLine(HDC dc,
                  const std::wstring& text,
                  const RECT& rect,
                  int font_size,
                  int weight,
                  const std::wstring& font_family,
                  COLORREF color,
                  UINT format) {
  HFONT font = CreateFont(
      -font_size, 0, 0, 0, weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
      OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
      DEFAULT_PITCH | FF_DONTCARE, font_family.c_str());
  HFONT old_font = static_cast<HFONT>(SelectObject(dc, font));
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, color);
  RECT text_rect = rect;
  DrawText(dc, text.c_str(), -1, &text_rect, format);
  SelectObject(dc, old_font);
  DeleteObject(font);
}

}  // namespace

DesktopWidgetWindow::DesktopWidgetWindow(flutter::BinaryMessenger* messenger,
                                         HWND main_window)
    : messenger_(messenger), main_window_(main_window) {
  RegisterChannelHandler();
  EnsureGdiplus();
}

DesktopWidgetWindow::~DesktopWidgetWindow() {
  Hide();
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
  ShutdownGdiplus();
}

void DesktopWidgetWindow::EnsureGdiplus() {
  // Guard the GDI+ startup flag and token so concurrent calls from
  // different threads (e.g. Paint() racing with the destructor) cannot
  // observe an inconsistent state or invoke GdiplusStartup twice.
  std::lock_guard<std::mutex> lock(gdiplus_mutex_);
  if (gdiplus_initialized_) {
    return;
  }
  Gdiplus::GdiplusStartupInput input;
  const Gdiplus::Status status =
      Gdiplus::GdiplusStartup(&gdiplus_token_, &input, nullptr);
  gdiplus_initialized_ = (status == Gdiplus::Ok);
  if (!gdiplus_initialized_) {
    gdiplus_token_ = 0;
    OutputDebugStringW(
        L"SpringNote: GdiplusStartup failed; wallpaper image rendering will be disabled.\n");
  }
}

void DesktopWidgetWindow::ShutdownGdiplus() {
  // The same lock used by EnsureGdiplus/Paint() so a teardown that races
  // with a paint frame cannot delete the cached Gdiplus::Image* while the
  // graphics pipeline is still dereferencing it.
  std::lock_guard<std::mutex> lock(gdiplus_mutex_);
  // Drop the cached image first; its destructor relies on a live GDI+
  // runtime, so this must happen before GdiplusShutdown.
  ClearWallpaperCache();

  if (!gdiplus_initialized_) {
    return;
  }
  Gdiplus::GdiplusShutdown(gdiplus_token_);
  gdiplus_token_ = 0;
  gdiplus_initialized_ = false;
}

Gdiplus::Image* DesktopWidgetWindow::GetOrLoadWallpaperImage(
    const std::wstring& path) {
  // Precondition: caller must hold gdiplus_mutex_. This guarantees the
  // cached image is not concurrently mutated (or destroyed) while we
  // inspect it or replace it.
  if (path.empty()) {
    return nullptr;
  }

  // Cache hit: same imported wallpaper path. Returning the existing
  // Gdiplus::Image* avoids decoder initialisation and filesystem metadata
  // reads on every WM_PAINT.
  if (cached_wallpaper_image_ != nullptr &&
      cached_wallpaper_path_ == path) {
    return cached_wallpaper_image_;
  }

  // Cache miss: load the new image from disk. FromFile returns a non-null
  // pointer even on failure, so we must check GetLastStatus().
  Gdiplus::Image* loaded = Gdiplus::Image::FromFile(path.c_str());
  if (loaded == nullptr || loaded->GetLastStatus() != Gdiplus::Ok) {
    delete loaded;
    // Keep the previous (still valid) cache around in case the new path
    // is transient; if the caller really wants a fresh load they can call
    // ClearWallpaperCache() explicitly. This also avoids holding a stale
    // pointer to an already-freed image.
    return nullptr;
  }

  // Replace the cache atomically. We delete the old image *after* the
  // new one is safely owned, so any thread waiting on the mutex sees a
  // consistent cache snapshot.
  delete cached_wallpaper_image_;
  cached_wallpaper_image_ = loaded;
  cached_wallpaper_path_ = path;
  return cached_wallpaper_image_;
}

Gdiplus::Bitmap* DesktopWidgetWindow::GetOrRenderWallpaperBitmap(
    const std::wstring& path,
    int width,
    int height,
    double opacity,
    COLORREF base_color) {
  // Precondition: caller must hold gdiplus_mutex_.
  if (path.empty() || width <= 0 || height <= 0) {
    return nullptr;
  }

  const double normalized_opacity = std::clamp(opacity, 0.0, 1.0);
  RenderedWallpaperCache& cache =
      (width <= kOrbWindowSize && height <= kOrbWindowSize)
          ? cached_wallpaper_renders_[0]
          : cached_wallpaper_renders_[1];
  if (cache.bitmap != nullptr && cache.path == path && cache.width == width &&
      cache.height == height &&
      std::abs(cache.opacity - normalized_opacity) < 0.001 &&
      cache.base_color == base_color) {
    return cache.bitmap;
  }

  Gdiplus::Image* src = GetOrLoadWallpaperImage(path);
  if (src == nullptr) {
    return nullptr;
  }
  const int img_w = static_cast<int>(src->GetWidth());
  const int img_h = static_cast<int>(src->GetHeight());
  if (img_w <= 0 || img_h <= 0) {
    return nullptr;
  }

  Gdiplus::Bitmap* rendered =
      new Gdiplus::Bitmap(width, height, PixelFormat32bppPARGB);
  if (rendered == nullptr || rendered->GetLastStatus() != Gdiplus::Ok) {
    delete rendered;
    return nullptr;
  }

  Gdiplus::Graphics render_graphics(rendered);
  render_graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  render_graphics.SetInterpolationMode(
      Gdiplus::InterpolationModeHighQualityBicubic);

  Gdiplus::Color base(255, GetRValue(base_color), GetGValue(base_color),
                      GetBValue(base_color));
  Gdiplus::SolidBrush base_brush(base);
  render_graphics.FillRectangle(&base_brush, 0, 0, width, height);

  const double scale_x =
      static_cast<double>(width) / static_cast<double>(img_w);
  const double scale_y =
      static_cast<double>(height) / static_cast<double>(img_h);
  const double scale = (scale_x > scale_y) ? scale_x : scale_y;
  const int draw_w = std::max(1, static_cast<int>(img_w * scale));
  const int draw_h = std::max(1, static_cast<int>(img_h * scale));
  const int draw_x = (width - draw_w) / 2;
  const int draw_y = (height - draw_h) / 2;

  if (normalized_opacity < 1.0) {
    Gdiplus::ColorMatrix matrix{};
    matrix.m[0][0] = 1.0f;
    matrix.m[1][1] = 1.0f;
    matrix.m[2][2] = 1.0f;
    matrix.m[3][3] = static_cast<Gdiplus::REAL>(normalized_opacity);
    matrix.m[4][4] = 1.0f;
    Gdiplus::ImageAttributes attrs;
    attrs.SetColorMatrix(&matrix);
    render_graphics.DrawImage(src, Gdiplus::Rect(draw_x, draw_y, draw_w, draw_h),
                              0, 0, img_w, img_h, Gdiplus::UnitPixel, &attrs);
  } else {
    render_graphics.DrawImage(src, draw_x, draw_y, draw_w, draw_h);
  }

  delete cache.bitmap;
  cache.bitmap = rendered;
  cache.path = path;
  cache.width = width;
  cache.height = height;
  cache.opacity = normalized_opacity;
  cache.base_color = base_color;
  return cache.bitmap;
}

void DesktopWidgetWindow::ClearWallpaperCache() {
  // Precondition: caller must hold gdiplus_mutex_.
  ClearRenderedWallpaperCache();
  delete cached_wallpaper_image_;
  cached_wallpaper_image_ = nullptr;
  cached_wallpaper_path_.clear();
}

void DesktopWidgetWindow::ClearRenderedWallpaperCache() {
  // Precondition: caller must hold gdiplus_mutex_.
  for (auto& cache : cached_wallpaper_renders_) {
    delete cache.bitmap;
    cache.bitmap = nullptr;
    cache.path.clear();
    cache.width = 0;
    cache.height = 0;
    cache.opacity = -1.0;
    cache.base_color = RGB(0, 0, 0);
  }
}

void DesktopWidgetWindow::RegisterChannelHandler() {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger_, "spring_note/desktop_widget_window",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "hide") {
          Hide();
          result->Success();
          return;
        }

        if (call.method_name() == "showOrUpdate") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(
              call.arguments());
          if (!arguments) {
            result->Error("bad_args", "showOrUpdate expects a map");
            return;
          }
          ShowOrUpdate(*arguments);
          result->Success();
          return;
        }

        result->NotImplemented();
      });
}

void DesktopWidgetWindow::ShowOrUpdate(const flutter::EncodableMap& arguments) {
  const bool was_visible = window_ && IsWindowVisible(window_) != FALSE;
  const bool was_orb_mode = state_.orb_mode;
  state_.running = ReadBool(arguments, "running", state_.running);
  state_.work_seconds = ReadInt(arguments, "workSeconds", state_.work_seconds);
  state_.coins = ReadDouble(arguments, "coins", state_.coins);
  state_.coin_rate_per_second =
      ReadDouble(arguments, "coinRatePerSecond", state_.coin_rate_per_second);
  state_.level = std::max(1, ReadInt(arguments, "level", state_.level));
  state_.experience_percent =
      std::clamp(ReadInt(arguments, "experiencePercent",
                         state_.experience_percent),
                 0, 99);
  state_.progress = std::clamp(ReadDouble(arguments, "progress", state_.progress),
                               0.0, 1.0);
  state_.font_family =
      ResolveFontFamily(ReadString(arguments, "appFont", "system"));
  state_.font_scale_factor =
      std::clamp(ReadDouble(arguments, "fontScaleFactor",
                            state_.font_scale_factor),
                 0.8, 1.4);
  state_.orb_mode = ReadBool(arguments, "orbMode", state_.orb_mode);
  state_.wallpaper_mode =
      std::clamp(ReadInt(arguments, "widgetWallpaperMode", state_.wallpaper_mode),
                 0, 2);
  const int64_t wp_color = ReadInt64(arguments, "widgetWallpaperColor", -1);
  if (wp_color >= 0) {
    state_.wallpaper_color =
        RGB((wp_color >> 16) & 0xFF, (wp_color >> 8) & 0xFF, wp_color & 0xFF);
  }
  state_.wallpaper_image_path =
      Utf8ToWide(ReadString(arguments, "widgetWallpaperImagePath", ""));
  state_.wallpaper_opacity =
      std::clamp(ReadDouble(arguments, "widgetWallpaperOpacity",
                            state_.wallpaper_opacity),
                 0.0, 1.0);
  state_.dark_mode = ReadBool(arguments, "darkMode", state_.dark_mode);
  if (!state_.orb_mode) {
    expanded_ = true;
  } else if (!was_orb_mode || window_ == nullptr) {
    expanded_ = false;
  }

  // Position priority: 1) Dart arguments  2) Registry  3) Default.
  // Only call UpdateSavedPosition when Dart explicitly passes a position;
  // otherwise try the registry so stale in-memory state doesn't block
  // cross-session persistence.
  const auto* dart_position = ReadMap(arguments, "position");
  if (dart_position) {
    UpdateSavedPosition(arguments);
  } else if (!saved_position_.has_value()) {
    saved_position_ = LoadPositionFromRegistry();
  }

  if (!EnsureWindow()) {
    return;
  }
  ApplyWindowShapeAndSize(positioned_);
  if (!positioned_) {
    MoveToSavedOrDefaultPosition();
    positioned_ = true;
  } else {
    ClampWindowToVisibleMonitor(false);
  }
  if (!was_visible) {
    ShowWindow(window_, SW_SHOWNOACTIVATE);
    SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }
  RedrawWindow(window_, nullptr, nullptr,
               RDW_INVALIDATE | RDW_UPDATENOW | RDW_NOERASE);
}

void DesktopWidgetWindow::Hide() {
  if (window_) {
    DestroyWindow(window_);
    window_ = nullptr;
    positioned_ = false;
    region_width_ = -1;
    region_height_ = -1;
    region_radius_ = -1;
  }
}

bool DesktopWidgetWindow::EnsureWindow() {
  if (window_) {
    return true;
  }

  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kWidgetWindowClassName;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.hbrBackground = nullptr;
  window_class.lpfnWndProc = DesktopWidgetWindow::WindowProc;
  RegisterClass(&window_class);

  window_ = CreateWindowEx(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kWidgetWindowClassName, L"SpringNote Widget", WS_POPUP, CW_USEDEFAULT,
      CW_USEDEFAULT, CurrentWidth(), CurrentHeight(), nullptr, nullptr,
      GetModuleHandle(nullptr), this);
  if (!window_) {
    return false;
  }

  ApplyWindowShapeAndSize(false);
  return true;
}

void DesktopWidgetWindow::MoveToDefaultPosition() {
  RECT work_area{};
  SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);
  const int width = CurrentWidth();
  const int height = CurrentHeight();
  const int x = work_area.right - width - 28;
  const int y = work_area.bottom - height - 28;
  SetWindowPos(window_, HWND_TOPMOST, x, y, width, height,
               SWP_NOACTIVATE);
}

void DesktopWidgetWindow::MoveToSavedOrDefaultPosition() {
  if (saved_position_.has_value()) {
    const HMONITOR monitor = MonitorForPosition(saved_position_.value());
    const RECT next =
        ClampedRectForOrigin(saved_position_->x, saved_position_->y, monitor);
    SetWindowPos(window_, HWND_TOPMOST, next.left, next.top, CurrentWidth(),
                 CurrentHeight(), SWP_NOACTIVATE);
    NotifyPositionChanged();
    SavePositionToRegistry();
    return;
  }

  MoveToDefaultPosition();
  ClampWindowToVisibleMonitor(true);
}

int DesktopWidgetWindow::CurrentWidth() const {
  return state_.orb_mode && !expanded_ ? kOrbWindowSize
                                       : kExpandedWindowWidth;
}

int DesktopWidgetWindow::CurrentHeight() const {
  return state_.orb_mode && !expanded_ ? kOrbWindowSize
                                       : kExpandedWindowHeight;
}

int DesktopWidgetWindow::CurrentCornerRadius() const {
  return state_.orb_mode && !expanded_ ? kOrbWindowSize
                                       : kExpandedCornerRadius;
}

void DesktopWidgetWindow::ApplyWindowShapeAndSize(bool preserve_bottom_right) {
  if (!window_) {
    return;
  }

  const int width = CurrentWidth();
  const int height = CurrentHeight();
  RECT rect{};
  GetWindowRect(window_, &rect);
  const int old_width = rect.right - rect.left;
  const int old_height = rect.bottom - rect.top;
  int x = rect.left;
  int y = rect.top;
  if (preserve_bottom_right) {
    x = rect.right - width;
    y = rect.bottom - height;
  }
  const RECT next = ClampedRectForOrigin(
      x, y, MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST));
  const bool changed = next.left != rect.left || next.top != rect.top ||
                       width != old_width || height != old_height;
  if (changed) {
    SetWindowPos(window_, HWND_TOPMOST, next.left, next.top, width, height,
                 SWP_NOACTIVATE | SWP_NOCOPYBITS | SWP_DEFERERASE);
  }
  const bool region_changed = UpdateWindowRegion(width, height, false);
  if (changed || region_changed) {
    RedrawWindow(window_, nullptr, nullptr,
                 RDW_INVALIDATE | RDW_FRAME | RDW_UPDATENOW);
  }
}

bool DesktopWidgetWindow::UpdateWindowRegion(int width,
                                             int height,
                                             bool redraw) {
  if (!window_) {
    return false;
  }
  const int radius = CurrentCornerRadius();
  if (region_width_ == width && region_height_ == height &&
      region_radius_ == radius) {
    return false;
  }
  HRGN region =
      CreateRoundRectRgn(0, 0, width + 1, height + 1, radius * 2, radius * 2);
  SetWindowRgn(window_, nullptr, FALSE);
  if (SetWindowRgn(window_, region, redraw ? TRUE : FALSE) == 0) {
    DeleteObject(region);
    region_width_ = -1;
    region_height_ = -1;
    region_radius_ = -1;
    OutputDebugStringW(
        L"SpringNote: failed to update desktop widget window region.\n");
    return false;
  }
  region_width_ = width;
  region_height_ = height;
  region_radius_ = radius;
  return true;
}

void DesktopWidgetWindow::SetExpanded(bool expanded) {
  if (!state_.orb_mode || expanded_ == expanded) {
    return;
  }
  expanded_ = expanded;
  region_width_ = -1;
  region_height_ = -1;
  region_radius_ = -1;
  ApplyWindowShapeAndSize(true);
}

void DesktopWidgetWindow::TrackMouseLeave() {
  if (!window_) {
    return;
  }
  if (tracking_mouse_leave_) {
    return;
  }
  TRACKMOUSEEVENT event{};
  event.cbSize = sizeof(TRACKMOUSEEVENT);
  event.dwFlags = TME_QUERY;
  event.hwndTrack = window_;
  if (TrackMouseEvent(&event) != 0 && (event.dwFlags & TME_LEAVE) != 0) {
    tracking_mouse_leave_ = true;
    return;
  }

  event = {};
  event.cbSize = sizeof(TRACKMOUSEEVENT);
  event.dwFlags = TME_LEAVE;
  event.hwndTrack = window_;
  tracking_mouse_leave_ = TrackMouseEvent(&event) != 0;
}

RECT DesktopWidgetWindow::WorkAreaForMonitor(HMONITOR monitor) const {
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (monitor && GetMonitorInfo(monitor, &monitor_info)) {
    return monitor_info.rcWork;
  }

  RECT work_area{};
  SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);
  return work_area;
}

HMONITOR DesktopWidgetWindow::MonitorForPosition(
    const WidgetPosition& position) const {
  if (!position.screen_id.empty()) {
    MonitorSearchContext context{&position.screen_id, nullptr};

    EnumDisplayMonitors(nullptr, nullptr, FindMonitorById,
                        reinterpret_cast<LPARAM>(&context));
    if (context.monitor) {
      return context.monitor;
    }
  }

  const POINT point{position.x + CurrentWidth() / 2,
                    position.y + CurrentHeight() / 2};
  return MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST);
}

BOOL CALLBACK DesktopWidgetWindow::FindMonitorById(HMONITOR monitor,
                                                   HDC,
                                                   LPRECT,
                                                   LPARAM data) {
  auto* context = reinterpret_cast<MonitorSearchContext*>(data);
  MONITORINFOEX monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFOEX);
  if (GetMonitorInfo(monitor, &monitor_info) &&
      WideToUtf8(monitor_info.szDevice) == *context->target_id) {
    context->monitor = monitor;
    return FALSE;
  }
  return TRUE;
}

RECT DesktopWidgetWindow::ClampedRectForOrigin(
    int x,
    int y,
    HMONITOR preferred_monitor) const {
  const RECT work_area = WorkAreaForMonitor(preferred_monitor);
  const int width = CurrentWidth();
  const int height = CurrentHeight();
  const int min_x = static_cast<int>(work_area.left);
  const int max_x =
      std::max(min_x, static_cast<int>(work_area.right) - width);
  const int min_y = static_cast<int>(work_area.top);
  const int max_y =
      std::max(min_y, static_cast<int>(work_area.bottom) - height);
  const int left = std::clamp(x, min_x, max_x);
  const int top = std::clamp(y, min_y, max_y);
  return RECT{
      left,
      top,
      left + width,
      top + height,
  };
}

void DesktopWidgetWindow::SetBoundedWindowOrigin(int x, int y) {
  const RECT proposed{x, y, x + CurrentWidth(), y + CurrentHeight()};
  const HMONITOR monitor = MonitorFromRect(&proposed, MONITOR_DEFAULTTONEAREST);
  const RECT next = ClampedRectForOrigin(x, y, monitor);
  SetWindowPos(window_, HWND_TOPMOST, next.left, next.top, 0, 0,
               SWP_NOSIZE | SWP_NOACTIVATE);
}

void DesktopWidgetWindow::ClampWindowToVisibleMonitor(bool notify) {
  if (!window_) {
    return;
  }

  RECT rect{};
  GetWindowRect(window_, &rect);
  const HMONITOR monitor = MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST);
  const RECT next = ClampedRectForOrigin(rect.left, rect.top, monitor);
  if (next.left != rect.left || next.top != rect.top) {
    SetWindowPos(window_, HWND_TOPMOST, next.left, next.top, 0, 0,
                 SWP_NOSIZE | SWP_NOACTIVATE);
  }
  if (notify) {
    NotifyPositionChanged();
    SavePositionToRegistry();
  }
}

void DesktopWidgetWindow::Paint() {
  // Derive a single dark/light palette so every render below stays in sync
  // with the in-app theme (mirrors macOS DesktopWidgetColors.palette).
  const bool dark = state_.dark_mode;
  const COLORREF c_text     = dark ? RGB(242, 242, 242) : RGB(23, 23, 23);
  const COLORREF c_text_sub = dark ? RGB(154, 154, 154) : RGB(102, 102, 102);
  const COLORREF c_track    = dark ? RGB(51, 51, 51)    : RGB(237, 237, 237);
  const COLORREF c_progress = dark ? RGB(120, 120, 120) : RGB(207, 207, 207);
  const COLORREF c_border   = dark ? RGB(64, 64, 64)    : RGB(229, 229, 229);
  const COLORREF c_orb_bg   = dark ? RGB(27, 27, 27)    : RGB(255, 255, 255);
  const COLORREF c_stopped  = dark ? RGB(120, 120, 120) : RGB(207, 207, 207);
  // Green accent stays the same in both themes for brand consistency.
  const COLORREF c_running  = RGB(16, 185, 129);
  const bool collapsed_orb = state_.orb_mode && !expanded_;
  const COLORREF c_wallpaper_base = collapsed_orb ? c_orb_bg
                                                  : RGB(255, 255, 255);

  PAINTSTRUCT paint{};
  HDC dc = BeginPaint(window_, &paint);

  RECT client{};
  GetClientRect(window_, &client);
  HDC memory_dc = CreateCompatibleDC(dc);
  HBITMAP bitmap = CreateCompatibleBitmap(dc, client.right, client.bottom);
  HBITMAP old_bitmap = static_cast<HBITMAP>(SelectObject(memory_dc, bitmap));

  // Wallpaper background rendering directly on memory_dc. Hold the GDI+
  // mutex for the whole GDI+ block so a concurrent ShutdownGdiplus() (e.g.
  // from the destructor) cannot yank the GDI+ runtime or the cached image
  // out from under us mid-draw. GDI-only operations below (text, brushes,
  // pens) don't need the lock and run outside the critical section to keep
  // contention minimal.
  {
    std::lock_guard<std::mutex> gdi_lock(gdiplus_mutex_);
    if (gdiplus_initialized_) {
      Gdiplus::Graphics* graphics = Gdiplus::Graphics::FromHDC(memory_dc);
      graphics->SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
      const int bmp_w = std::max(static_cast<int>(client.right), 1);
      const int bmp_h = std::max(static_cast<int>(client.bottom), 1);
      const auto fill_base = [&]() {
        Gdiplus::Color base(255, GetRValue(c_wallpaper_base),
                            GetGValue(c_wallpaper_base),
                            GetBValue(c_wallpaper_base));
        Gdiplus::SolidBrush brush(base);
        graphics->FillRectangle(&brush, 0, 0, bmp_w, bmp_h);
      };

      if (state_.wallpaper_mode == 1) {
        fill_base();
        const BYTE alpha = static_cast<BYTE>(
            std::round(std::clamp(state_.wallpaper_opacity, 0.0, 1.0) * 255.0));
        Gdiplus::Color c(alpha, GetRValue(state_.wallpaper_color),
                         GetGValue(state_.wallpaper_color),
                         GetBValue(state_.wallpaper_color));
        Gdiplus::SolidBrush brush(c);
        graphics->FillRectangle(&brush, 0, 0, bmp_w, bmp_h);
      } else if (state_.wallpaper_mode == 2 &&
                 !state_.wallpaper_image_path.empty()) {
        // Use the cached image instead of reloading from disk on every
        // WM_PAINT. The rendered cache is keyed by imported path, target size,
        // opacity and base color, so orb/card transitions draw a tiny bitmap
        // instead of rescaling the original image on the UI thread.
        Gdiplus::Bitmap* wallpaper = GetOrRenderWallpaperBitmap(
            state_.wallpaper_image_path, bmp_w, bmp_h,
            state_.wallpaper_opacity, c_wallpaper_base);
        if (wallpaper != nullptr) {
          graphics->DrawImage(wallpaper, 0, 0, bmp_w, bmp_h);
        } else {
          fill_base();
        }
      } else {
        fill_base();
      }
      delete graphics;
    } else {
      HBRUSH fallback_brush = CreateSolidBrush(c_wallpaper_base);
      FillRect(memory_dc, &client, fallback_brush);
      DeleteObject(fallback_brush);
    }
  }

  const auto font_size = [this](int size) {
    return std::max(
        1, static_cast<int>(std::round(size * state_.font_scale_factor)));
  };

  if (collapsed_orb) {
    HBRUSH dot_brush = CreateSolidBrush(
        state_.running ? c_running : c_stopped);
    HBRUSH old_dot_brush =
        static_cast<HBRUSH>(SelectObject(memory_dc, dot_brush));
    HPEN dot_pen = CreatePen(
        PS_SOLID, 1, state_.running ? c_running : c_stopped);
    HPEN old_dot_pen = static_cast<HPEN>(SelectObject(memory_dc, dot_pen));
    Ellipse(memory_dc, 46, 12, 54, 20);
    SelectObject(memory_dc, old_dot_pen);
    SelectObject(memory_dc, old_dot_brush);
    DeleteObject(dot_pen);
    DeleteObject(dot_brush);

    std::wstringstream coins_stream;
    coins_stream << std::fixed << std::setprecision(state_.coins >= 100 ? 0 : 1)
                 << state_.coins;
    RECT coins_rect{7, 20, kOrbWindowSize - 7, 43};
    DrawTextLine(memory_dc, coins_stream.str(), coins_rect, font_size(17),
                 FW_SEMIBOLD, state_.font_family, c_text,
                 DT_CENTER | DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS);

    RECT unit_rect{8, 43, kOrbWindowSize - 8, 56};
    DrawTextLine(memory_dc, L"coin", unit_rect, font_size(10), FW_SEMIBOLD,
                 state_.font_family, c_text_sub,
                 DT_CENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

    HPEN border_pen = CreatePen(PS_SOLID, 1, c_border);
    HBRUSH hollow = static_cast<HBRUSH>(GetStockObject(HOLLOW_BRUSH));
    HPEN old_border_pen =
        static_cast<HPEN>(SelectObject(memory_dc, border_pen));
    HBRUSH old_hollow = static_cast<HBRUSH>(SelectObject(memory_dc, hollow));
    Ellipse(memory_dc, 0, 0, kOrbWindowSize, kOrbWindowSize);
    SelectObject(memory_dc, old_hollow);
    SelectObject(memory_dc, old_border_pen);
    DeleteObject(border_pen);

    BitBlt(dc, 0, 0, client.right, client.bottom, memory_dc, 0, 0, SRCCOPY);
    SelectObject(memory_dc, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(memory_dc);
    EndPaint(window_, &paint);
    return;
  }

  // Card background already filled by wallpaper rendering above

  RECT header_rect{16, 14, kExpandedWindowWidth - 16, 32};
  std::wstringstream header_stream;
  header_stream << L"Lv." << state_.level << L" \u5b9e\u4e60\u751f ("
                << state_.experience_percent << L"%)";
  DrawTextLine(memory_dc, header_stream.str(), header_rect, font_size(14),
               FW_SEMIBOLD, state_.font_family, c_text_sub,
               DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS);

  RECT track{16, 39, kExpandedWindowWidth - 16, 41};
  FillRoundRect(memory_dc, track, 2, c_track);
  RECT progress = track;
  progress.right =
      progress.left + static_cast<LONG>((track.right - track.left) *
                                        std::clamp(state_.progress, 0.0, 1.0));
  if (progress.right > progress.left) {
    FillRoundRect(memory_dc, progress, 2, c_progress);
  }

  std::wstringstream coins_stream;
  coins_stream << std::fixed << std::setprecision(2) << state_.coins;
  RECT coins_rect{16, 54, kExpandedWindowWidth - 16, 98};
  DrawTextLine(memory_dc, coins_stream.str(), coins_rect, font_size(38),
               FW_MEDIUM, state_.font_family, c_text,
               DT_LEFT | DT_SINGLELINE | DT_VCENTER);

  std::wstringstream rate_stream;
  rate_stream << L"+" << std::fixed << std::setprecision(3)
              << (state_.running ? state_.coin_rate_per_second : 0.0)
              << L" coin/s";
  RECT rate_rect{16, 112, 140, 130};
  DrawTextLine(memory_dc, rate_stream.str(), rate_rect, font_size(14), FW_BOLD,
               state_.font_family, c_running,
               DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS);

  HBRUSH dot_brush =
      CreateSolidBrush(state_.running ? c_running : c_stopped);
  HBRUSH old_dot_brush = static_cast<HBRUSH>(SelectObject(memory_dc, dot_brush));
  HPEN dot_pen = CreatePen(
      PS_SOLID, 1, state_.running ? c_running : c_stopped);
  HPEN old_dot_pen = static_cast<HPEN>(SelectObject(memory_dc, dot_pen));
  Ellipse(memory_dc, kExpandedWindowWidth - 96, 118,
          kExpandedWindowWidth - 90, 124);
  SelectObject(memory_dc, old_dot_pen);
  SelectObject(memory_dc, old_dot_brush);
  DeleteObject(dot_pen);
  DeleteObject(dot_brush);

  RECT time_rect{kExpandedWindowWidth - 84, 111, kExpandedWindowWidth - 16,
                 130};
  DrawTextLine(memory_dc, FormatDuration(), time_rect, font_size(13),
               FW_NORMAL, state_.font_family, c_text_sub,
               DT_RIGHT | DT_SINGLELINE);

  HPEN border_pen = CreatePen(PS_SOLID, 1, c_border);
  HBRUSH hollow = static_cast<HBRUSH>(GetStockObject(HOLLOW_BRUSH));
  HPEN old_border_pen = static_cast<HPEN>(SelectObject(memory_dc, border_pen));
  HBRUSH old_hollow = static_cast<HBRUSH>(SelectObject(memory_dc, hollow));
  RoundRect(memory_dc, 0, 0, kExpandedWindowWidth, kExpandedWindowHeight,
            kExpandedCornerRadius * 2, kExpandedCornerRadius * 2);
  SelectObject(memory_dc, old_hollow);
  SelectObject(memory_dc, old_border_pen);
  DeleteObject(border_pen);

  BitBlt(dc, 0, 0, client.right, client.bottom, memory_dc, 0, 0, SRCCOPY);
  SelectObject(memory_dc, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory_dc);
  EndPaint(window_, &paint);
}

void DesktopWidgetWindow::InvokeFlutterMethod(const std::string& method) {
  if (!channel_) {
    return;
  }
  channel_->InvokeMethod(method, std::make_unique<flutter::EncodableValue>());
}

DesktopWidgetWindow::WidgetPosition
DesktopWidgetWindow::CaptureCurrentPosition() const {
  WidgetPosition pos;
  if (!window_) {
    return pos;
  }

  RECT rect{};
  GetWindowRect(window_, &rect);
  pos.x = rect.left;
  pos.y = rect.top;

  const HMONITOR monitor = MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST);
  MONITORINFOEX monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFOEX);
  if (monitor && GetMonitorInfo(monitor, &monitor_info)) {
    pos.screen_id = WideToUtf8(monitor_info.szDevice);
  }

  return pos;
}

void DesktopWidgetWindow::NotifyPositionChanged() {
  if (!channel_ || !window_) {
    return;
  }

  const WidgetPosition pos = CaptureCurrentPosition();

  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("screenId")] =
      flutter::EncodableValue(pos.screen_id);
  arguments[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<double>(pos.x));
  arguments[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<double>(pos.y));
  channel_->InvokeMethod(
      "positionChanged",
      std::make_unique<flutter::EncodableValue>(std::move(arguments)));
}

void DesktopWidgetWindow::UpdateSavedPosition(
    const flutter::EncodableMap& arguments) {
  const auto* position = ReadMap(arguments, "position");
  if (!position) {
    return;
  }

  const double x = ReadDouble(
      *position, "x", std::numeric_limits<double>::quiet_NaN());
  const double y = ReadDouble(
      *position, "y", std::numeric_limits<double>::quiet_NaN());
  if (!std::isfinite(x) || !std::isfinite(y)) {
    return;
  }

  saved_position_ = WidgetPosition{
      ReadString(*position, "screenId"),
      static_cast<int>(std::round(x)),
      static_cast<int>(std::round(y)),
  };
}

void DesktopWidgetWindow::SavePositionToRegistry() {
  if (!window_) {
    return;
  }

  const WidgetPosition pos = CaptureCurrentPosition();

  RegKey key;
  const LSTATUS status = key.Create(HKEY_CURRENT_USER, kRegistryPath,
                                    KEY_SET_VALUE);
  if (status != ERROR_SUCCESS || !key.valid()) {
    LogRegistryError(L"create", status);
    return;
  }

  const std::wstring wide_screen_id = Utf8ToWide(pos.screen_id);
  const LSTATUS screen_status =
      RegSetValueExW(key.get(), kRegistryScreenId, 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(wide_screen_id.c_str()),
                     static_cast<DWORD>((wide_screen_id.size() + 1) *
                                        sizeof(wchar_t)));
  if (screen_status != ERROR_SUCCESS) {
    LogRegistryError(L"write screen_id", screen_status);
    return;
  }

  // Store x and y as REG_SZ strings so negative coordinates survive.
  const auto write_int_str = [&](const wchar_t* name, int value,
                                 const wchar_t* label) -> bool {
    const std::wstring str = std::to_wstring(value);
    const LSTATUS value_status =
        RegSetValueExW(key.get(), name, 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(str.c_str()),
                       static_cast<DWORD>((str.size() + 1) * sizeof(wchar_t)));
    if (value_status != ERROR_SUCCESS) {
      LogRegistryError(label, value_status);
      return false;
    }
    return true;
  };
  if (!write_int_str(kRegistryX, pos.x, L"write x") ||
      !write_int_str(kRegistryY, pos.y, L"write y")) {
    return;
  }

  // Keep the in-memory saved position in sync so same-process hide/show
  // or subsequent showOrUpdate calls see the latest clamped position.
  saved_position_ = pos;
}

std::optional<DesktopWidgetWindow::WidgetPosition>
DesktopWidgetWindow::LoadPositionFromRegistry() {
  RegKey key;
  const LSTATUS status = key.Open(HKEY_CURRENT_USER, kRegistryPath, KEY_READ);
  if (status != ERROR_SUCCESS || !key.valid()) {
    if (status != ERROR_FILE_NOT_FOUND) {
      LogRegistryError(L"open", status);
    }
    return std::nullopt;
  }

  // Helper: read a REG_SZ value into a std::wstring. Returns false on failure.
  const auto read_string = [&](const wchar_t* name,
                               std::wstring& out) -> bool {
    // First query the type and size.
    DWORD type = 0;
    DWORD byte_size = 0;
    const LSTATUS query_status =
        RegQueryValueExW(key.get(), name, nullptr, &type, nullptr,
                         &byte_size);
    if (query_status != ERROR_SUCCESS) {
      if (query_status != ERROR_FILE_NOT_FOUND) {
        LogRegistryError(L"query value", query_status);
      }
      return false;
    }
    if (type != REG_SZ) {
      OutputDebugStringW(
          L"SpringNote: desktop widget registry value has unexpected type.\n");
      return false;
    }
    // Guard against empty or unreasonably large values (no valid position
    // string should exceed 256 bytes).
    if (byte_size == 0 || byte_size > 256) {
      OutputDebugStringW(
          L"SpringNote: desktop widget registry value has invalid size.\n");
      return false;
    }
    // byte_size includes the null terminator. Add one extra wchar so tampered
    // odd byte sizes still have room for a terminator without arithmetic wrap.
    const DWORD wchar_count = byte_size / sizeof(wchar_t) + 1;
    std::vector<wchar_t> buffer(wchar_count, L'\0');
    DWORD read_bytes = byte_size;
    const LSTATUS read_status =
        RegQueryValueExW(key.get(), name, nullptr, nullptr,
                         reinterpret_cast<BYTE*>(buffer.data()),
                         &read_bytes);
    if (read_status != ERROR_SUCCESS) {
      LogRegistryError(L"read value", read_status);
      return false;
    }
    // Ensure null-termination regardless of what the registry holds.
    buffer.back() = L'\0';
    out = buffer.data();
    return true;
  };

  // Helper: read a REG_SZ containing a decimal integer. Returns false on
  // failure or overflow.
  const auto read_int_from_str = [&](const wchar_t* name,
                                     int& out) -> bool {
    std::wstring str;
    if (!read_string(name, str)) {
      return false;
    }
    if (str.empty()) {
      return false;
    }
    wchar_t* end = nullptr;
    errno = 0;
    const long value = wcstol(str.c_str(), &end, 10);
    if (errno == ERANGE || end == str.c_str() || *end != L'\0') {
      return false;
    }
    if (value < std::numeric_limits<int>::min() ||
        value > std::numeric_limits<int>::max()) {
      return false;
    }
    out = static_cast<int>(value);
    return true;
  };

  WidgetPosition position;
  bool has_x = false;
  bool has_y = false;

  // screen_id is optional - we fall back to MonitorFromPoint if missing.
  {
    std::wstring str;
    if (read_string(kRegistryScreenId, str)) {
      position.screen_id = WideToUtf8(str.c_str());
      MonitorSearchContext context{&position.screen_id, nullptr};
      EnumDisplayMonitors(nullptr, nullptr, FindMonitorById,
                          reinterpret_cast<LPARAM>(&context));
      if (!context.monitor) {
        position.screen_id.clear();
      }
    }
  }

  has_x = read_int_from_str(kRegistryX, position.x);
  has_y = read_int_from_str(kRegistryY, position.y);

  // Both x and y are required; otherwise the saved position is incomplete.
  if (!has_x || !has_y) {
    return std::nullopt;
  }

  return position;
}

void DesktopWidgetWindow::OpenMainWindow() {
  if (!main_window_) {
    return;
  }
  ShowWindow(main_window_, SW_RESTORE);
  SetForegroundWindow(main_window_);
}

std::wstring DesktopWidgetWindow::FormatDuration() const {
  const int hours = state_.work_seconds / 3600;
  const int minutes = (state_.work_seconds % 3600) / 60;
  const int seconds = state_.work_seconds % 60;
  std::wstringstream stream;
  stream << std::setfill(L'0') << std::setw(2) << hours << L":"
         << std::setw(2) << minutes << L":" << std::setw(2) << seconds;
  return stream.str();
}

LRESULT CALLBACK DesktopWidgetWindow::WindowProc(HWND hwnd,
                                                 UINT message,
                                                 WPARAM wparam,
                                                 LPARAM lparam) {
  DesktopWidgetWindow* widget = nullptr;
  if (message == WM_NCCREATE) {
    const auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    widget =
        static_cast<DesktopWidgetWindow*>(create_struct->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(widget));
  } else {
    widget = reinterpret_cast<DesktopWidgetWindow*>(
        GetWindowLongPtr(hwnd, GWLP_USERDATA));
  }

  if (widget) {
    return widget->HandleMessage(hwnd, message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT DesktopWidgetWindow::HandleMessage(HWND hwnd,
                                           UINT message,
                                           WPARAM wparam,
                                           LPARAM lparam) {
  switch (message) {
    case WM_PAINT:
      Paint();
      return 0;
    case WM_LBUTTONDOWN: {
      dragging_ = true;
      moved_while_pressed_ = false;
      drag_start_screen_ = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ClientToScreen(hwnd, &drag_start_screen_);
      GetWindowRect(hwnd, &drag_start_rect_);
      SetCapture(hwnd);
      return 0;
    }
    case WM_MOUSEMOVE:
      if (state_.orb_mode) {
        POINT mouse_point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        if (expanded_ || PointInRoundRectRegion(mouse_point, CurrentWidth(),
                                                CurrentHeight(),
                                                CurrentCornerRadius())) {
          SetExpanded(true);
          TrackMouseLeave();
        }
      }
      if (dragging_) {
        if ((wparam & MK_LBUTTON) == 0) {
          if (GetCapture() == hwnd) {
            ReleaseCapture();
          }
          dragging_ = false;
          moved_while_pressed_ = false;
          return 0;
        }
        POINT current{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ClientToScreen(hwnd, &current);
        const int dx = current.x - drag_start_screen_.x;
        const int dy = current.y - drag_start_screen_.y;
        if (std::abs(dx) > 3 || std::abs(dy) > 3) {
          moved_while_pressed_ = true;
        }
        SetBoundedWindowOrigin(drag_start_rect_.left + dx,
                               drag_start_rect_.top + dy);
      }
      return 0;
    case WM_MOUSELEAVE: {
      tracking_mouse_leave_ = false;
      POINT cursor{};
      GetCursorPos(&cursor);
      POINT client_cursor = cursor;
      ScreenToClient(hwnd, &client_cursor);
      const bool cursor_in_region = PointInRoundRectRegion(
          client_cursor, CurrentWidth(), CurrentHeight(), CurrentCornerRadius());
      if (dragging_) {
        return 0;
      }
      if (state_.orb_mode) {
        if (cursor_in_region) {
          return 0;
        }
      }
      SetExpanded(false);
      return 0;
    }
    case WM_LBUTTONUP:
      if (dragging_) {
        const bool moved = moved_while_pressed_;
        if (GetCapture() == hwnd) {
          ReleaseCapture();
        }
        dragging_ = false;
        if (!moved) {
          InvokeFlutterMethod("toggle");
        } else {
          ClampWindowToVisibleMonitor(true);
        }
        POINT release_point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        if (state_.orb_mode) {
          if (PointInRoundRectRegion(release_point, CurrentWidth(),
                                     CurrentHeight(), CurrentCornerRadius())) {
            TrackMouseLeave();
          } else {
            SetExpanded(false);
          }
        }
      }
      return 0;
    case WM_CAPTURECHANGED:
      if (reinterpret_cast<HWND>(lparam) != hwnd) {
        dragging_ = false;
        moved_while_pressed_ = false;
      }
      return 0;
    case WM_CANCELMODE:
      if (GetCapture() == hwnd) {
        ReleaseCapture();
      }
      dragging_ = false;
      moved_while_pressed_ = false;
      return 0;
    case WM_RBUTTONUP:
      OpenMainWindow();
      InvokeFlutterMethod("openHome");
      return 0;
    case WM_DESTROY:
      if (hwnd == window_) {
        window_ = nullptr;
        tracking_mouse_leave_ = false;
        dragging_ = false;
        moved_while_pressed_ = false;
        region_width_ = -1;
        region_height_ = -1;
        region_radius_ = -1;
      }
      return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}
