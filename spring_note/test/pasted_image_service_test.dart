import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/services/pasted_image_service.dart';

void main() {
  test('save png writes unique files for note', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_pasted_image_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final noteFile = File(_join(temp.path, 'notes/daily.md'));
    await noteFile.parent.create(recursive: true);
    await noteFile.writeAsString('');

    final service = const PastedImageService();
    final now = DateTime(2026, 6, 18, 12, 0, 0);
    final first = await service.savePngForNote(
      notePath: noteFile.path,
      pngBytes: Uint8List.fromList([1, 2, 3]),
      now: now,
    );
    final second = await service.savePngForNote(
      notePath: noteFile.path,
      pngBytes: Uint8List.fromList([4, 5, 6]),
      now: now,
    );

    expect(first.name, 'pasted-image-20260618-120000-000.png');
    expect(second.name, 'pasted-image-20260618-120000-000-2.png');
    expect(await File(first.path).readAsBytes(), [1, 2, 3]);
    expect(await File(second.path).readAsBytes(), [4, 5, 6]);
  });

  test('save png rejects empty bytes', () async {
    await expectLater(
      const PastedImageService().savePngForNote(
        notePath: _join(Directory.systemTemp.path, 'daily.md'),
        pngBytes: Uint8List(0),
      ),
      throwsArgumentError,
    );
  });

  test('copy image sanitizes fallback file name from source path', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_pasted_image_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final noteFile = File(_join(temp.path, 'notes/daily.md'));
    await noteFile.parent.create(recursive: true);
    await noteFile.writeAsString('');

    final sourceName = Platform.isWindows ? '.png' : 'bad<name>.png';
    final expectedName = Platform.isWindows ? 'png.png' : 'bad-name-.png';
    final sourceFile = File(_join(temp.path, sourceName));
    await sourceFile.writeAsBytes([1, 2, 3]);

    final saved = await const PastedImageService().copyImageFileForNote(
      notePath: noteFile.path,
      sourcePath: sourceFile.path,
      sourceName: '  ',
    );

    expect(saved.name, expectedName);
    expect(File(saved.path).existsSync(), isTrue);
    expect(await File(saved.path).readAsBytes(), [1, 2, 3]);
    expect(
      saved.path,
      _join(_join(noteFile.parent.path, 'images'), expectedName),
    );
  });

  test('copy image preserves non-image multi extension names', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_pasted_image_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final noteFile = File(_join(temp.path, 'notes/daily.md'));
    await noteFile.parent.create(recursive: true);
    await noteFile.writeAsString('');

    final sourceFile = File(_join(temp.path, 'source.png'));
    await sourceFile.writeAsBytes([1, 2, 3]);

    final saved = await const PastedImageService().copyImageFileForNote(
      notePath: noteFile.path,
      sourcePath: sourceFile.path,
      sourceName: 'image.tar.gz',
    );

    expect(saved.name, 'image.tar.gz.png');
  });
}

String _join(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}
