import 'dart:typed_data';

class PendingImage {
  const PendingImage({
    required this.id,
    required this.bytes,
    required this.name,
    required this.extension,
  });

  final String id;
  final Uint8List bytes;
  final String name;
  final String extension;

  bool get isSvg => extension.toLowerCase() == 'svg';
}
