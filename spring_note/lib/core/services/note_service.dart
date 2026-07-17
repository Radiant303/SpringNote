import 'dart:io';

import '../models/note_file.dart';
import 'note_storage_coordinator.dart';

class NoteService {
  const NoteService();

  Future<List<NoteFile>> listMarkdownFiles({
    required String directoryPath,
    required NoteKind kind,
  }) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final files = await directory
        .list()
        .where(
          (entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.md'),
        )
        .cast<File>()
        .toList();

    final noteFiles = <NoteFile>[];
    for (final file in files) {
      final stat = await file.stat();
      final content = await readMarkdown(file.path);
      final name = _fileName(file.path);
      noteFiles.add(
        NoteFile(
          path: file.path,
          name: name,
          title: _titleFromContent(content, name),
          modifiedAt: stat.modified,
          kind: kind,
          preview: _previewFromContent(content),
          searchText: _searchTextFromContent(content),
        ),
      );
    }

    noteFiles.sort((a, b) => b.name.compareTo(a.name));
    return noteFiles;
  }

  Future<NoteFile> ensureCurrentMarkdownFile({
    required String directoryPath,
    required NoteKind kind,
    DateTime? now,
  }) async {
    final date = now ?? DateTime.now();
    final name = switch (kind) {
      NoteKind.daily => _formatDate(date),
      NoteKind.weekly => _formatIsoWeek(date),
      NoteKind.monthly =>
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}',
    };
    final path = _join(directoryPath, '$name.md');
    final title = '$name ${kind.suffix}';

    await ensureMarkdownFile(path, defaultContent: '# $title\n\n');
    final stat = await File(path).stat();
    final content = await readMarkdown(path);

    return NoteFile(
      path: path,
      name: '$name.md',
      title: _titleFromContent(content, '$name.md'),
      modifiedAt: stat.modified,
      kind: kind,
      preview: _previewFromContent(content),
      searchText: _searchTextFromContent(content),
    );
  }

  Future<String> readMarkdown(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<void> writeMarkdown(String path, String content) async {
    await NoteStorageCoordinator.runForManagedNotePath(path, () async {
      final file = File(path);
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await file.writeAsString(content);
    });
  }

  Future<bool> refreshMarkdownIndex({
    required String directoryPath,
    required NoteKind kind,
  }) async {
    return false;
  }

  Future<void> indexMarkdownFile({
    required String directoryPath,
    required NoteKind kind,
    required String notePath,
  }) async {}

  NoteFile describeMarkdown({
    required NoteFile note,
    required String content,
    DateTime? modifiedAt,
  }) {
    return NoteFile(
      path: note.path,
      name: note.name,
      title: _titleFromContent(content, note.name),
      modifiedAt: modifiedAt ?? DateTime.now(),
      kind: note.kind,
      preview: _previewFromContent(content),
      searchText: _searchTextFromContent(content),
    );
  }

  Future<List<NoteFile>> searchMarkdownFiles({
    required String directoryPath,
    required NoteKind kind,
    required String query,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.runes.length < 2) {
      return const [];
    }

    final notes = await listMarkdownFiles(
      directoryPath: directoryPath,
      kind: kind,
    );
    final results = <NoteFile>[];
    for (final note in notes) {
      final content = await readMarkdown(note.path);
      if (content.toLowerCase().contains(normalizedQuery) ||
          note.name.toLowerCase().contains(normalizedQuery) ||
          note.title.toLowerCase().contains(normalizedQuery)) {
        results.add(note);
      }
    }
    return results;
  }

  Future<File> ensureMarkdownFile(
    String path, {
    String defaultContent = '',
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      await writeMarkdown(path, defaultContent);
    }
    return file;
  }

  String _fileName(String path) {
    return path.split(RegExp(r'[\\/]')).last;
  }

  String _titleFromContent(String content, String fallbackName) {
    for (final line in content.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        return trimmed.substring(2).trim();
      }
      if (trimmed.isNotEmpty) {
        return trimmed.length > 28 ? '${trimmed.substring(0, 28)}...' : trimmed;
      }
    }
    return fallbackName.replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
  }

  String _previewFromContent(String content) {
    final text = _bodyTextFromContent(content, skipFirstLine: true);
    if (text.length <= 72) {
      return text;
    }
    return '${text.substring(0, 72)}...';
  }

  String _searchTextFromContent(String content) {
    return _bodyTextFromContent(content);
  }

  String _bodyTextFromContent(String content, {bool skipFirstLine = false}) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim().replaceFirst(RegExp(r'^#{1,6}\s+'), ''))
        .where((line) => line.isNotEmpty)
        .toList();
    return (skipFirstLine ? lines.skip(1) : lines).join(' ');
  }

  String _join(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  int _isoWeekNumber(DateTime date) {
    final start = _startOfWeek(date);
    final isoYear = start.add(const Duration(days: 3)).year;
    final first = _startOfWeek(DateTime(isoYear, 1, 4));
    return (start.difference(first).inDays ~/ 7) + 1;
  }

  String _formatIsoWeek(DateTime date) {
    final start = _startOfWeek(date);
    final isoYear = start.add(const Duration(days: 3)).year;
    final week = _isoWeekNumber(date);
    return '${isoYear.toString().padLeft(4, '0')}-W${week.toString().padLeft(2, '0')}';
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }
}
