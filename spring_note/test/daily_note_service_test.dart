import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/structured_work_note.dart';
import 'package:spring_note/core/services/daily_note_service.dart';

void main() {
  test('daily note service creates and merges today markdown', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_daily_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    const service = DailyNoteService();
    final date = DateTime(2026, 6, 18, 17, 30);
    final firstPath = await service.mergeStructuredNote(
      dailyNotesDirectory: temp.path,
      date: date,
      note: const StructuredWorkNote(
        rawInput: '完成首页输入',
        completed: ['完成首页输入'],
        issues: [],
        plans: [],
      ),
    );

    expect(firstPath.endsWith('2026-06-18.md'), isTrue);
    expect(await File(firstPath).exists(), isTrue);
    expect(await File(firstPath).readAsString(), contains('完成首页输入'));

    await service.mergeStructuredNote(
      dailyNotesDirectory: temp.path,
      date: date,
      note: const StructuredWorkNote(
        rawInput: '明天补充测试',
        completed: [],
        issues: [],
        plans: ['明天补充测试'],
      ),
    );

    final merged = await File(firstPath).readAsString();
    expect(merged, contains('完成首页输入'));
    expect(merged, contains('明天补充测试'));
  });
}
