const allowedImageExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.heic',
  '.svg',
  '.jfif',
  '.bmp',
};

String? allowedImageExtension(String path) {
  final lower = path.toLowerCase();
  for (final extension in allowedImageExtensions) {
    if (lower.endsWith(extension)) {
      return extension;
    }
  }
  return null;
}

String normalizedImageExtension(String extension, {String fallback = 'png'}) {
  final normalized = extension.trim().toLowerCase().replaceFirst('.', '');
  return allowedImageExtensions.contains('.$normalized')
      ? normalized
      : fallback;
}

bool hasAllowedImageExtension(String path) {
  return allowedImageExtension(path) != null;
}
