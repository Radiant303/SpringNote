import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/note_file.dart';
import 'package:spring_note/core/services/note_service.dart';

void main() {
  test('note service reads and writes markdown files', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_notes_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final notePath =
        '${temp.path}${Platform.pathSeparator}daily${Platform.pathSeparator}2026-06-18.md';
    const service = NoteService();

    expect(await service.readMarkdown(notePath), isEmpty);

    await service.writeMarkdown(notePath, '# 日报\n\n- 完成第一阶段');

    expect(await File(notePath).exists(), isTrue);
    expect(await service.readMarkdown(notePath), contains('完成第一阶段'));
  });

  test('note service lists and ensures current markdown files', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_list_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    const service = NoteService();
    final ensured = await service.ensureCurrentMarkdownFile(
      directoryPath: temp.path,
      kind: NoteKind.daily,
      now: DateTime(2026, 6, 18),
    );
    final files = await service.listMarkdownFiles(
      directoryPath: temp.path,
      kind: NoteKind.daily,
    );

    expect(ensured.name, '2026-06-18.md');
    expect(files, hasLength(1));
    expect(files.single.title, contains('2026-06-18'));
  });
}
