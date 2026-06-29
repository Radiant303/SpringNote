import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/cloud_sync_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/model_config.dart';
import 'package:spring_note/core/models/note_file.dart';
import 'package:spring_note/core/models/provider_config.dart';
import 'package:spring_note/core/services/ai_client_service.dart';
import 'package:spring_note/core/services/clipboard_image_service.dart';
import 'package:spring_note/core/services/cloud_sync_service.dart';
import 'package:spring_note/core/services/note_service.dart';
import 'package:spring_note/core/services/pasted_image_service.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/notes/notes_page.dart';
import 'package:spring_note/src/rust/cloud_sync.dart' as rust_model;

void main() {
  testWidgets('notes page loads edits previews and saves markdown', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md':
          '# 2026-06-18 日报\n\n- 初始内容',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _localDataState,
          noteService: noteService,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Markdown Source · 源码编辑'), findsOneWidget);
    expect(find.text('2026-06-18 日报'), findsWidgets);

    const edited = r'''
# 编辑后的日报

这是一段包含 `inline code` 和 [链接](https://example.com) 的正文。

行内公式 $E = mc^2$ 应该可读渲染。

$$
\\frac{a}{b} + \\alpha_1 = \\sum_{i=1}^{n} x_i
$$

> 这是引用内容

1. 第一项
2. 第二项

- 无序项

```dart
final value = 1;
```

| 模块 | 状态 |
| --- | --- |
| 预览 | 正常 |
''';

    await tester.enterText(find.byType(TextField).last, edited);
    await tester.pump();
    await tester.pump();

    expect(find.text('编辑后的日报'), findsWidgets);
    expect(find.text('这是引用内容', findRichText: true), findsOneWidget);
    expect(find.text('第一项', findRichText: true), findsOneWidget);
    expect(find.text('无序项', findRichText: true), findsOneWidget);
    expect(find.textContaining('E = mc', findRichText: true), findsWidgets);
    expect(find.text('dart'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(noteService.contents.values.single, edited);
  });

  testWidgets('notes page checks focused note every three seconds', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notePath = 'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md';
    final noteService = _MemoryNoteService({notePath: '# 初始日报\n'});
    final cloudSyncApi = _FakeCloudSyncRustApi();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _cloudSyncLocalDataState,
          noteService: noteService,
          cloudSyncService: CloudSyncService(api: cloudSyncApi),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(cloudSyncApi.uploadCalls, 0);

    const edited = '# 修改后的日报\n\n自动同步这一篇。';
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, edited);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(cloudSyncApi.uploadCalls, 1);
    expect(cloudSyncApi.uploadRequests.single.notePath, notePath);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(cloudSyncApi.uploadCalls, 2);
  });

  testWidgets('notes page uploads changed note once when editor loses focus', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notePath = 'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md';
    final noteService = _MemoryNoteService({notePath: '# 初始日报\n'});
    final cloudSyncApi = _FakeCloudSyncRustApi();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _cloudSyncLocalDataState,
          noteService: noteService,
          cloudSyncService: CloudSyncService(api: cloudSyncApi),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '# 失焦同步\n');
    await tester.pump();
    await tester.pump();
    expect(cloudSyncApi.uploadCalls, 0);

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.pump();

    expect(cloudSyncApi.uploadCalls, 1);
    expect(cloudSyncApi.uploadRequests.single.notePath, notePath);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(cloudSyncApi.uploadCalls, 1);
  });

  testWidgets('notes page skips auto upload when real-time sync is disabled', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 初始日报\n',
    });
    final cloudSyncApi = _FakeCloudSyncRustApi();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _cloudSyncWithoutRealTimeLocalDataState,
          noteService: noteService,
          cloudSyncService: CloudSyncService(api: cloudSyncApi),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, '# 本地修改\n');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(cloudSyncApi.uploadCalls, 0);
  });

  testWidgets('notes page switches note kind from menu', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n',
      'D:\\Temp\\SpringNote\\notes\\weekly\\2026-W25.md': '# 周报\n',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _localDataState,
          noteService: noteService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周报').last);
    await tester.pump();
    await tester.pump();

    expect(find.text('周报'), findsWidgets);
  });

  testWidgets('notes editor debounces FIM and accepts full prediction', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n',
    });
    final aiClientService = _FakeAiClientService('补全文字\n第二行');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _fimLocalDataState,
          noteService: noteService,
          aiClientService: aiClientService,
        ),
      ),
    );
    await tester.pump();

    final editor = find.byType(TextField).last;
    await tester.enterText(editor, '# 日报\n我完成');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.enterText(editor, '# 日报\n我完成了');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.enterText(editor, '# 日报\n我完成了登录');
    await tester.pump(const Duration(milliseconds: 350));

    expect(aiClientService.calls, 1);
    expect(aiClientService.lastPrompt, '# 日报\n我完成了登录');
    expect(_editablePlainText(tester), contains('补全文字'));
    expect(_editableRealText(tester), isNot(contains('补全文字')));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(noteService.contents.values.single, contains('我完成了登录补全文字\n第二行'));
  });

  testWidgets('notes editor accepts one predicted line with Ctrl+L', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n',
    });
    final aiClientService = _FakeAiClientService('第一行\n第二行');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _fimLocalDataState,
          noteService: noteService,
          aiClientService: aiClientService,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, '# 日报\n前缀');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 500));

    expect(noteService.contents.values.single, '# 日报\n前缀第一行\n');
    expect(aiClientService.calls, 1);
    expect(_editablePlainText(tester), contains('第二行'));
    expect(_editableRealText(tester), isNot(contains('第二行')));
  });

  testWidgets('notes editor accepts one visible character with Ctrl+K', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n',
    });
    final aiClientService = _FakeAiClientService('你好');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _fimLocalDataState,
          noteService: noteService,
          aiClientService: aiClientService,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, '# 日报\n前缀');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 500));

    expect(aiClientService.calls, 1);
    expect(noteService.contents.values.single, '# 日报\n前缀你');
    expect(_editablePlainText(tester), contains('好'));
    expect(_editableRealText(tester), isNot(contains('好')));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(noteService.contents.values.single, '# 日报\n前缀你好');
  });

  testWidgets('notes editor inserts tab when there is no FIM prediction', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _localDataState,
          noteService: noteService,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, '# 日报\n前缀');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(noteService.contents.values.single, '# 日报\n前缀\t');
  });

  testWidgets('notes editor inserts selected image markdown', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const imagePath = 'D:\\Temp\\SpringNote\\assets\\screenshot final.png';
    final pastedImageService = _MemoryPastedImageService(
      const SavedPastedImage(
        path: 'D:\\Temp\\SpringNote\\notes\\daily\\images\\screenshot #1.png',
        name: 'screenshot [final](copy)\ncopy.png',
      ),
    );
    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n前缀',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _localDataState,
          noteService: noteService,
          pastedImageService: pastedImageService,
          imagePicker: () async => const [
            NoteImageAttachment(path: imagePath, name: 'screenshot final.png'),
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('插入图片'));
    await tester.pump();
    await tester.pump();

    final expectedImage =
        r'![screenshot \[final\]\(copy\) copy.png]'
        '(images/screenshot%20%231.png)';
    expect(noteService.contents.values.single, '# 日报\n前缀\n$expectedImage');
    expect(pastedImageService.notePath, contains('2026-06-18.md'));
    expect(pastedImageService.sourcePath, imagePath);
    expect(pastedImageService.sourceName, 'screenshot final.png');
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).last)
          .focusNode
          .hasFocus,
      isTrue,
    );
    expect(find.text('已插入图片'), findsOneWidget);
  });

  testWidgets('notes editor ignores empty image picker result', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pastedImageService = _MemoryPastedImageService(
      const SavedPastedImage(path: 'unused', name: 'unused.png'),
    );
    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n前缀',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _localDataState,
          noteService: noteService,
          pastedImageService: pastedImageService,
          imagePicker: () async => const [],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('插入图片'));
    await tester.pump();
    await tester.pump();

    expect(noteService.contents.values.single, '# 日报\n前缀');
    expect(pastedImageService.copyCalls, 0);
    expect(find.text('已插入图片'), findsNothing);
    expect(find.text('已取消选择图片'), findsOneWidget);
    expect(find.text('无法插入图片，请重新选择文件。'), findsNothing);
  });

  testWidgets('notes editor shows error when image picker fails', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n前缀',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _localDataState,
          noteService: noteService,
          imagePicker: () async => throw StateError('picker failed'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('插入图片'));
    await tester.pump();
    await tester.pump();

    expect(noteService.contents.values.single, '# 日报\n前缀');
    expect(find.text('无法插入图片，请重新选择文件。'), findsOneWidget);
  });

  testWidgets(
    'notes editor ignores repeated image insert while picker is open',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final pickerCompleter = Completer<List<NoteImageAttachment>>();
      var pickerCalls = 0;
      final pastedImageService = _MemoryPastedImageService(
        const SavedPastedImage(
          path: 'D:\\Temp\\SpringNote\\notes\\daily\\images\\screenshot.png',
          name: 'screenshot.png',
        ),
      );
      final noteService = _MemoryNoteService({
        'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n前缀',
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: NotesPage(
            localDataState: _localDataState,
            noteService: noteService,
            pastedImageService: pastedImageService,
            imagePicker: () {
              pickerCalls++;
              return pickerCompleter.future;
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('插入图片'));
      await tester.pump();
      await tester.tap(find.byTooltip('插入图片'));
      await tester.pump();

      expect(pickerCalls, 1);

      pickerCompleter.complete(const [
        NoteImageAttachment(
          path: 'D:\\Temp\\SpringNote\\assets\\screenshot.png',
          name: 'screenshot.png',
        ),
      ]);
      await tester.pump();
      await tester.pump();

      expect(pastedImageService.copyCalls, 1);
      expect(noteService.contents.values.single, contains('![screenshot.png]'));
    },
  );

  testWidgets(
    'notes editor saves selected images under migrated note directory',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const imagePath = 'D:\\Temp\\SpringNote\\assets\\screenshot.png';
      final migratedState = _localDataState.copyWith(
        dataDirectory: 'E:\\SpringNoteData',
        configPath: 'E:\\SpringNoteData\\config.json',
        dailyNotesDirectory: 'E:\\SpringNoteData\\notes\\daily',
        weeklyNotesDirectory: 'E:\\SpringNoteData\\notes\\weekly',
        monthlyNotesDirectory: 'E:\\SpringNoteData\\notes\\monthly',
      );
      final pastedImageService = _MemoryPastedImageService(
        const SavedPastedImage(
          path: 'E:\\SpringNoteData\\notes\\daily\\images\\screenshot.png',
          name: 'screenshot.png',
        ),
      );
      final noteService = _MemoryNoteService({
        'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 旧目录\n',
        'E:\\SpringNoteData\\notes\\daily\\2026-06-18.md': '# 迁移后\n',
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: NotesPage(
            localDataState: _localDataState,
            noteService: noteService,
            pastedImageService: pastedImageService,
            imagePicker: () async => const [
              NoteImageAttachment(path: imagePath, name: 'screenshot.png'),
            ],
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: NotesPage(
            localDataState: migratedState,
            noteService: noteService,
            pastedImageService: pastedImageService,
            imagePicker: () async => const [
              NoteImageAttachment(path: imagePath, name: 'screenshot.png'),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('插入图片'));
      await tester.pump();
      await tester.pump();

      expect(
        pastedImageService.notePath,
        'E:\\SpringNoteData\\notes\\daily\\2026-06-18.md',
      );
      expect(
        noteService.contents['E:\\SpringNoteData\\notes\\daily\\2026-06-18.md'],
        contains('![screenshot.png](images/screenshot.png)'),
      );
      expect(
        noteService
            .contents['D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md'],
        '# 旧目录\n',
      );
    },
  );

  testWidgets('notes editor pastes clipboard image as saved markdown link', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final imageBytes = Uint8List.fromList([1, 2, 3, 4]);
    final clipboardImageService = _FakeClipboardImageService(imageBytes);
    final pastedImageService = _MemoryPastedImageService(
      const SavedPastedImage(
        path:
            'D:\\Temp\\SpringNote\\notes\\daily\\images\\pasted-image-20260618-120000-000.png',
        name: 'pasted-image-20260618-120000-000.png',
      ),
    );
    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n前缀',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _localDataState,
          noteService: noteService,
          clipboardImageService: clipboardImageService,
          pastedImageService: pastedImageService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    final expectedImage =
        '![pasted-image-20260618-120000-000.png]'
        '(images/pasted-image-20260618-120000-000.png)';
    expect(noteService.contents.values.single, '# 日报\n前缀\n$expectedImage');
    expect(clipboardImageService.calls, 1);
    expect(pastedImageService.savedBytes, imageBytes);
    expect(pastedImageService.notePath, contains('2026-06-18.md'));
    expect(find.text('已粘贴图片'), findsOneWidget);
  });

  testWidgets('notes editor keeps text paste when clipboard has no image', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        expect(call.arguments, Clipboard.kTextPlain);
        return {'text': '粘贴文字'};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final clipboardImageService = _FakeClipboardImageService(null);
    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n前缀',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _localDataState,
          noteService: noteService,
          clipboardImageService: clipboardImageService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    expect(noteService.contents.values.single, '# 日报\n前缀粘贴文字');
    expect(clipboardImageService.calls, 1);
  });

  testWidgets('notes editor ignores text clipboard errors when pasting', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        throw PlatformException(code: 'clipboard-error');
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final clipboardImageService = _FakeClipboardImageService(null);
    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n前缀',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _localDataState,
          noteService: noteService,
          clipboardImageService: clipboardImageService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(noteService.contents.values.single, '# 日报\n前缀');
    expect(clipboardImageService.calls, 1);
    expect(find.text('无法读取剪贴板文字。'), findsOneWidget);
  });

  testWidgets('notes editor shows FIM unavailable reason', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final noteService = _MemoryNoteService({
      'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md': '# 日报\n',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _localDataState,
          noteService: noteService,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, '# 日报\n前缀');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.textContaining('FIM 未触发：未选择编辑补全模型'), findsOneWidget);
  });
}

String _editablePlainText(WidgetTester tester) {
  final finder = find.byType(EditableText).last;
  final editableText = tester.widget<EditableText>(finder);
  final context = tester.element(finder);
  return editableText.controller
      .buildTextSpan(
        context: context,
        style: editableText.style,
        withComposing: false,
      )
      .toPlainText();
}

String _editableRealText(WidgetTester tester) {
  final editableText = tester.widget<EditableText>(
    find.byType(EditableText).last,
  );
  return editableText.controller.text;
}

final _localDataState = LocalDataState(
  dataDirectory: 'D:\\Temp\\SpringNote',
  configPath: 'D:\\Temp\\SpringNote\\config.json',
  dailyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\daily',
  weeklyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\weekly',
  monthlyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\monthly',
  config: AppConfig.defaults(),
);

final _cloudSyncLocalDataState = _localDataState.copyWith(
  config: _localDataState.config.copyWith(
    cloudSync: const CloudSyncConfig(
      enabled: true,
      serverUrl: 'https://example.com/dav/',
      username: 'user',
      password: 'token',
      syncOnStartup: false,
      realTimeSync: true,
      lastSyncedAt: null,
    ),
  ),
);

final _cloudSyncWithoutRealTimeLocalDataState = _localDataState.copyWith(
  config: _localDataState.config.copyWith(
    cloudSync: const CloudSyncConfig(
      enabled: true,
      serverUrl: 'https://example.com/dav/',
      username: 'user',
      password: 'token',
      syncOnStartup: false,
      realTimeSync: false,
      lastSyncedAt: null,
    ),
  ),
);

final _fimLocalDataState = LocalDataState(
  dataDirectory: 'D:\\Temp\\SpringNote',
  configPath: 'D:\\Temp\\SpringNote\\config.json',
  dailyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\daily',
  weeklyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\weekly',
  monthlyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\monthly',
  config: AppConfig.defaults().copyWith(
    providers: const [
      ProviderConfig(
        id: 'openai-compatible',
        enabled: true,
        name: 'OpenAI Compatible',
        protocol: 'openaiCompatible',
        apiKey: 'test-key',
        baseUrl: 'https://api.example.com/v1',
        apiPath: '/completions',
        models: [
          ModelConfig(
            modelId: 'fim-model',
            displayName: 'FIM Model',
            modelTypes: ['completion'],
          ),
        ],
      ),
    ],
    defaultModels: {
      'intelligentGenerationModel': null,
      'editCompletionModel': 'fim-model',
      'memoryBookModel': null,
    },
  ),
);

class _MemoryNoteService extends NoteService {
  _MemoryNoteService(this.contents);

  final Map<String, String> contents;

  @override
  Future<List<NoteFile>> listMarkdownFiles({
    required String directoryPath,
    required NoteKind kind,
  }) async {
    final files =
        contents.entries
            .where((entry) => entry.key.startsWith(directoryPath))
            .map((entry) => _noteFile(entry.key, entry.value, kind))
            .toList()
          ..sort((a, b) => b.name.compareTo(a.name));
    return files;
  }

  @override
  Future<NoteFile> ensureCurrentMarkdownFile({
    required String directoryPath,
    required NoteKind kind,
    DateTime? now,
  }) async {
    final name = switch (kind) {
      NoteKind.daily => '2026-06-18.md',
      NoteKind.weekly => '2026-W25.md',
      NoteKind.monthly => '2026-06.md',
    };
    final path = '$directoryPath\\$name';
    contents.putIfAbsent(path, () => '# ${kind.label}\n');
    return _noteFile(path, contents[path]!, kind);
  }

  @override
  Future<String> readMarkdown(String path) async {
    return contents[path] ?? '';
  }

  @override
  Future<void> writeMarkdown(String path, String content) async {
    contents[path] = content;
  }

  NoteFile _noteFile(String path, String content, NoteKind kind) {
    final name = path.split('\\').last;
    final title = content
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => name)
        .replaceFirst(RegExp(r'^#\s+'), '');
    return NoteFile(
      path: path,
      name: name,
      title: title,
      modifiedAt: DateTime(2026, 6, 18, 12, 0),
      kind: kind,
      preview: content.replaceAll('\n', ' '),
    );
  }
}

class _FakeCloudSyncRustApi extends CloudSyncRustApi {
  int uploadCalls = 0;
  final List<rust_model.CloudSyncNoteUploadRequest> uploadRequests = [];

  @override
  Future<rust_model.CloudSyncResult> uploadNote(
    rust_model.CloudSyncNoteUploadRequest request,
  ) async {
    uploadCalls++;
    uploadRequests.add(request);
    return const rust_model.CloudSyncResult(
      ok: true,
      message: 'ok',
      uploaded: 1,
      downloaded: 0,
      conflicts: 0,
      syncedAt: '2026-06-29T00:00:00+08:00',
      errorCode: '',
      needsDeleteConfirmation: false,
      pendingDeleteLocal: [],
      pendingDeleteRemote: [],
      needsDeleteModifyConfirmation: false,
      pendingDeleteModifyConflicts: [],
    );
  }
}

class _FakeAiClientService extends AiClientService {
  _FakeAiClientService(this.prediction);

  final String prediction;
  int get calls => _calls;
  String get lastPrompt => _lastPrompt;

  int _calls = 0;
  String _lastPrompt = '';

  @override
  Future<({String? content, String? error})> fimCompleteMarkdown({
    required String appDataDir,
    required AppConfig config,
    required String prompt,
    required String suffix,
  }) async {
    _calls++;
    _lastPrompt = prompt;
    return (content: prediction, error: null);
  }
}

class _FakeClipboardImageService extends ClipboardImageService {
  _FakeClipboardImageService(this.imageBytes);

  final Uint8List? imageBytes;
  int calls = 0;
  int fileCalls = 0;

  @override
  Future<List<String>> readImageFiles() async {
    fileCalls++;
    return const [];
  }

  @override
  Future<Uint8List?> readPngImage() async {
    calls++;
    return imageBytes;
  }
}

class _MemoryPastedImageService extends PastedImageService {
  _MemoryPastedImageService(this.savedImage);

  final SavedPastedImage savedImage;
  int copyCalls = 0;
  Uint8List? savedBytes;
  String? notePath;
  String? sourcePath;
  String? sourceName;

  @override
  Future<SavedPastedImage> savePngForNote({
    required String notePath,
    required Uint8List pngBytes,
    DateTime? now,
  }) async {
    this.notePath = notePath;
    savedBytes = pngBytes;
    return savedImage;
  }

  @override
  Future<SavedPastedImage> copyImageFileForNote({
    required String notePath,
    required String sourcePath,
    required String sourceName,
  }) async {
    copyCalls++;
    this.notePath = notePath;
    this.sourcePath = sourcePath;
    this.sourceName = sourceName;
    return savedImage;
  }
}
