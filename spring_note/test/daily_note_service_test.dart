import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/structured_note_section_config.dart';
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
    final defaults = StructuredNoteSectionConfig.defaults;
    final sectionConfigs = [
      defaults[0].copyWith(title: '今日进展'),
      defaults[1].copyWith(title: '当前阻塞'),
      defaults[2].copyWith(title: '后续安排'),
    ];
    final firstPath = await service.mergeStructuredNote(
      dailyNotesDirectory: temp.path,
      date: date,
      sectionConfigs: sectionConfigs,
      note: const StructuredWorkNote(
        rawInput: '完成首页输入',
        sections: [
          StructuredWorkNoteSection(
            id: StructuredNoteSectionIds.a,
            items: ['完成首页输入'],
          ),
          StructuredWorkNoteSection(id: StructuredNoteSectionIds.b, items: []),
          StructuredWorkNoteSection(id: StructuredNoteSectionIds.c, items: []),
        ],
      ),
    );

    expect(firstPath.endsWith('2026-06-18.md'), isTrue);
    expect(await File(firstPath).exists(), isTrue);
    final firstMarkdown = await File(firstPath).readAsString();
    expect(firstMarkdown, contains('完成首页输入'));
    expect(firstMarkdown, contains('### 今日进展'));
    expect(firstMarkdown, contains('### 当前阻塞'));
    expect(firstMarkdown, contains('### 后续安排'));

    await service.mergeStructuredNote(
      dailyNotesDirectory: temp.path,
      date: date,
      sectionConfigs: sectionConfigs,
      note: const StructuredWorkNote(
        rawInput: '明天补充测试',
        sections: [
          StructuredWorkNoteSection(id: StructuredNoteSectionIds.a, items: []),
          StructuredWorkNoteSection(id: StructuredNoteSectionIds.b, items: []),
          StructuredWorkNoteSection(
            id: StructuredNoteSectionIds.c,
            items: ['明天补充测试'],
          ),
        ],
      ),
    );

    final merged = await File(firstPath).readAsString();
    expect(merged, contains('完成首页输入'));
    expect(merged, contains('明天补充测试'));
  });
}
