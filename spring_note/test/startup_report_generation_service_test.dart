import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/services/ai_client_service.dart';
import 'package:spring_note/core/services/startup_report_generation_service.dart';

class _FakeAiClientService extends AiClientService {
  String? lastMonthlySource;

  @override
  Future<String?> generateMonthlyReport({
    required String appDataDir,
    required AppConfig config,
    required String sourceMarkdown,
    required String periodLabel,
    List<AiImageInput> images = const [],
  }) async {
    lastMonthlySource = sourceMarkdown;
    return '# 月报\n\n汇总。\n';
  }
}

void main() {
  late Directory root;
  late LocalDataState state;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'springnote-startup-report-test-',
    );
    final notes = _join(root.path, 'notes');
    state = LocalDataState(
      dataDirectory: root.path,
      configPath: _join(root.path, 'config.json'),
      dailyNotesDirectory: _join(notes, 'daily'),
      weeklyNotesDirectory: _join(notes, 'weekly'),
      monthlyNotesDirectory: _join(notes, 'monthly'),
      config: AppConfig.defaults(),
    );
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('月报生成回退读取小写 w 文件名的周报', () async {
    await Directory(state.weeklyNotesDirectory).create(recursive: true);
    await File(
      _join(state.weeklyNotesDirectory, '2026-w29.md'),
    ).writeAsString('# 2026-W29 周报\n\n小写文件名的周报内容。\n');

    final ai = _FakeAiClientService();
    final generated = await StartupReportGenerationService(
      aiClientService: ai,
    ).generateMissingReports(localDataState: state, now: DateTime(2026, 8, 1));

    expect(ai.lastMonthlySource, contains('小写文件名的周报内容'));
    expect(
      generated.any((report) => report.path.endsWith('2026-07.md')),
      isTrue,
    );
  });
}

String _join(String left, String right) {
  return '$left${Platform.pathSeparator}$right';
}
