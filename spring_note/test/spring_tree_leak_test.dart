import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/note_file.dart';
import 'package:spring_note/core/services/note_service.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/notes/notes_page.dart';

const _notePath = 'D:\\Temp\\SpringNote\\notes\\daily\\2026-06-18.md';

const _markdown = '''
# 内存测试

```springtree
- 中心主题
  - 分支 A
    - 叶子 A1
    - 叶子 A2
  - 分支 B
  - 分支 C
```

正文段落。
''';

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
    return [
      for (final entry in contents.entries)
        if (entry.key.startsWith(directoryPath))
          _noteFile(entry.key, entry.value, kind),
    ];
  }

  @override
  Future<NoteFile> ensureCurrentMarkdownFile({
    required String directoryPath,
    required NoteKind kind,
    DateTime? now,
  }) async {
    contents.putIfAbsent(_notePath, () => _markdown);
    return _noteFile(_notePath, contents[_notePath]!, kind);
  }

  @override
  Future<String> readMarkdown(String path) async => contents[path] ?? '';

  @override
  Future<void> writeMarkdown(String path, String content) async {
    contents[path] = content;
  }

  NoteFile _noteFile(String path, String content, NoteKind kind) {
    final name = path.split('\\').last;
    return NoteFile(
      path: path,
      name: name,
      title: name,
      modifiedAt: DateTime(2026, 6, 18, 12),
      kind: kind,
      preview: '',
      searchText: content,
    );
  }
}

void main() {
  testWidgets('notes workspace mode switches release springtree resources', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final noteService = _MemoryNoteService({_notePath: _markdown});

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotesPage(
          localDataState: _localDataState,
          noteService: noteService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var cycle = 0; cycle < 6; cycle++) {
      await tester.tap(
        find.byKey(const ValueKey('notes-workspace-mode-preview')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notes-workspace-mode-edit')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('notes-workspace-mode-split')),
      );
      await tester.pumpAndSettle();
    }
  });
}
