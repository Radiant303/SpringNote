import 'dart:convert';
import 'dart:io';

import '../attachments/pending_image.dart';
import '../models/memory_message.dart';

class MemoryConversationService {
  const MemoryConversationService();

  Future<List<MemoryMessage>> readMessages({required String appDataDir}) async {
    final file = _rememberFile(appDataDir);
    if (!await file.exists()) {
      return [];
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return [];
    }
    final decoded = jsonDecode(content);
    if (decoded is! List) {
      return [];
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .map(MemoryMessage.fromJson)
        .toList();
  }

  Future<void> saveMessages({
    required String appDataDir,
    required List<MemoryMessage> messages,
  }) async {
    final file = _rememberFile(appDataDir);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert(messages.map((message) => message.toJson()).toList())}\n',
    );
  }

  Future<void> clear({required String appDataDir}) async {
    final file = _rememberFile(appDataDir);
    await file.parent.create(recursive: true);
    await file.writeAsString('[]\n');
    final imagesDirectory = _imagesDirectory(appDataDir);
    if (await imagesDirectory.exists()) {
      await imagesDirectory.delete(recursive: true);
    }
  }

  /// Persists the images attached to a user message under
  /// `memory_images/` and returns their file names for
  /// [MemoryMessage.imageNames].
  Future<List<String>> saveImages({
    required String appDataDir,
    required List<PendingImage> images,
  }) async {
    if (images.isEmpty) {
      return const [];
    }
    final directory = _imagesDirectory(appDataDir);
    await directory.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final names = <String>[];
    for (var index = 0; index < images.length; index++) {
      final image = images[index];
      final name = '${stamp}_$index.${image.extension}';
      await File(_join(directory.path, name)).writeAsBytes(image.bytes);
      names.add(name);
    }
    return names;
  }

  /// Reads a previously saved conversation image by file name; null when
  /// the file is gone (e.g. the data directory was moved without it).
  Future<List<int>?> readImageBytes({
    required String appDataDir,
    required String name,
  }) async {
    if (name.contains('/') || name.contains('\\') || name.isEmpty) {
      return null;
    }
    final file = File(_join(_imagesDirectory(appDataDir).path, name));
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  /// Absolute path of a saved conversation image, for rendering thumbnails.
  String imagePath({required String appDataDir, required String name}) {
    return _join(_imagesDirectory(appDataDir).path, name);
  }

  Directory _imagesDirectory(String appDataDir) {
    return Directory(_join(appDataDir, 'memory_images'));
  }

  File _rememberFile(String appDataDir) {
    return File(_join(appDataDir, 'remember.json'));
  }

  String _join(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }
}
