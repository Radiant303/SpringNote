import 'dart:io';

import '../models/structured_work_note.dart';
import 'note_service.dart';

class DailyNoteService {
  const DailyNoteService({this.noteService = const NoteService()});

  final NoteService noteService;

  Future<String> mergeStructuredNote({
    required String dailyNotesDirectory,
    required DateTime date,
    required StructuredWorkNote note,
  }) async {
    final path = dailyNotePath(dailyNotesDirectory, date);
    final existing = await noteService.readMarkdown(path);
    final merged = _mergeMarkdown(existing, date, note);
    await noteService.writeMarkdown(path, merged);
    return path;
  }

  String dailyNotePath(String dailyNotesDirectory, DateTime date) {
    final separator = Platform.pathSeparator;
    final directory = dailyNotesDirectory.endsWith(separator)
        ? dailyNotesDirectory.substring(0, dailyNotesDirectory.length - 1)
        : dailyNotesDirectory;
    return '$directory$separator${_formatDate(date)}.md';
  }

  String _mergeMarkdown(
    String existing,
    DateTime date,
    StructuredWorkNote note,
  ) {
    final buffer = StringBuffer();
    final trimmedExisting = existing.trim();

    if (trimmedExisting.isEmpty) {
      buffer.writeln('# ${_formatDate(date)} 日报');
    } else {
      buffer.writeln(trimmedExisting);
    }

    buffer
      ..writeln()
      ..writeln('## ${_formatTime(date)} 随手记录')
      ..writeln()
      ..writeln('### 原始记录')
      ..writeln()
      ..writeln(note.rawInput)
      ..writeln()
      ..writeln('### 完成事项');
    _writeItems(buffer, note.completed);
    buffer
      ..writeln()
      ..writeln('### 问题记录');
    _writeItems(buffer, note.issues);
    buffer
      ..writeln()
      ..writeln('### 明日计划');
    _writeItems(buffer, note.plans);

    return '${buffer.toString().trimRight()}\n';
  }

  void _writeItems(StringBuffer buffer, List<String> items) {
    if (items.isEmpty) {
      buffer.writeln('- 暂无');
      return;
    }

    for (final item in items) {
      buffer.writeln('- $item');
    }
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
