import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/structured_note_section_config.dart';
import 'package:spring_note/core/models/structured_work_note.dart';
import 'package:spring_note/core/services/mock_ai_service.dart';

void main() {
  const service = MockAiService();

  test('default section semantics keep local keyword classification', () {
    final defaults = StructuredNoteSectionConfig.defaults;
    final note = service.structureWorkNote(
      '完成首页开发。问题：按钮报错。明天补充测试。',
      sectionConfigs: [
        defaults[0].copyWith(title: '今日进展'),
        defaults[1].copyWith(title: '当前阻塞'),
        defaults[2].copyWith(title: '后续安排'),
      ],
    );

    expect(note.itemsFor(StructuredNoteSectionIds.a), ['完成首页开发']);
    expect(note.itemsFor(StructuredNoteSectionIds.b), ['问题：按钮报错']);
    expect(note.itemsFor(StructuredNoteSectionIds.c), ['明天补充测试']);
  });

  test('custom section semantics use conservative local fallback', () {
    final defaults = StructuredNoteSectionConfig.defaults;
    final note = service.structureWorkNote(
      '完成首页开发。问题：按钮报错。明天补充测试。',
      sectionConfigs: [
        defaults[0].copyWith(title: '工作记录', aiInstruction: '保留所有输入内容。'),
        defaults[1].copyWith(title: '灵感'),
        defaults[2].copyWith(title: '资料'),
      ],
    );

    expect(note.itemsFor(StructuredNoteSectionIds.a), [
      '完成首页开发',
      '问题：按钮报错',
      '明天补充测试',
    ]);
    expect(note.itemsFor(StructuredNoteSectionIds.b), isEmpty);
    expect(note.itemsFor(StructuredNoteSectionIds.c), isEmpty);
  });
}
