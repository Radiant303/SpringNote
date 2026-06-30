import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

Widget? buildMarkdownLocalImage({
  required String url,
  required String? baseDirectoryPath,
  required double? width,
  required double? height,
  required BoxFit fit,
  required ImageErrorWidgetBuilder errorBuilder,
}) {
  final file = _localImageFile(url, baseDirectoryPath);
  if (file == null) {
    return null;
  }
  if (_isSvgFile(file.path)) {
    return SvgPicture.file(
      file,
      width: width,
      height: height,
      fit: fit,
      placeholderBuilder: (context) => const SizedBox.shrink(),
    );
  }
  return Image.file(
    file,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: errorBuilder,
  );
}

File? _localImageFile(String value, String? baseDirectoryPath) {
  if (baseDirectoryPath == null || baseDirectoryPath.trim().isEmpty) {
    return null;
  }

  final candidate = _candidateFile(value, baseDirectoryPath);
  if (candidate == null || !_hasAllowedImageExtension(candidate.path)) {
    return null;
  }

  final base = _resolvedDirectoryPath(baseDirectoryPath);
  final resolvedFile = _resolvedFile(candidate);
  if (base == null || resolvedFile == null) {
    return null;
  }

  if (_isSameOrInsideDirectory(path: resolvedFile.path, base: base)) {
    return resolvedFile.file;
  }
  return null;
}

File? _candidateFile(String value, String baseDirectoryPath) {
  if (_isWindowsAbsolutePath(value)) {
    return File(value);
  }

  final uri = Uri.tryParse(value);
  if (uri == null) {
    return null;
  }
  if (uri.scheme == 'file') {
    return File.fromUri(uri);
  }
  if (uri.hasScheme) {
    return null;
  }
  if (_isRootedPath(value)) {
    return File(value);
  }
  return File(_joinPath(baseDirectoryPath, _decodeMarkdownImagePath(value)));
}

String _decodeMarkdownImagePath(String value) {
  try {
    return Uri.decodeFull(value);
  } catch (_) {
    return value;
  }
}

bool _isSvgFile(String path) {
  return path.toLowerCase().endsWith('.svg');
}

bool _hasAllowedImageExtension(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.svg') ||
      lower.endsWith('.jfif') ||
      lower.endsWith('.bmp');
}

bool _isWindowsAbsolutePath(String value) {
  return Platform.isWindows && RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
}

bool _isRootedPath(String value) {
  return value.startsWith('/') ||
      (Platform.isWindows && value.startsWith(r'\\'));
}

String _joinPath(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

String _canonicalPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.startsWith('//')) {
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return _canonicalParts('//${parts[0]}/${parts[1]}', parts.skip(2));
    }
  }

  final driveMatch = RegExp(r'^[a-zA-Z]:/').firstMatch(normalized);
  final prefix = driveMatch == null
      ? normalized.startsWith('/')
            ? '/'
            : ''
      : driveMatch.group(0)!.toLowerCase();
  final rest = prefix.isEmpty
      ? normalized
      : normalized.substring(prefix.length);
  return _canonicalParts(prefix, rest.split('/'));
}

String _canonicalParts(String prefix, Iterable<String> rawParts) {
  final parts = <String>[];

  for (final part in rawParts) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (parts.isNotEmpty) {
        parts.removeLast();
      }
      continue;
    }
    parts.add(part);
  }

  final pathWithoutCaseNormalization = switch ((prefix, parts.isEmpty)) {
    ('', true) => '',
    ('', false) => parts.join('/'),
    ('/', true) => '/',
    ('/', false) => '/${parts.join('/')}',
    (_, true) => prefix,
    _ => '$prefix/${parts.join('/')}',
  };
  if (Platform.isWindows) {
    return pathWithoutCaseNormalization.toLowerCase();
  }
  return pathWithoutCaseNormalization;
}

String? _resolvedDirectoryPath(String path) {
  try {
    return _canonicalPath(Directory(path).resolveSymbolicLinksSync());
  } on FileSystemException {
    return null;
  }
}

({String path, File file})? _resolvedFile(File file) {
  try {
    return (
      path: _canonicalPath(file.resolveSymbolicLinksSync()),
      file: file.absolute,
    );
  } on FileSystemException {
    final resolvedMissingPath = _resolvedMissingFilePath(file.absolute);
    if (resolvedMissingPath == null) {
      return null;
    }
    return (path: resolvedMissingPath, file: file.absolute);
  }
}

String? _resolvedMissingFilePath(File file) {
  var directory = file.parent;
  final missingParts = <String>[_pathBasename(file.path)];

  while (true) {
    try {
      final resolvedDirectory = directory.resolveSymbolicLinksSync();
      return _canonicalPath(
        _joinPath(resolvedDirectory, missingParts.reversed.join('/')),
      );
    } on FileSystemException {
      final parent = directory.parent;
      if (parent.path == directory.path) {
        return null;
      }
      missingParts.add(_pathBasename(directory.path));
      directory = parent;
    }
  }
}

String _pathBasename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final trimmed = normalized.endsWith('/') && normalized.length > 1
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final separator = trimmed.lastIndexOf('/');
  return separator < 0 ? trimmed : trimmed.substring(separator + 1);
}

bool _isSameOrInsideDirectory({required String path, required String base}) {
  if (path == base) {
    return true;
  }
  final prefix = base.endsWith('/') ? base : '$base/';
  return path.startsWith(prefix);
}
