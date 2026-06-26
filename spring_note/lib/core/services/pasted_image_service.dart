import 'dart:io';
import 'dart:typed_data';

class SavedPastedImage {
  const SavedPastedImage({required this.path, required this.name});

  final String path;
  final String name;
}

class PastedImageService {
  const PastedImageService();

  Future<SavedPastedImage> savePngForNote({
    required String notePath,
    required Uint8List pngBytes,
    DateTime? now,
  }) async {
    if (pngBytes.isEmpty) {
      throw ArgumentError.value(pngBytes, 'pngBytes', 'must not be empty');
    }

    final imageDirectory = await _ensureImageDirectory(notePath);

    final timestamp = _timestamp(now ?? DateTime.now());
    var name = 'pasted-image-$timestamp.png';
    var file = File(_join(imageDirectory.path, name));
    var index = 2;
    while (await file.exists()) {
      name = 'pasted-image-$timestamp-$index.png';
      file = File(_join(imageDirectory.path, name));
      index++;
    }

    await file.writeAsBytes(pngBytes, flush: true);
    return SavedPastedImage(path: file.path, name: name);
  }

  Future<SavedPastedImage> copyImageFileForNote({
    required String notePath,
    required String sourcePath,
    required String sourceName,
  }) async {
    final preferredName = _safeImageFileName(
      sourceName.trim().isNotEmpty ? sourceName : _fileName(sourcePath),
      sourcePath,
    );
    final imageDirectory = await _ensureImageDirectory(notePath);
    var name = preferredName;
    var file = File(_join(imageDirectory.path, name));
    var index = 2;
    while (await file.exists()) {
      name = _deduplicatedName(preferredName, index);
      file = File(_join(imageDirectory.path, name));
      index++;
    }

    await File(sourcePath).copy(file.path);
    return SavedPastedImage(path: file.path, name: name);
  }

  Future<Directory> _ensureImageDirectory(String notePath) async {
    final noteDirectory = File(notePath).parent;
    final imageDirectory = Directory(_join(noteDirectory.path, 'images'));
    if (!await imageDirectory.exists()) {
      await imageDirectory.create(recursive: true);
    }
    return imageDirectory;
  }

  String _safeImageFileName(String value, String sourcePath) {
    final sanitized = _sanitizeFileName(value);
    final fallback = _sanitizeFileName(_fileName(sourcePath));
    final name = sanitized.isEmpty
        ? (fallback.isEmpty ? 'image.png' : fallback)
        : sanitized;
    if (_hasAllowedImageExtension(name)) {
      return name;
    }

    final sourceExtension = _allowedExtension(sourcePath);
    if (sourceExtension == null) {
      throw ArgumentError.value(sourcePath, 'sourcePath', 'unsupported image');
    }
    return '${_stripAllowedImageExtension(name)}$sourceExtension';
  }

  String _sanitizeFileName(String value) {
    return value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  }

  String _deduplicatedName(String name, int index) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) {
      return '$name-$index';
    }
    return '${name.substring(0, dot)}-$index${name.substring(dot)}';
  }

  String _fileName(String path) {
    final segments = path.split(RegExp(r'[\\/]')).where((item) {
      return item.trim().isNotEmpty;
    }).toList();
    return segments.isEmpty ? 'image.png' : segments.last;
  }

  String _stripAllowedImageExtension(String name) {
    final extension = _allowedExtension(name);
    if (extension == null) {
      return name;
    }
    return name.substring(0, name.length - extension.length);
  }

  bool _hasAllowedImageExtension(String path) {
    return _allowedExtension(path) != null;
  }

  String? _allowedExtension(String path) {
    final lower = path.toLowerCase();
    for (final extension in const [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.heic',
      '.bmp',
    ]) {
      if (lower.endsWith(extension)) {
        return extension;
      }
    }
    return null;
  }

  String _join(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }

  String _timestamp(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');
    final millisecond = date.millisecond.toString().padLeft(3, '0');
    return '$year$month$day-$hour$minute$second-$millisecond';
  }
}
