import '../models/structured_work_note.dart';

class MockAiService {
  const MockAiService();

  StructuredWorkNote structureWorkNote(String input) {
    final lines = input
        .split(RegExp(r'[\r\n。；;]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final completed = <String>[];
    final issues = <String>[];
    final plans = <String>[];

    for (final line in lines) {
      if (_matches(line, ['明天', '计划', '接下来', '后续', '待办', '准备'])) {
        plans.add(line);
      } else if (_matches(line, ['问题', '阻塞', '报错', '失败', '异常', '卡住', '风险'])) {
        issues.add(line);
      } else {
        completed.add(line);
      }
    }

    if (completed.isEmpty &&
        issues.isEmpty &&
        plans.isEmpty &&
        input.trim().isNotEmpty) {
      completed.add(input.trim());
    }

    return StructuredWorkNote(
      rawInput: input.trim(),
      completed: completed,
      issues: issues,
      plans: plans,
    );
  }

  bool _matches(String value, List<String> keywords) {
    return keywords.any(value.contains);
  }
}
