import 'dart:typed_data';

import 'pending_image.dart';

class AttachmentManager {
  AttachmentManager();

  final List<PendingImage> _images = [];
  int _nextId = 0;

  List<PendingImage> get images => List.unmodifiable(_images);
  bool get hasImages => _images.isNotEmpty;

  void addImage({
    required Uint8List bytes,
    required String name,
    required String extension,
  }) {
    if (bytes.isEmpty) {
      return;
    }
    final normalizedExtension = extension.trim().toLowerCase();
    _images.add(
      PendingImage(
        id: 'pending-image-${_nextId++}',
        bytes: Uint8List.fromList(bytes),
        name: _normalizeName(name, normalizedExtension),
        extension: normalizedExtension.isEmpty ? 'png' : normalizedExtension,
      ),
    );
  }

  void removeImage(String id) {
    _images.removeWhere((image) => image.id == id);
  }

  void clear() {
    _images.clear();
  }

  String _normalizeName(String name, String extension) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    final suffix = extension.trim().isEmpty ? 'png' : extension.trim();
    return 'pasted-image.$suffix';
  }
}
