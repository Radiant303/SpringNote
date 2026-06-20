#ifndef RUNNER_AUTO_START_MANAGER_H_
#define RUNNER_AUTO_START_MANAGER_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

class AutoStartManager {
 public:
  explicit AutoStartManager(flutter::BinaryMessenger* messenger);
  ~AutoStartManager();

  AutoStartManager(const AutoStartManager&) = delete;
  AutoStartManager& operator=(const AutoStartManager&) = delete;

 private:
  void RegisterChannelHandler();
  bool SetEnabled(bool enabled);
  bool Enable();
  bool Disable();

  flutter::BinaryMessenger* messenger_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_AUTO_START_MANAGER_H_
