import '../../src/rust/api/note_image_cleanup_api.dart' as rust_api;
import '../../src/rust/note_image_cleanup.dart' as rust_model;
import '../models/local_data_state.dart';
import 'note_storage_coordinator.dart';

class NoteImageCleanupEntry {
  const NoteImageCleanupEntry({
    required this.relativePath,
    required this.sizeBytes,
  });

  final String relativePath;
  final int sizeBytes;

  factory NoteImageCleanupEntry.fromRust(
    rust_model.NoteImageCleanupEntry entry,
  ) {
    return NoteImageCleanupEntry(
      relativePath: entry.relativePath,
      sizeBytes: _platformInt64ToInt(entry.sizeBytes),
    );
  }
}

class NoteImageCleanupScan {
  const NoteImageCleanupScan({
    required this.totalImageCount,
    required this.referencedImageCount,
    required this.totalSizeBytes,
    required this.unusedImages,
  });

  final int totalImageCount;
  final int referencedImageCount;
  final int totalSizeBytes;
  final List<NoteImageCleanupEntry> unusedImages;

  int get unusedImageCount => unusedImages.length;

  int get unusedSizeBytes =>
      unusedImages.fold(0, (total, image) => total + image.sizeBytes);
}

class NoteImageCleanupDeleteResult {
  const NoteImageCleanupDeleteResult({
    required this.deletedImages,
    required this.failedImages,
    required this.skippedCount,
  });

  final List<NoteImageCleanupEntry> deletedImages;
  final List<NoteImageCleanupEntry> failedImages;
  final int skippedCount;

  int get deletedCount => deletedImages.length;

  int get deletedSizeBytes =>
      deletedImages.fold(0, (total, image) => total + image.sizeBytes);
}

class NoteImageCleanupService {
  const NoteImageCleanupService({this.api = const NoteImageCleanupRustApi()});

  final NoteImageCleanupRustApi api;

  Future<NoteImageCleanupScan> scan(LocalDataState localDataState) async {
    return NoteStorageCoordinator.runForDataDirectory(
      localDataState.dataDirectory,
      () async {
        final result = await api.scan(localDataState.dataDirectory);
        if (!result.ok) {
          throw StateError(_errorMessage(result.errorMessage, '图片扫描失败'));
        }
        return NoteImageCleanupScan(
          totalImageCount: result.totalImageCount,
          referencedImageCount: result.referencedImageCount,
          totalSizeBytes: _platformInt64ToInt(result.totalSizeBytes),
          unusedImages: List.unmodifiable(
            result.unusedImages.map(NoteImageCleanupEntry.fromRust),
          ),
        );
      },
    );
  }

  Future<NoteImageCleanupDeleteResult> deleteUnusedImages({
    required LocalDataState localDataState,
    required Iterable<String> candidateRelativePaths,
  }) async {
    final candidates = candidateRelativePaths.toList(growable: false);
    return NoteStorageCoordinator.runForDataDirectory(
      localDataState.dataDirectory,
      () async {
        final result = await api.deleteUnused(
          dataDirectory: localDataState.dataDirectory,
          candidateRelativePaths: candidates,
        );
        if (!result.ok) {
          throw StateError(_errorMessage(result.errorMessage, '图片清理失败'));
        }
        return NoteImageCleanupDeleteResult(
          deletedImages: List.unmodifiable(
            result.deletedImages.map(NoteImageCleanupEntry.fromRust),
          ),
          failedImages: List.unmodifiable(
            result.failedImages.map(NoteImageCleanupEntry.fromRust),
          ),
          skippedCount: result.skippedCount,
        );
      },
    );
  }

  String _errorMessage(String message, String fallback) {
    final trimmed = message.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }
}

class NoteImageCleanupRustApi {
  const NoteImageCleanupRustApi();

  Future<rust_model.NoteImageCleanupScanResult> scan(String dataDirectory) {
    return rust_api.scanNoteImages(dataDirectory: dataDirectory);
  }

  Future<rust_model.NoteImageCleanupDeleteResult> deleteUnused({
    required String dataDirectory,
    required List<String> candidateRelativePaths,
  }) {
    return rust_api.deleteUnusedNoteImages(
      dataDirectory: dataDirectory,
      candidateRelativePaths: candidateRelativePaths,
    );
  }
}

int _platformInt64ToInt(Object value) {
  if (value is int) {
    return value;
  }
  if (value is BigInt) {
    return value.toInt();
  }
  return int.parse(value.toString());
}
