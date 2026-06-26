#ifndef RUNNER_CLIPBOARD_IMAGE_MANAGER_H_
#define RUNNER_CLIPBOARD_IMAGE_MANAGER_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

class ClipboardImageManager {
 public:
  explicit ClipboardImageManager(flutter::BinaryMessenger* messenger);
  ~ClipboardImageManager();

  ClipboardImageManager(const ClipboardImageManager&) = delete;
  ClipboardImageManager& operator=(const ClipboardImageManager&) = delete;

 private:
  void RegisterChannelHandler();

  flutter::BinaryMessenger* messenger_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_CLIPBOARD_IMAGE_MANAGER_H_
