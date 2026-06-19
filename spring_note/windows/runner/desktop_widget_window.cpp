#include "desktop_widget_window.h"

#include <flutter/standard_method_codec.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <sstream>

namespace {

constexpr wchar_t kWidgetWindowClassName[] = L"SPRING_NOTE_DESKTOP_WIDGET";
constexpr int kWindowWidth = 260;
constexpr int kWindowHeight = 140;
constexpr int kCornerRadius = 16;

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
                  COLORREF color,
                  UINT format) {
  HFONT font = CreateFont(
      -font_size, 0, 0, 0, weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
      OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
      DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable");
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

  if (!EnsureWindow()) {
    return;
  }
  if (!positioned_) {
    MoveToDefaultPosition();
    positioned_ = true;
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
      CW_USEDEFAULT, kWindowWidth, kWindowHeight, nullptr, nullptr,
      GetModuleHandle(nullptr), this);
  if (!window_) {
    return false;
  }

  HRGN region =
      CreateRoundRectRgn(0, 0, kWindowWidth + 1, kWindowHeight + 1,
                         kCornerRadius * 2, kCornerRadius * 2);
  SetWindowRgn(window_, region, TRUE);
  return true;
}

void DesktopWidgetWindow::MoveToDefaultPosition() {
  RECT work_area{};
  SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);
  const int x = work_area.right - kWindowWidth - 28;
  const int y = work_area.bottom - kWindowHeight - 28;
  SetWindowPos(window_, HWND_TOPMOST, x, y, kWindowWidth, kWindowHeight,
               SWP_NOACTIVATE);
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

  RECT card{0, 0, kWindowWidth, kWindowHeight};
  FillRoundRect(memory_dc, card, kCornerRadius * 2, RGB(255, 255, 255));

  RECT header_rect{16, 14, kWindowWidth - 16, 32};
  std::wstringstream header_stream;
  header_stream << L"Lv." << state_.level << L" \u5b9e\u4e60\u751f \u00b7 "
                << (state_.running ? L"\u5de5\u4f5c\u4e2d"
                                   : L"\u5df2\u6682\u505c");
  DrawTextLine(memory_dc, header_stream.str(), header_rect, 14, FW_SEMIBOLD,
               RGB(100, 116, 139),
               DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS);

  std::wstringstream experience_stream;
  experience_stream << L"EXP " << state_.experience_percent << L"%";
  RECT experience_rect{180, 14, kWindowWidth - 16, 32};
  DrawTextLine(memory_dc, experience_stream.str(), experience_rect, 12,
               FW_SEMIBOLD, RGB(148, 163, 184), DT_RIGHT | DT_SINGLELINE);

  RECT track{16, 39, kWindowWidth - 16, 41};
  FillRoundRect(memory_dc, track, 2, RGB(241, 245, 249));
  RECT progress = track;
  progress.right =
      progress.left + static_cast<LONG>((track.right - track.left) *
                                        std::clamp(state_.progress, 0.0, 1.0));
  if (progress.right > progress.left) {
    FillRoundRect(memory_dc, progress, 2, RGB(203, 213, 225));
  }

  std::wstringstream coins_stream;
  coins_stream << std::fixed << std::setprecision(2) << state_.coins;
  RECT coins_rect{16, 54, kWindowWidth - 16, 98};
  DrawTextLine(memory_dc, coins_stream.str(), coins_rect, 38, FW_MEDIUM,
               RGB(15, 23, 42), DT_LEFT | DT_SINGLELINE | DT_VCENTER);

  std::wstringstream rate_stream;
  rate_stream << L"+" << std::fixed << std::setprecision(3)
              << (state_.running ? state_.coin_rate_per_second : 0.0) << L"/s";
  RECT rate_rect{16, 112, 122, 130};
  DrawTextLine(memory_dc, rate_stream.str(), rate_rect, 14, FW_BOLD,
               RGB(16, 185, 129), DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS);

  HBRUSH dot_brush =
      CreateSolidBrush(state_.running ? RGB(16, 185, 129) : RGB(203, 213, 225));
  HBRUSH old_dot_brush = static_cast<HBRUSH>(SelectObject(memory_dc, dot_brush));
  HPEN dot_pen = CreatePen(
      PS_SOLID, 1, state_.running ? RGB(16, 185, 129) : RGB(203, 213, 225));
  HPEN old_dot_pen = static_cast<HPEN>(SelectObject(memory_dc, dot_pen));
  Ellipse(memory_dc, kWindowWidth - 96, 118, kWindowWidth - 90, 124);
  SelectObject(memory_dc, old_dot_pen);
  SelectObject(memory_dc, old_dot_brush);
  DeleteObject(dot_pen);
  DeleteObject(dot_brush);

  RECT time_rect{kWindowWidth - 84, 111, kWindowWidth - 16, 130};
  DrawTextLine(memory_dc, FormatDuration(), time_rect, 13, FW_NORMAL,
               RGB(100, 116, 139), DT_RIGHT | DT_SINGLELINE);

  HPEN border_pen = CreatePen(PS_SOLID, 1, RGB(229, 231, 235));
  HBRUSH hollow = static_cast<HBRUSH>(GetStockObject(HOLLOW_BRUSH));
  HPEN old_border_pen = static_cast<HPEN>(SelectObject(memory_dc, border_pen));
  HBRUSH old_hollow = static_cast<HBRUSH>(SelectObject(memory_dc, hollow));
  RoundRect(memory_dc, 0, 0, kWindowWidth, kWindowHeight, kCornerRadius * 2,
            kCornerRadius * 2);
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
      if (dragging_) {
        POINT current{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ClientToScreen(hwnd, &current);
        const int dx = current.x - drag_start_screen_.x;
        const int dy = current.y - drag_start_screen_.y;
        if (std::abs(dx) > 3 || std::abs(dy) > 3) {
          moved_while_pressed_ = true;
        }
        SetWindowPos(hwnd, HWND_TOPMOST, drag_start_rect_.left + dx,
                     drag_start_rect_.top + dy, 0, 0,
                     SWP_NOSIZE | SWP_NOACTIVATE);
      }
      return 0;
    case WM_LBUTTONUP:
      if (dragging_) {
        ReleaseCapture();
        dragging_ = false;
        if (!moved_while_pressed_) {
          InvokeFlutterMethod("toggle");
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
      }
      return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}
