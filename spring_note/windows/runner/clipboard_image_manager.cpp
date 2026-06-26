#include "clipboard_image_manager.h"

#include <windows.h>

#include <gdiplus.h>
#include <objidl.h>

#include <cstdint>
#include <memory>
#include <optional>
#include <vector>

namespace {

const CLSID kPngEncoderClsid = {
    0x557cf406,
    0x1a04,
    0x11d3,
    {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e},
};

class ClipboardGuard {
 public:
  ClipboardGuard() : opened_(OpenClipboard(nullptr) != FALSE) {}
  ~ClipboardGuard() {
    if (opened_) {
      CloseClipboard();
    }
  }

  bool opened() const { return opened_; }

 private:
  bool opened_ = false;
};

class GdiplusSession {
 public:
  GdiplusSession() {
    Gdiplus::GdiplusStartupInput input;
    status_ = Gdiplus::GdiplusStartup(&token_, &input, nullptr);
  }

  ~GdiplusSession() {
    if (status_ == Gdiplus::Ok) {
      Gdiplus::GdiplusShutdown(token_);
    }
  }

  bool ok() const { return status_ == Gdiplus::Ok; }

 private:
  ULONG_PTR token_ = 0;
  Gdiplus::Status status_ = Gdiplus::GenericError;
};

struct StreamReleaser {
  void operator()(IStream* stream) const {
    if (stream) {
      stream->Release();
    }
  }
};

using ScopedStream = std::unique_ptr<IStream, StreamReleaser>;

struct BitmapReleaser {
  void operator()(void* bitmap) const {
    if (bitmap) {
      DeleteObject(static_cast<HGDIOBJ>(bitmap));
    }
  }
};

using ScopedBitmap = std::unique_ptr<void, BitmapReleaser>;

class ScopedGlobalLock {
 public:
  explicit ScopedGlobalLock(HGLOBAL global)
      : global_(global), data_(GlobalLock(global)) {}
  ~ScopedGlobalLock() {
    if (data_) {
      GlobalUnlock(global_);
    }
  }

  const void* data() const { return data_; }

 private:
  HGLOBAL global_ = nullptr;
  const void* data_ = nullptr;
};

bool IsGdiplusReady() {
  static GdiplusSession session;
  return session.ok();
}

std::optional<std::vector<uint8_t>> EncodeBitmapAsPng(HBITMAP bitmap) {
  if (!bitmap) {
    return std::nullopt;
  }
  if (!IsGdiplusReady()) {
    return std::nullopt;
  }

  Gdiplus::Bitmap image(bitmap, nullptr);
  if (image.GetLastStatus() != Gdiplus::Ok) {
    return std::nullopt;
  }

  IStream* raw_stream = nullptr;
  if (CreateStreamOnHGlobal(nullptr, TRUE, &raw_stream) != S_OK ||
      !raw_stream) {
    return std::nullopt;
  }
  ScopedStream stream(raw_stream);

  if (image.Save(stream.get(), &kPngEncoderClsid, nullptr) != Gdiplus::Ok) {
    return std::nullopt;
  }

  HGLOBAL global = nullptr;
  if (GetHGlobalFromStream(stream.get(), &global) != S_OK || !global) {
    return std::nullopt;
  }

  const SIZE_T size = GlobalSize(global);
  if (size == 0) {
    return std::nullopt;
  }

  ScopedGlobalLock lock(global);
  if (!lock.data()) {
    return std::nullopt;
  }
  const auto* bytes = static_cast<const uint8_t*>(lock.data());
  std::vector<uint8_t> png(bytes, bytes + size);
  return png;
}

size_t ColorTableEntryCount(const BITMAPINFOHEADER& header) {
  if (header.biClrUsed > 0) {
    return header.biClrUsed;
  }
  if (header.biBitCount <= 8) {
    return static_cast<size_t>(1) << header.biBitCount;
  }
  return 0;
}

size_t BitfieldMaskBytes(const BITMAPINFOHEADER& header) {
  // V4/V5 headers store bit masks in the extended header itself.
  if (header.biSize >= sizeof(BITMAPV5HEADER)) {
    return 0;
  }
  if (header.biSize > sizeof(BITMAPINFOHEADER)) {
    return 0;
  }
  if (header.biCompression == BI_BITFIELDS) {
    return 3 * sizeof(DWORD);
  }
#ifdef BI_ALPHABITFIELDS
  if (header.biCompression == BI_ALPHABITFIELDS) {
    return 4 * sizeof(DWORD);
  }
#endif
  return 0;
}

std::optional<size_t> PixelDataOffset(const BITMAPINFOHEADER& header,
                                      SIZE_T global_size) {
  if (header.biSize < sizeof(BITMAPINFOHEADER) ||
      header.biSize > global_size) {
    return std::nullopt;
  }

  const size_t header_size = header.biSize;
  const size_t mask_bytes = BitfieldMaskBytes(header);
  if (mask_bytes > global_size - header_size) {
    return std::nullopt;
  }

  const size_t color_count = ColorTableEntryCount(header);
  const size_t remaining = global_size - header_size - mask_bytes;
  if (color_count > remaining / sizeof(RGBQUAD)) {
    return std::nullopt;
  }

  const size_t offset =
      header_size + mask_bytes + color_count * sizeof(RGBQUAD);
  if (offset >= global_size) {
    return std::nullopt;
  }
  return offset;
}

std::optional<std::vector<uint8_t>> EncodeDibClipboardFormat(UINT format) {
  HANDLE handle = GetClipboardData(format);
  if (!handle) {
    return std::nullopt;
  }

  const SIZE_T global_size = GlobalSize(handle);
  if (global_size < sizeof(BITMAPINFOHEADER)) {
    return std::nullopt;
  }

  ScopedGlobalLock lock(static_cast<HGLOBAL>(handle));
  if (!lock.data()) {
    return std::nullopt;
  }

  const auto* header = static_cast<const BITMAPINFOHEADER*>(lock.data());
  std::optional<std::vector<uint8_t>> png;
  const auto pixel_offset = PixelDataOffset(*header, global_size);
  if (pixel_offset && header->biPlanes == 1 && header->biWidth != 0 &&
      header->biHeight != 0 && header->biCompression != BI_JPEG &&
      header->biCompression != BI_PNG) {
    HDC screen = GetDC(nullptr);
    if (screen) {
      const auto* pixels =
          static_cast<const uint8_t*>(lock.data()) + *pixel_offset;
      HBITMAP bitmap = CreateDIBitmap(
          screen, header, CBM_INIT, pixels,
          reinterpret_cast<const BITMAPINFO*>(lock.data()), DIB_RGB_COLORS);
      ReleaseDC(nullptr, screen);
      ScopedBitmap scoped_bitmap(bitmap);
      png = EncodeBitmapAsPng(static_cast<HBITMAP>(scoped_bitmap.get()));
    }
  }

  return png;
}

std::optional<std::vector<uint8_t>> ReadClipboardImageAsPng() {
  ClipboardGuard clipboard;
  if (!clipboard.opened()) {
    return std::nullopt;
  }

  if (IsClipboardFormatAvailable(CF_BITMAP)) {
    auto png = EncodeBitmapAsPng(
        static_cast<HBITMAP>(GetClipboardData(CF_BITMAP)));
    if (png) {
      return png;
    }
  }

  if (IsClipboardFormatAvailable(CF_DIBV5)) {
    auto png = EncodeDibClipboardFormat(CF_DIBV5);
    if (png) {
      return png;
    }
  }

  if (IsClipboardFormatAvailable(CF_DIB)) {
    auto png = EncodeDibClipboardFormat(CF_DIB);
    if (png) {
      return png;
    }
  }

  return std::nullopt;
}

}  // namespace

ClipboardImageManager::ClipboardImageManager(
    flutter::BinaryMessenger* messenger)
    : messenger_(messenger) {
  if (messenger_) {
    RegisterChannelHandler();
  }
}

ClipboardImageManager::~ClipboardImageManager() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

void ClipboardImageManager::RegisterChannelHandler() {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger_, "spring_note/clipboard_image",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "readPngImage") {
          auto png = ReadClipboardImageAsPng();
          if (!png) {
            result->Success();
            return;
          }
          result->Success(flutter::EncodableValue(std::move(*png)));
          return;
        }

        result->NotImplemented();
      });
}
