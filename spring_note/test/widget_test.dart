import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/structured_work_note.dart';
import 'package:spring_note/core/router/app_shell.dart';
import 'package:spring_note/core/services/daily_note_service.dart';
import 'package:spring_note/core/services/local_data_service.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/home/home_page.dart';

void main() {
  testWidgets('SpringNote app shows home shell', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('spring_note_widget_test_'),
    );
    expect(temp, isNotNull);

    addTearDown(() async {
      final directory = temp;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final state = await tester.runAsync(
      () => LocalDataService(appDataPath: temp!.path).initialize(),
    );
    expect(state, isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(localDataState: state!),
      ),
    );

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('今日收益'), findsOneWidget);
    expect(find.text('完成事项'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    expect(find.text('偏好设置'), findsOneWidget);
  });

  testWidgets('home input updates overview with mock structured result', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeDailyNoteService = _FakeDailyNoteService();
    final localDataState = LocalDataState(
      dataDirectory: 'D:\\Temp\\SpringNote',
      configPath: 'D:\\Temp\\SpringNote\\config.json',
      dailyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\daily',
      weeklyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\weekly',
      monthlyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\monthly',
      config: AppConfig.defaults(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomePage(
          localDataState: localDataState,
          dailyNoteService: fakeDailyNoteService,
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      '完成首页输入流程\n问题：按钮状态需要校验\n明天补充更多测试',
    );
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump();

    expect(find.text('完成首页输入流程'), findsOneWidget);
    expect(find.text('问题：按钮状态需要校验'), findsOneWidget);
    expect(find.text('明天补充更多测试'), findsOneWidget);
    expect(fakeDailyNoteService.savedNote?.rawInput, contains('完成首页输入流程'));
  });
}

class _FakeDailyNoteService extends DailyNoteService {
  StructuredWorkNote? savedNote;

  @override
  Future<String> mergeStructuredNote({
    required String dailyNotesDirectory,
    required DateTime date,
    required StructuredWorkNote note,
  }) async {
    savedNote = note;
    return '$dailyNotesDirectory\\2026-06-18.md';
  }
}
