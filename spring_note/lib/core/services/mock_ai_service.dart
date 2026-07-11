import '../models/structured_note_section_config.dart';
import '../models/structured_work_note.dart';

class MockAiService {
  const MockAiService();

  StructuredWorkNote structureWorkNote(
    String input, {
    List<StructuredNoteSectionConfig> sectionConfigs =
        StructuredNoteSectionConfig.defaults,
  }) {
    final sections = StructuredNoteSectionConfig.normalize(sectionConfigs);
    final lines = input
        .split(RegExp(r'[\r\n。；;]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty && input.trim().isNotEmpty) {
      lines.add(input.trim());
    }

    if (!_usesDefaultSemantics(sections)) {
      return _buildNote(
        input: input,
        sections: sections,
        firstItems: lines,
        secondItems: const [],
        thirdItems: const [],
      );
    }

    final firstItems = <String>[];
    final secondItems = <String>[];
    final thirdItems = <String>[];

    for (final line in lines) {
      if (_matches(line, ['明天', '计划', '接下来', '后续', '待办', '准备'])) {
        thirdItems.add(line);
      } else if (_matches(line, ['问题', '阻塞', '报错', '失败', '异常', '卡住', '风险'])) {
        secondItems.add(line);
      } else {
        firstItems.add(line);
      }
    }

    return _buildNote(
      input: input,
      sections: sections,
      firstItems: firstItems,
      secondItems: secondItems,
      thirdItems: thirdItems,
    );
  }

  StructuredWorkNote _buildNote({
    required String input,
    required List<StructuredNoteSectionConfig> sections,
    required List<String> firstItems,
    required List<String> secondItems,
    required List<String> thirdItems,
  }) {
    return StructuredWorkNote(
      rawInput: input.trim(),
      sections: [
        StructuredWorkNoteSection(id: sections[0].id, items: firstItems),
        StructuredWorkNoteSection(id: sections[1].id, items: secondItems),
        StructuredWorkNoteSection(id: sections[2].id, items: thirdItems),
      ],
    );
  }

  bool _usesDefaultSemantics(List<StructuredNoteSectionConfig> sections) {
    final defaults = StructuredNoteSectionConfig.defaults;
    for (var index = 0; index < defaults.length; index++) {
      if (sections[index].aiInstruction.trim() !=
          defaults[index].aiInstruction) {
        return false;
      }
    }
    return true;
  }

  bool _matches(String value, List<String> keywords) {
    return keywords.any(value.contains);
  }
}
