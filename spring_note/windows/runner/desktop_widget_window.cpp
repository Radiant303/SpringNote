#include "desktop_widget_window.h"

#include <flutter/standard_method_codec.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <limits>
#include <sstream>
#include <string>

namespace {

constexpr wchar_t kWidgetWindowClassName[] = L"SPRING_NOTE_DESKTOP_WIDGET";
constexpr int kExpandedWindowWidth = 260;
constexpr int kExpandedWindowHeight = 140;
constexpr int kExpandedCornerRadius = 16;
constexpr int kOrbWindowSize = 64;

struct MonitorSearchContext {
  const std::string* target_id;
  HMONITOR monitor = nullptr;
};

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
}

DesktopWidgetWindow::~DesktopWidgetWindow() {
  Hide();
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
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
  if (!state_.orb_mode) {
    expanded_ = true;
  } else if (!was_orb_mode || window_ == nullptr) {
    expanded_ = false;
  }
  UpdateSavedPosition(arguments);

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
  ShowWindow(window_, SW_SHOWNOACTIVATE);
  SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  InvalidateRect(window_, nullptr, FALSE);
}

void DesktopWidgetWindow::Hide() {
  if (window_) {
    DestroyWindow(window_);
    window_ = nullptr;
    positioned_ = false;
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
  int x = rect.left;
  int y = rect.top;
  if (preserve_bottom_right) {
    x = rect.right - width;
    y = rect.bottom - height;
  }
  const RECT next =
      ClampedRectForOrigin(x, y, MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST));
  SetWindowPos(window_, HWND_TOPMOST, next.left, next.top, width, height,
               SWP_NOACTIVATE);
  const int radius = CurrentCornerRadius();
  HRGN region =
      CreateRoundRectRgn(0, 0, width + 1, height + 1, radius * 2, radius * 2);
  SetWindowRgn(window_, region, TRUE);
}

void DesktopWidgetWindow::SetExpanded(bool expanded) {
  if (!state_.orb_mode || expanded_ == expanded) {
    return;
  }
  expanded_ = expanded;
  ApplyWindowShapeAndSize(true);
  InvalidateRect(window_, nullptr, FALSE);
}

void DesktopWidgetWindow::TrackMouseLeave() {
  if (!window_) {
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
  }
}

void DesktopWidgetWindow::Paint() {
  PAINTSTRUCT paint{};
  HDC dc = BeginPaint(window_, &paint);

  RECT client{};
  GetClientRect(window_, &client);
  HDC memory_dc = CreateCompatibleDC(dc);
  HBITMAP bitmap = CreateCompatibleBitmap(dc, client.right, client.bottom);
  HBITMAP old_bitmap = static_cast<HBITMAP>(SelectObject(memory_dc, bitmap));

  FillRect(memory_dc, &client,
           static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));

  const auto font_size = [this](int size) {
    return std::max(
        1, static_cast<int>(std::round(size * state_.font_scale_factor)));
  };

  if (state_.orb_mode && !expanded_) {
    RECT orb{0, 0, kOrbWindowSize, kOrbWindowSize};
    FillRoundRect(memory_dc, orb, kOrbWindowSize, RGB(255, 255, 255));

    HBRUSH dot_brush = CreateSolidBrush(
        state_.running ? RGB(16, 185, 129) : RGB(207, 207, 207));
    HBRUSH old_dot_brush =
        static_cast<HBRUSH>(SelectObject(memory_dc, dot_brush));
    HPEN dot_pen = CreatePen(
        PS_SOLID, 1, state_.running ? RGB(16, 185, 129) : RGB(207, 207, 207));
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
                 FW_SEMIBOLD, state_.font_family, RGB(23, 23, 23),
                 DT_CENTER | DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS);

    RECT unit_rect{8, 43, kOrbWindowSize - 8, 56};
    DrawTextLine(memory_dc, L"coin", unit_rect, font_size(10), FW_SEMIBOLD,
                 state_.font_family, RGB(102, 102, 102),
                 DT_CENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

    HPEN border_pen = CreatePen(PS_SOLID, 1, RGB(229, 229, 229));
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

  RECT card{0, 0, kExpandedWindowWidth, kExpandedWindowHeight};
  FillRoundRect(memory_dc, card, kExpandedCornerRadius * 2, RGB(255, 255, 255));

  RECT header_rect{16, 14, kExpandedWindowWidth - 16, 32};
  std::wstringstream header_stream;
  header_stream << L"Lv." << state_.level << L" \u5b9e\u4e60\u751f ("
                << state_.experience_percent << L"%)";
  DrawTextLine(memory_dc, header_stream.str(), header_rect, font_size(14),
               FW_SEMIBOLD, state_.font_family, RGB(102, 102, 102),
               DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS);

  RECT track{16, 39, kExpandedWindowWidth - 16, 41};
  FillRoundRect(memory_dc, track, 2, RGB(237, 237, 237));
  RECT progress = track;
  progress.right =
      progress.left + static_cast<LONG>((track.right - track.left) *
                                        std::clamp(state_.progress, 0.0, 1.0));
  if (progress.right > progress.left) {
    FillRoundRect(memory_dc, progress, 2, RGB(207, 207, 207));
  }

  std::wstringstream coins_stream;
  coins_stream << std::fixed << std::setprecision(2) << state_.coins;
  RECT coins_rect{16, 54, kExpandedWindowWidth - 16, 98};
  DrawTextLine(memory_dc, coins_stream.str(), coins_rect, font_size(38),
               FW_MEDIUM, state_.font_family, RGB(23, 23, 23),
               DT_LEFT | DT_SINGLELINE | DT_VCENTER);

  std::wstringstream rate_stream;
  rate_stream << L"+" << std::fixed << std::setprecision(3)
              << (state_.running ? state_.coin_rate_per_second : 0.0)
              << L" coin/s";
  RECT rate_rect{16, 112, 140, 130};
  DrawTextLine(memory_dc, rate_stream.str(), rate_rect, font_size(14), FW_BOLD,
               state_.font_family, RGB(16, 185, 129),
               DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS);

  HBRUSH dot_brush =
      CreateSolidBrush(state_.running ? RGB(16, 185, 129) : RGB(207, 207, 207));
  HBRUSH old_dot_brush = static_cast<HBRUSH>(SelectObject(memory_dc, dot_brush));
  HPEN dot_pen = CreatePen(
      PS_SOLID, 1, state_.running ? RGB(16, 185, 129) : RGB(207, 207, 207));
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
               FW_NORMAL, state_.font_family, RGB(102, 102, 102),
               DT_RIGHT | DT_SINGLELINE);

  HPEN border_pen = CreatePen(PS_SOLID, 1, RGB(229, 229, 229));
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

void DesktopWidgetWindow::NotifyPositionChanged() {
  if (!channel_ || !window_) {
    return;
  }

  RECT rect{};
  GetWindowRect(window_, &rect);
  const HMONITOR monitor = MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST);
  MONITORINFOEX monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFOEX);
  std::string screen_id;
  if (monitor && GetMonitorInfo(monitor, &monitor_info)) {
    screen_id = WideToUtf8(monitor_info.szDevice);
  }

  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("screenId")] =
      flutter::EncodableValue(screen_id);
  arguments[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<double>(rect.left));
  arguments[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<double>(rect.top));
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
    case WM_LBUTTONDOWN:
      dragging_ = true;
      moved_while_pressed_ = false;
      drag_start_screen_ = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ClientToScreen(hwnd, &drag_start_screen_);
      GetWindowRect(hwnd, &drag_start_rect_);
      SetCapture(hwnd);
      return 0;
    case WM_MOUSEMOVE:
      if (state_.orb_mode) {
        SetExpanded(true);
        TrackMouseLeave();
      }
      if (dragging_) {
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
    case WM_MOUSELEAVE:
      tracking_mouse_leave_ = false;
      if (dragging_) {
        return 0;
      }
      if (state_.orb_mode) {
        POINT cursor{};
        GetCursorPos(&cursor);
        RECT window_rect{};
        GetWindowRect(hwnd, &window_rect);
        if (PtInRect(&window_rect, cursor)) {
          TrackMouseLeave();
          return 0;
        }
      }
      SetExpanded(false);
      return 0;
    case WM_LBUTTONUP:
      if (dragging_) {
        ReleaseCapture();
        dragging_ = false;
        if (!moved_while_pressed_) {
          InvokeFlutterMethod("toggle");
        }
        ClampWindowToVisibleMonitor(true);
        RECT client{};
        GetClientRect(hwnd, &client);
        POINT release_point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        if (state_.orb_mode) {
          if (PtInRect(&client, release_point)) {
            TrackMouseLeave();
          } else {
            SetExpanded(false);
          }
        }
      }
      return 0;
    case WM_RBUTTONUP:
      OpenMainWindow();
      InvokeFlutterMethod("openHome");
      return 0;
    case WM_DESTROY:
      if (hwnd == window_) {
        window_ = nullptr;
        tracking_mouse_leave_ = false;
      }
      return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}
