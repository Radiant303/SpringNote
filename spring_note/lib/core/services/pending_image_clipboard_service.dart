import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../attachments/pending_image.dart';
import 'clipboard_image_service.dart';
import 'image_file_types.dart';

class PendingImageClipboardService {
  const PendingImageClipboardService({
    this.clipboardImageService = const ClipboardImageService(),
  });

  final ClipboardImageService clipboardImageService;

  Future<List<PendingImage>> readPendingImages() async {
    final fileImages = await _readImageFiles();
    if (fileImages.isNotEmpty) {
      return fileImages;
    }

    final bytes = await clipboardImageService.readPngImage();
    if (bytes == null || bytes.isEmpty) {
      return const [];
    }

    return [
      PendingImage(
        id: 'clipboard-png-0',
        bytes: Uint8List.fromList(bytes),
        name: 'pasted-image.png',
        extension: 'png',
      ),
    ];
  }

  Future<List<PendingImage>> _readImageFiles() async {
    final paths = await clipboardImageService.readImageFiles();
    final images = <PendingImage>[];

    for (final path in paths) {
      final extension = allowedImageExtension(path)?.replaceFirst('.', '');
      if (extension == null) {
        continue;
      }
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        continue;
      }
      images.add(
        PendingImage(
          id: 'clipboard-file-${images.length}',
          bytes: Uint8List.fromList(bytes),
          name: p.basename(path),
          extension: extension,
        ),
      );
    }

    return images;
  }
}
