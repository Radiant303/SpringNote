#include <windows.h>
#include <shellapi.h>

#include <cwchar>
#include <cstdlib>
#include <string>
#include <vector>

namespace {

constexpr DWORD kRestartRequiredExitCode = 3010;

struct Options {
  std::wstring installer;
  std::wstring app;
  std::wstring inno_log;
  std::wstring helper_log;
  DWORD wait_pid = 0;
};

size_t LastSeparator(const std::wstring& path) {
  return path.find_last_of(L"\\/");
}

std::wstring ParentPath(const std::wstring& path) {
  const size_t index = LastSeparator(path);
  if (index == std::wstring::npos) {
    return L"";
  }
  return path.substr(0, index);
}

std::wstring QuoteArgument(const std::wstring& value) {
  std::wstring result = L"\"";
  for (wchar_t ch : value) {
    if (ch == L'"') {
      result += L"\\\"";
    } else {
      result += ch;
    }
  }
  result += L"\"";
  return result;
}

std::wstring InstallerArguments(const std::wstring& log_path) {
  return L"/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG=" +
         QuoteArgument(log_path);
}

void WriteLog(const Options& options, const std::wstring& message) {
  if (options.helper_log.empty()) {
    return;
  }

  SYSTEMTIME time{};
  GetLocalTime(&time);

  const std::wstring log_directory = ParentPath(options.helper_log);
  if (!log_directory.empty()) {
    CreateDirectoryW(log_directory.c_str(), nullptr);
  }

  wchar_t timestamp[64]{};
  swprintf_s(timestamp, L"[%04u-%02u-%02u %02u:%02u:%02u.%03u] ",
             time.wYear, time.wMonth, time.wDay, time.wHour, time.wMinute,
             time.wSecond, time.wMilliseconds);
  const std::wstring line = std::wstring(timestamp) + message + L"\r\n";

  const int byte_count =
      WideCharToMultiByte(CP_UTF8, 0, line.c_str(), -1, nullptr, 0, nullptr,
                          nullptr);
  if (byte_count <= 1) {
    return;
  }

  std::vector<char> bytes(static_cast<size_t>(byte_count));
  WideCharToMultiByte(CP_UTF8, 0, line.c_str(), -1, bytes.data(), byte_count,
                      nullptr, nullptr);

  HANDLE file = CreateFileW(options.helper_log.c_str(), FILE_APPEND_DATA,
                            FILE_SHARE_READ, nullptr, OPEN_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }

  DWORD written = 0;
  WriteFile(file, bytes.data(), static_cast<DWORD>(byte_count - 1), &written,
            nullptr);
  CloseHandle(file);
}

std::wstring LastErrorText(DWORD error) {
  if (error == ERROR_SUCCESS) {
    return L"0";
  }

  wchar_t* buffer = nullptr;
  const DWORD length = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
          FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, error, 0, reinterpret_cast<wchar_t*>(&buffer), 0, nullptr);
  if (length == 0 || buffer == nullptr) {
    return std::to_wstring(error);
  }

  std::wstring message(buffer, length);
  LocalFree(buffer);
  return std::to_wstring(error) + L": " + message;
}

void WaitForOldProcess(const Options& options) {
  if (options.wait_pid == 0) {
    return;
  }

  WriteLog(options, L"waiting for old process " +
                        std::to_wstring(options.wait_pid));
  HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, options.wait_pid);
  if (!process) {
    WriteLog(options, L"old process is already gone");
    return;
  }

  DWORD wait_result = WaitForSingleObject(process, 30000);
  if (wait_result == WAIT_TIMEOUT) {
    WriteLog(options, L"old process is still running; installer will request "
                      L"application close");
  }
  CloseHandle(process);
}

DWORD RunInstaller(const Options& options) {
  const std::wstring arguments = InstallerArguments(options.inno_log);
  const std::wstring installer_directory = ParentPath(options.installer);
  WriteLog(options, L"starting installer: " + options.installer + L" " +
                        arguments);

  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOCLOSEPROCESS;
  info.lpVerb = L"open";
  info.lpFile = options.installer.c_str();
  info.lpParameters = arguments.c_str();
  info.lpDirectory = installer_directory.c_str();
  info.nShow = SW_SHOWNORMAL;

  if (!ShellExecuteExW(&info)) {
    const DWORD error = GetLastError();
    WriteLog(options, L"installer launch failed: " + LastErrorText(error));
    return error == ERROR_SUCCESS ? 1 : error;
  }

  WaitForSingleObject(info.hProcess, INFINITE);
  DWORD exit_code = 1;
  GetExitCodeProcess(info.hProcess, &exit_code);
  CloseHandle(info.hProcess);
  WriteLog(options, L"installer exited with code " +
                        std::to_wstring(exit_code));
  return exit_code;
}

bool StartApp(const Options& options) {
  const std::wstring working_directory = ParentPath(options.app);
  WriteLog(options, L"starting app: " + options.app);

  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.lpVerb = L"open";
  info.lpFile = options.app.c_str();
  info.lpDirectory = working_directory.c_str();
  info.nShow = SW_SHOWNORMAL;

  if (ShellExecuteExW(&info)) {
    WriteLog(options, L"app launch requested");
    return true;
  }

  WriteLog(options, L"app launch failed: " + LastErrorText(GetLastError()));
  return false;
}

Options ParseArguments(int argc, wchar_t* argv[]) {
  Options options;
  for (int index = 1; index + 1 < argc; index += 2) {
    const std::wstring key = argv[index];
    const std::wstring value = argv[index + 1];
    if (key == L"--installer") {
      options.installer = value;
    } else if (key == L"--app") {
      options.app = value;
    } else if (key == L"--inno-log") {
      options.inno_log = value;
    } else if (key == L"--helper-log") {
      options.helper_log = value;
    } else if (key == L"--wait-pid") {
      options.wait_pid =
          static_cast<DWORD>(std::wcstoul(value.c_str(), nullptr, 10));
    }
  }
  return options;
}

bool HasRequiredOptions(const Options& options) {
  return !options.installer.empty() && !options.app.empty() &&
         !options.inno_log.empty() && !options.helper_log.empty();
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE, HINSTANCE, wchar_t*, int) {
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) {
    return 2;
  }

  const Options options = ParseArguments(argc, argv);
  LocalFree(argv);

  if (!HasRequiredOptions(options)) {
    return 2;
  }

  WriteLog(options, L"helper started");
  WaitForOldProcess(options);
  const DWORD installer_exit_code = RunInstaller(options);
  if (installer_exit_code == kRestartRequiredExitCode) {
    WriteLog(options, L"installer requested a Windows restart");
    MessageBoxW(
        nullptr,
        L"SpringNote was updated, but Windows must be restarted before the "
        L"new version can start.",
        L"SpringNote Update", MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND);
    return 0;
  }
  if (installer_exit_code != 0) {
    WriteLog(options, L"helper exiting after installer failure");
    return static_cast<int>(installer_exit_code);
  }

  if (!StartApp(options)) {
    WriteLog(options, L"helper exiting after app launch failure");
    return 4;
  }

  WriteLog(options, L"helper finished");
  return 0;
}
