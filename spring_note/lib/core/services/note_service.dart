import 'dart:io';

import '../models/note_file.dart';

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
      NoteKind.weekly =>
        '${date.year}-W${_isoWeekNumber(date).toString().padLeft(2, '0')}',
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
    final file = File(path);
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsString(content);
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
    final text = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim().replaceFirst(RegExp(r'^#{1,6}\s+'), ''))
        .where((line) => line.isNotEmpty)
        .skip(1)
        .join(' ');
    if (text.length <= 72) {
      return text;
    }
    return '${text.substring(0, 72)}...';
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
    final normalized = DateTime.utc(date.year, date.month, date.day);
    final thursday = normalized.add(Duration(days: 4 - normalized.weekday));
    final firstThursday = DateTime.utc(thursday.year, 1, 4);
    return 1 + thursday.difference(firstThursday).inDays ~/ 7;
  }
}
