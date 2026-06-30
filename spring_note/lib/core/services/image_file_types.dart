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

String imageMimeTypeForExtension(String extension) {
  final normalized = normalizedImageExtension(extension);
  return switch (normalized) {
    'jpg' || 'jpeg' || 'jfif' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'bmp' => 'image/bmp',
    'svg' => 'image/svg+xml',
    _ => 'image/png',
  };
}
