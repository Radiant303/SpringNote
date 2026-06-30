import 'dart:io';
import 'dart:typed_data';

import 'image_file_types.dart';

class SavedPastedImage {
  const SavedPastedImage({required this.path, required this.name});

  final String path;
  final String name;
}

class PastedImageService {
  const PastedImageService();

  static const int _maxImageFileNameAttempts = 100;
  static const _noteDirectoryNames = {'daily', 'weekly', 'monthly'};

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
    final available = await _availableImageFile(
      imageDirectory: imageDirectory,
      preferredName: 'pasted-image-$timestamp.png',
    );

    await available.file.writeAsBytes(pngBytes, flush: true);
    return SavedPastedImage(path: available.file.path, name: available.name);
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
    final available = await _availableImageFileForNote(
      notePath: notePath,
      preferredName: preferredName,
    );

    await File(sourcePath).copy(available.file.path);
    return SavedPastedImage(path: available.file.path, name: available.name);
  }

  Future<SavedPastedImage> saveImageBytesForNote({
    required String notePath,
    required Uint8List bytes,
    required String preferredName,
    required String extension,
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }
    final safeExtension = normalizedImageExtension(extension);
    final safeName = _safeImageFileName(
      preferredName.trim().isEmpty
          ? 'pasted-image.$safeExtension'
          : preferredName,
      'image.$safeExtension',
    );
    final available = await _availableImageFileForNote(
      notePath: notePath,
      preferredName: safeName,
    );

    await available.file.writeAsBytes(bytes, flush: true);
    return SavedPastedImage(path: available.file.path, name: available.name);
  }

  Future<({File file, String name})> _availableImageFileForNote({
    required String notePath,
    required String preferredName,
  }) async {
    final imageDirectory = await _ensureImageDirectory(notePath);
    return _availableImageFile(
      imageDirectory: imageDirectory,
      preferredName: preferredName,
    );
  }

  Future<Directory> _ensureImageDirectory(String notePath) async {
    final imageDirectory = imageDirectoryForNote(notePath);
    if (!await imageDirectory.exists()) {
      await imageDirectory.create(recursive: true);
    }
    return imageDirectory;
  }

  Directory imageDirectoryForNote(String notePath) {
    final noteDirectory = File(notePath).parent;
    if (_isManagedNoteDirectory(noteDirectory.path)) {
      return Directory(_join(noteDirectory.parent.path, 'images'));
    }
    return Directory(_join(noteDirectory.path, 'images'));
  }

  String markdownPathForNote({
    required String notePath,
    required String imagePath,
  }) {
    final noteDirectory = _parentDirectoryPath(notePath);
    if (_isManagedNoteDirectory(noteDirectory)) {
      final notesDirectory = _parentDirectoryPath(noteDirectory);
      final sharedRelative = _relativePathIfInside(
        path: imagePath,
        baseDirectory: notesDirectory,
      );
      if (sharedRelative != null &&
          sharedRelative.toLowerCase().startsWith('images/')) {
        return _encodeMarkdownPath('../$sharedRelative');
      }
      return _imageUri(imagePath);
    }

    final noteRelative = _relativePathIfInside(
      path: imagePath,
      baseDirectory: noteDirectory,
    );
    if (noteRelative != null) {
      return _encodeMarkdownPath(noteRelative);
    }

    return _imageUri(imagePath);
  }

  Future<({File file, String name})> _availableImageFile({
    required Directory imageDirectory,
    required String preferredName,
  }) async {
    for (var attempt = 1; attempt <= _maxImageFileNameAttempts; attempt++) {
      final name = attempt == 1
          ? preferredName
          : _deduplicatedName(preferredName, attempt);
      final file = File(_join(imageDirectory.path, name));
      if (!await file.exists()) {
        return (file: file, name: name);
      }
    }
    throw StateError('Unable to find an available image file name.');
  }

  String _safeImageFileName(String value, String sourcePath) {
    final sanitized = _sanitizeFileName(value);
    final fallback = _sanitizeFileName(_fileName(sourcePath));
    final name = sanitized.isEmpty
        ? (fallback.isEmpty ? 'image.png' : fallback)
        : sanitized;
    if (hasAllowedImageExtension(name)) {
      return name;
    }

    final sourceExtension = allowedImageExtension(sourcePath);
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

  bool _isManagedNoteDirectory(String path) {
    final name = _fileName(path).toLowerCase();
    return _noteDirectoryNames.contains(name);
  }

  String? _relativePathIfInside({
    required String path,
    required String baseDirectory,
  }) {
    final normalizedPath = path.replaceAll('\\', '/');
    final normalizedBase = _trimTrailingSlashes(
      baseDirectory.replaceAll('\\', '/'),
    );
    final compareCaseInsensitive =
        RegExp(r'^[a-zA-Z]:/').hasMatch(normalizedPath) ||
        RegExp(r'^[a-zA-Z]:/').hasMatch(normalizedBase);
    final comparablePath = compareCaseInsensitive
        ? normalizedPath.toLowerCase()
        : normalizedPath;
    final comparableBase = compareCaseInsensitive
        ? normalizedBase.toLowerCase()
        : normalizedBase;
    final prefix = '$comparableBase/';
    if (!comparablePath.startsWith(prefix)) {
      return null;
    }
    final relative = normalizedPath.substring(normalizedBase.length + 1);
    return relative.isEmpty ? null : relative;
  }

  String _trimTrailingSlashes(String value) {
    var end = value.length;
    while (end > 0 && value.codeUnitAt(end - 1) == 47) {
      end--;
    }
    return value.substring(0, end);
  }

  String _parentDirectoryPath(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf('\\');
    final index = slash > backslash ? slash : backslash;
    if (index <= 0) {
      return path;
    }
    return path.substring(0, index);
  }

  String _encodeMarkdownPath(String path) {
    final buffer = StringBuffer();
    for (final rune in path.runes) {
      final character = String.fromCharCode(rune);
      buffer.write(switch (character) {
        ' ' => '%20',
        '#' => '%23',
        '%' => '%25',
        '?' => '%3F',
        '(' => '%28',
        ')' => '%29',
        '[' => '%5B',
        ']' => '%5D',
        '<' => '%3C',
        '>' => '%3E',
        _ => character,
      });
    }
    return buffer.toString();
  }

  String _imageUri(String path) {
    if (_isWindowsPath(path)) {
      return Uri.file(path, windows: true).toString();
    }
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme) {
      return uri.toString();
    }
    return Uri.file(path).toString();
  }

  bool _isWindowsPath(String path) {
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');
  }

  String _stripAllowedImageExtension(String name) {
    final extension = allowedImageExtension(name);
    if (extension == null) {
      return name;
    }
    return name.substring(0, name.length - extension.length);
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
