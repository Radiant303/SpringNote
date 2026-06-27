import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/structured_work_note.dart';
import 'package:spring_note/core/router/app_shell.dart';
import 'package:spring_note/core/services/daily_note_service.dart';
import 'package:spring_note/core/services/desktop_widget_controller.dart';
import 'package:spring_note/core/services/home_overview_service.dart';
import 'package:spring_note/core/services/local_data_service.dart';
import 'package:spring_note/core/services/stats_service.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/home/home_page.dart';
import 'package:spring_note/src/rust/stats.dart' as rust_stats;

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
    expect(find.text('EARNINGS TODAY'), findsOneWidget);
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
    final fakeHomeOverviewService = _FakeHomeOverviewService();
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
          homeOverviewService: fakeHomeOverviewService,
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      '完成首页输入流程\n问题：按钮状态需要校验\n明天补充更多测试',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('home-smart-generate-button')));
    for (var index = 0; index < 20; index++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (fakeHomeOverviewService.savedOverview != null) {
        break;
      }
    }

    expect(find.text('完成首页输入流程'), findsOneWidget);
    expect(find.text('问题：按钮状态需要校验'), findsOneWidget);
    expect(find.text('明天补充更多测试'), findsOneWidget);
    expect(fakeDailyNoteService.savedNote?.rawInput, contains('完成首页输入流程'));
    expect(
      fakeHomeOverviewService.savedOverview?.completed,
      contains('完成首页输入流程'),
    );
  });

  for (final shortcut in const [
    (name: 'ctrl enter', key: LogicalKeyboardKey.controlLeft),
    (name: 'meta enter', key: LogicalKeyboardKey.metaLeft),
  ]) {
    testWidgets('home input submits with ${shortcut.name}', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeDailyNoteService = _FakeDailyNoteService();
      final fakeHomeOverviewService = _FakeHomeOverviewService();
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
            homeOverviewService: fakeHomeOverviewService,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '用快捷键整理首页内容');
      await tester.sendKeyDownEvent(shortcut.key);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(shortcut.key);
      for (var index = 0; index < 20; index++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (fakeDailyNoteService.savedNote != null) {
          break;
        }
      }

      expect(fakeDailyNoteService.savedNote?.rawInput, contains('用快捷键整理首页内容'));
      expect(
        fakeHomeOverviewService.savedOverview?.completed,
        contains('用快捷键整理首页内容'),
      );
    });
  }

  testWidgets('home attachment buttons add files to submitted note', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeDailyNoteService = _FakeDailyNoteService();
    final fakeHomeOverviewService = _FakeHomeOverviewService();
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
          homeOverviewService: fakeHomeOverviewService,
          imageAttachmentPicker: () async => const [
            HomeAttachment(
              path: '/Users/demo/Desktop/screenshot.png',
              name: 'screenshot.png',
              kind: HomeAttachmentKind.image,
            ),
          ],
          documentAttachmentPicker: () async => const [
            HomeAttachment(
              path: '/Users/demo/Documents/spec.pdf',
              name: 'spec.pdf',
              kind: HomeAttachmentKind.document,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byTooltip('上传图片'));
    await tester.pump();
    await tester.tap(find.byTooltip('添加文件'));
    await tester.pump();

    expect(find.text('图片 · screenshot.png'), findsOneWidget);
    expect(find.text('文件 · spec.pdf'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '整理附件内容');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('home-smart-generate-button')));
    for (var index = 0; index < 20; index++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (fakeDailyNoteService.savedNote != null) {
        break;
      }
    }

    final rawInput = fakeDailyNoteService.savedNote?.rawInput ?? '';
    expect(rawInput, contains('整理附件内容'));
    expect(rawInput, contains('附件：'));
    expect(rawInput, contains('[图片] screenshot.png'));
    expect(rawInput, contains('/Users/demo/Desktop/screenshot.png'));
    expect(rawInput, contains('[文件] spec.pdf'));
    expect(rawInput, contains('/Users/demo/Documents/spec.pdf'));
  });

  testWidgets('home income stays in sync with desktop widget controller', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final localDataState = LocalDataState(
      dataDirectory: 'D:\\Temp\\SpringNote',
      configPath: 'D:\\Temp\\SpringNote\\config.json',
      dailyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\daily',
      weeklyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\weekly',
      monthlyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\monthly',
      config: AppConfig.defaults().copyWith(
        dailyWorkHours: 1,
        dailySalary: 3600,
      ),
    );
    final controller = DesktopWidgetController(
      statsService: const _FakeStatsService(),
      tickDuration: const Duration(seconds: 1),
    )..attach(localDataState);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomePage(
          localDataState: localDataState,
          homeOverviewService: _FakeHomeOverviewService(),
          desktopWidgetController: controller,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('10'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('11'), findsOneWidget);
    expect(find.text('+1.000 c/s'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _FakeDailyNoteService extends DailyNoteService {
  StructuredWorkNote? savedNote;

  @override
  Future<String> readDailyMarkdown({
    required String dailyNotesDirectory,
    required DateTime date,
  }) async {
    return '';
  }

  @override
  Future<String> mergeStructuredNote({
    required String dailyNotesDirectory,
    required DateTime date,
    required StructuredWorkNote note,
    String? mergedMarkdown,
  }) async {
    savedNote = note;
    return '$dailyNotesDirectory\\2026-06-18.md';
  }
}

class _FakeHomeOverviewService extends HomeOverviewService {
  StructuredWorkNote? savedOverview;

  @override
  Future<StructuredWorkNote> readOverview({
    required String appDataDir,
    required DateTime date,
  }) async {
    return const StructuredWorkNote(
      rawInput: '',
      completed: [],
      issues: [],
      plans: [],
    );
  }

  @override
  Future<StructuredWorkNote> mergeAndSaveOverview({
    required String appDataDir,
    required DateTime date,
    required StructuredWorkNote current,
    required StructuredWorkNote incoming,
  }) async {
    savedOverview = StructuredWorkNote(
      rawInput: incoming.rawInput,
      completed: [...incoming.completed, ...current.completed],
      issues: [...incoming.issues, ...current.issues],
      plans: [...incoming.plans, ...current.plans],
    );
    return savedOverview!;
  }
}

class _FakeStatsService extends StatsService {
  const _FakeStatsService();

  @override
  Future<rust_stats.StatsSnapshot> readSnapshot({
    required LocalDataState localDataState,
    required DateTime start,
    required DateTime end,
  }) async {
    return const rust_stats.StatsSnapshot(
      summary: rust_stats.StatsSummary(
        summaries: 0,
        fimCompletions: 0,
        totalRecords: 0,
        dailyNotes: 0,
        weeklyNotes: 0,
        monthlyNotes: 0,
        inputTokens: 0,
        outputTokens: 0,
        cachedTokens: 0,
        appLaunches: 0,
        workSeconds: 10,
        coins: 10,
      ),
      activity: [],
      tokenUsage: [],
      providerUsage: [],
    );
  }

  @override
  Future<void> recordWorkTime({
    required String appDataDir,
    required int workSeconds,
    required double coins,
  }) async {}
}
