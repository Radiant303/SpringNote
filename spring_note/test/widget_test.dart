import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/attachments/pending_image.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/structured_work_note.dart';
import 'package:spring_note/core/router/app_shell.dart';
import 'package:spring_note/core/services/daily_note_service.dart';
import 'package:spring_note/core/services/desktop_widget_controller.dart';
import 'package:spring_note/core/services/home_overview_service.dart';
import 'package:spring_note/core/services/pending_image_clipboard_service.dart';
import 'package:spring_note/core/services/pending_image_service.dart';
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
    final localDataState = _testLocalDataState();

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
    await _pumpUntil(
      tester,
      () => fakeHomeOverviewService.savedOverview != null,
      'home overview to be saved',
    );

    expect(find.text('完成首页输入流程'), findsOneWidget);
    expect(find.text('问题：按钮状态需要校验'), findsOneWidget);
    expect(find.text('明天补充更多测试'), findsOneWidget);
    expect(fakeDailyNoteService.savedNote, isNotNull);
    expect(fakeHomeOverviewService.savedOverview, isNotNull);
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
      final localDataState = _testLocalDataState();

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
      await _pumpUntil(
        tester,
        () => fakeDailyNoteService.savedNote != null,
        'daily note to be saved after ${shortcut.name}',
      );

      expect(fakeDailyNoteService.savedNote, isNotNull);
      expect(fakeHomeOverviewService.savedOverview, isNotNull);
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

    final imageBytes = Uint8List.fromList(_transparentPngBytes);
    final fakeDailyNoteService = _FakeDailyNoteService();
    final fakeHomeOverviewService = _FakeHomeOverviewService();
    final fakePendingImageService = _FakePendingImageService();
    final localDataState = _testLocalDataState();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomePage(
          localDataState: localDataState,
          dailyNoteService: fakeDailyNoteService,
          homeOverviewService: fakeHomeOverviewService,
          pendingImageService: fakePendingImageService,
          imageAttachmentPicker: () async => [
            PendingImage(
              id: 'picked-image',
              bytes: imageBytes,
              name: 'screenshot.png',
              extension: 'png',
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
    await _pumpUntil(
      tester,
      () => fakeDailyNoteService.savedNote != null,
      'daily note with attachments to be saved',
    );

    expect(fakeDailyNoteService.savedNote, isNotNull);
    expect(fakePendingImageService.savedBytes.single, imageBytes);
    final rawInput = fakeDailyNoteService.savedNote?.rawInput ?? '';
    expect(rawInput, contains('整理附件内容'));
    expect(rawInput, contains('图片：'));
    expect(rawInput, contains('![screenshot.png](images/screenshot.png)'));
    expect(rawInput, contains('附件：'));
    expect(rawInput, contains('[文件] spec.pdf'));
    expect(rawInput, contains('/Users/demo/Documents/spec.pdf'));
  });

  testWidgets('home paste image saves markdown path on submit', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final imageBytes = Uint8List.fromList(_transparentPngBytes);
    final fakeDailyNoteService = _FakeDailyNoteService();
    final fakeHomeOverviewService = _FakeHomeOverviewService();
    final fakePendingImageService = _FakePendingImageService();
    final localDataState = _testLocalDataState();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomePage(
          localDataState: localDataState,
          dailyNoteService: fakeDailyNoteService,
          homeOverviewService: fakeHomeOverviewService,
          pendingImageClipboardService: _FakePendingImageClipboardService(
            imageBytes,
          ),
          pendingImageService: fakePendingImageService,
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.text('图片 · clipboard.png'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '整理带图日报');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('home-smart-generate-button')));
    await _pumpUntil(
      tester,
      () => fakeDailyNoteService.savedNote != null,
      'daily note with pasted image to be saved',
    );

    expect(fakeDailyNoteService.savedNote, isNotNull);
    expect(
      fakePendingImageService.notePath,
      contains(_joinPath('notes', 'daily')),
    );
    expect(fakePendingImageService.notePath, endsWith('.md'));
    expect(fakePendingImageService.savedBytes.single, imageBytes);
    final rawInput = fakeDailyNoteService.savedNote?.rawInput ?? '';
    expect(rawInput, contains('整理带图日报'));
    expect(rawInput, contains('![clipboard.png](images/clipboard.png)'));
    expect(find.text('图片 · clipboard.png'), findsNothing);
  });

  testWidgets('home image markdown keeps readable non-ascii relative path', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final imageBytes = Uint8List.fromList(_transparentPngBytes);
    final fakeDailyNoteService = _FakeDailyNoteService();
    final fakeHomeOverviewService = _FakeHomeOverviewService();
    final fakePendingImageService = _FakePendingImageService();
    final localDataState = _testLocalDataState();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomePage(
          localDataState: localDataState,
          dailyNoteService: fakeDailyNoteService,
          homeOverviewService: fakeHomeOverviewService,
          pendingImageClipboardService: _FakePendingImageClipboardService(
            imageBytes,
            name: '【哲风壁纸】庭院雨景-树木-清新.png',
          ),
          pendingImageService: fakePendingImageService,
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('home-smart-generate-button')));
    await _pumpUntil(
      tester,
      () => fakeDailyNoteService.savedNote != null,
      'daily note with non-ascii image to be saved',
    );

    expect(fakeDailyNoteService.savedNote, isNotNull);
    final rawInput = fakeDailyNoteService.savedNote?.rawInput ?? '';
    expect(
      rawInput,
      contains('![【哲风壁纸】庭院雨景-树木-清新.png](images/【哲风壁纸】庭院雨景-树木-清新.png)'),
    );
  });

  testWidgets('home income stays in sync with desktop widget controller', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final localDataState = _testLocalDataState(
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

  testWidgets('desktop widget controller flushes pending income on shutdown', (
    WidgetTester tester,
  ) async {
    final statsService = _RecordingStatsService();
    final localDataState = _testLocalDataState(
      config: AppConfig.defaults().copyWith(
        dailyWorkHours: 1,
        dailySalary: 3600,
      ),
    );
    final controller = DesktopWidgetController(
      statsService: statsService,
      tickDuration: const Duration(seconds: 1),
    )..attach(localDataState);

    await tester.pump(const Duration(seconds: 30));
    await controller.flush();

    expect(statsService.recordedWorkSeconds, [30]);
    expect(statsService.recordedCoins.single, 30);

    controller.dispose();
  });
}

LocalDataState _testLocalDataState({AppConfig? config}) {
  final tempDir = Directory.systemTemp.createTempSync(
    'spring_note_widget_test_',
  );
  addTearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
  final notes = _joinPath(tempDir.path, 'notes');
  return LocalDataState(
    dataDirectory: tempDir.path,
    configPath: _joinPath(tempDir.path, 'config.json'),
    dailyNotesDirectory: _joinPath(notes, 'daily'),
    weeklyNotesDirectory: _joinPath(notes, 'weekly'),
    monthlyNotesDirectory: _joinPath(notes, 'monthly'),
    config: config ?? AppConfig.defaults(),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
  String description,
) async {
  for (var index = 0; index < 20; index++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) {
      return;
    }
  }
  fail('Timed out waiting for $description.');
}

String _joinPath(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
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

class _FakePendingImageClipboardService extends PendingImageClipboardService {
  const _FakePendingImageClipboardService(
    this.bytes, {
    this.name = 'clipboard.png',
  });

  final Uint8List bytes;
  final String name;

  @override
  Future<List<PendingImage>> readPendingImages() async {
    return [
      PendingImage(
        id: 'test-image',
        bytes: bytes,
        name: name,
        extension: 'png',
      ),
    ];
  }
}

class _FakePendingImageService extends PendingImageService {
  String? notePath;
  final List<Uint8List> savedBytes = [];

  @override
  Future<List<SavedPendingImage>> saveForDailyNote({
    required String notePath,
    required List<PendingImage> images,
  }) async {
    this.notePath = notePath;
    savedBytes.addAll(images.map((image) => image.bytes));
    return images
        .map(
          (image) => SavedPendingImage(
            path: '$notePath.images\\${image.name}',
            name: image.name,
            markdownPath: 'images/${image.name}',
          ),
        )
        .toList();
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

class _RecordingStatsService extends StatsService {
  final List<int> recordedWorkSeconds = [];
  final List<double> recordedCoins = [];

  @override
  Future<rust_stats.StatsSnapshot> readSnapshot({
    required LocalDataState localDataState,
    required DateTime start,
    required DateTime end,
  }) async {
    return StatsService.emptySnapshot;
  }

  @override
  Future<void> recordWorkTime({
    required String appDataDir,
    required int workSeconds,
    required double coins,
  }) async {
    recordedWorkSeconds.add(workSeconds);
    recordedCoins.add(coins);
  }
}

const _transparentPngBytes = [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  248,
  15,
  4,
  0,
  9,
  251,
  3,
  253,
  167,
  132,
  129,
  130,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];
