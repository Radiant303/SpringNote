import '../attachments/pending_image.dart';
import 'pasted_image_service.dart';

class SavedPendingImage {
  const SavedPendingImage({
    required this.path,
    required this.name,
    required this.markdownPath,
  });

  final String path;
  final String name;
  final String markdownPath;
}

class PendingImageService {
  const PendingImageService({
    this.pastedImageService = const PastedImageService(),
  });

  final PastedImageService pastedImageService;

  Future<List<SavedPendingImage>> saveForDailyNote({
    required String notePath,
    required List<PendingImage> images,
  }) async {
    if (images.isEmpty) {
      return const [];
    }

    final saved = <SavedPendingImage>[];
    for (final image in images) {
      if (image.bytes.isEmpty) {
        continue;
      }
      final copied = await pastedImageService.saveImageBytesForNote(
        notePath: notePath,
        bytes: image.bytes,
        preferredName: image.name,
        extension: image.extension,
      );
      saved.add(
        SavedPendingImage(
          path: copied.path,
          name: copied.name,
          markdownPath: pastedImageService.markdownPathForNote(
            notePath: notePath,
            imagePath: copied.path,
          ),
        ),
      );
    }

    return saved;
  }
}
