import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/note_file.dart';
import 'package:spring_note/core/services/note_service.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/notes/notes_page.dart';

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

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周报').last);
    await tester.pump();
    await tester.pump();

    expect(find.text('周报'), findsWidgets);
  });
}

final _localDataState = LocalDataState(
  dataDirectory: 'D:\\Temp\\SpringNote',
  configPath: 'D:\\Temp\\SpringNote\\config.json',
  dailyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\daily',
  weeklyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\weekly',
  monthlyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\monthly',
  config: AppConfig.defaults(),
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
