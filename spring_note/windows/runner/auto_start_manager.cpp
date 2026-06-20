#include "auto_start_manager.h"

#include <string>

namespace {

constexpr wchar_t kRunKeyPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValueName[] = L"SpringNote";

std::wstring CurrentExecutablePath() {
  std::wstring buffer(MAX_PATH, L'\0');
  DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                    static_cast<DWORD>(buffer.size()));
  while (length == buffer.size()) {
    buffer.resize(buffer.size() * 2);
    length = GetModuleFileNameW(nullptr, buffer.data(),
                                static_cast<DWORD>(buffer.size()));
  }
  if (length == 0) {
    return L"";
  }
  buffer.resize(length);
  return buffer;
}

std::wstring QuoteCommand(const std::wstring& path) {
  return L"\"" + path + L"\"";
}

}  // namespace

AutoStartManager::AutoStartManager(flutter::BinaryMessenger* messenger)
    : messenger_(messenger) {
  if (messenger_) {
    RegisterChannelHandler();
  }
}

AutoStartManager::~AutoStartManager() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

void AutoStartManager::RegisterChannelHandler() {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger_, "spring_note/auto_start",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setEnabled") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          if (!enabled) {
            result->Error("bad_args", "setEnabled expects a bool");
            return;
          }
          result->Success(flutter::EncodableValue(SetEnabled(*enabled)));
          return;
        }

        result->NotImplemented();
      });
}

bool AutoStartManager::SetEnabled(bool enabled) {
  return enabled ? Enable() : Disable();
}

bool AutoStartManager::Enable() {
  const std::wstring executable_path = CurrentExecutablePath();
  if (executable_path.empty()) {
    return false;
  }

  HKEY key = nullptr;
  const LSTATUS open_status =
      RegCreateKeyExW(HKEY_CURRENT_USER, kRunKeyPath, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr);
  if (open_status != ERROR_SUCCESS) {
    return false;
  }

  const std::wstring command = QuoteCommand(executable_path);
  const LSTATUS write_status = RegSetValueExW(
      key, kRunValueName, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(command.c_str()),
      static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  return write_status == ERROR_SUCCESS;
}

bool AutoStartManager::Disable() {
  HKEY key = nullptr;
  const LSTATUS open_status =
      RegOpenKeyExW(HKEY_CURRENT_USER, kRunKeyPath, 0, KEY_SET_VALUE, &key);
  if (open_status == ERROR_FILE_NOT_FOUND) {
    return true;
  }
  if (open_status != ERROR_SUCCESS) {
    return false;
  }

  const LSTATUS delete_status = RegDeleteValueW(key, kRunValueName);
  RegCloseKey(key);
  return delete_status == ERROR_SUCCESS ||
         delete_status == ERROR_FILE_NOT_FOUND;
}
