import 'dart:io';

import '../models/app_language.dart';
import '../models/local_data_state.dart';
import '../models/note_file.dart';
import 'ai_client_service.dart';
import 'note_service.dart';
import 'report_image_service.dart';

class StartupReportGenerationService {
  const StartupReportGenerationService({
    this.aiClientService = const AiClientService(),
    this.noteService = const NoteService(),
    this.reportImageService = const ReportImageService(),
  });

  final AiClientService aiClientService;
  final NoteService noteService;
  final ReportImageService reportImageService;

  Future<List<GeneratedReport>> generateMissingReports({
    required LocalDataState localDataState,
    DateTime? now,
  }) async {
    final today = _dateOnly(now ?? DateTime.now());
    final generated = <GeneratedReport>[];
    final currentWeekStart = _startOfWeek(today);
    final currentMonth = DateTime(today.year, today.month);

    final weekStarts = await _completedWeekStartsWithDailyNotes(
      localDataState,
      before: currentWeekStart,
    );
    for (final weekStart in weekStarts) {
      final weekly = await _generateWeekReport(
        localDataState: localDataState,
        weekStart: weekStart,
      );
      if (weekly != null) {
        generated.add(weekly);
      }
    }

    final months = await _completedMonthsWithWeeklyReports(
      localDataState,
      before: currentMonth,
    );
    for (final month in months) {
      final monthly = await _generateMonthReport(
        localDataState: localDataState,
        month: month,
      );
      if (monthly != null) {
        generated.add(monthly);
      }
    }

    return generated;
  }

  Future<GeneratedReport?> _generateWeekReport({
    required LocalDataState localDataState,
    required DateTime weekStart,
  }) async {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final label = _formatIsoWeek(weekStart);
    final targetPath = _join(localDataState.weeklyNotesDirectory, '$label.md');

    if (await _hasMeaningfulFile(targetPath)) {
      return null;
    }

    final source = await _dailySourceForWeek(localDataState, weekStart);
    if (source.trim().isEmpty) {
      return null;
    }

    // 与 Rust 重生成路径（report_regeneration.rs）的周期格式保持一致。
    final english = resolveAppLanguage(localDataState.config.language) == 'en';
    final images = await _collectReportImages(
      localDataState,
      localDataState.dailyNotesDirectory,
      _dailySourcePathsForWeekNewestFirst(localDataState, weekStart),
    );
    final markdown = await aiClientService.generateWeeklyReport(
      appDataDir: localDataState.dataDirectory,
      config: localDataState.config,
      sourceMarkdown: source,
      periodLabel: english
          ? '$label (${_formatDate(weekStart)} - ${_formatDate(weekEnd)})'
          : '$label（${_formatDate(weekStart)} 至 ${_formatDate(weekEnd)}）',
      images: images,
    );
    if (markdown == null) {
      return null;
    }

    await noteService.writeMarkdown(targetPath, markdown);
    return GeneratedReport(kind: NoteKind.weekly, path: targetPath);
  }

  Future<GeneratedReport?> _generateMonthReport({
    required LocalDataState localDataState,
    required DateTime month,
  }) async {
    final label = _formatMonth(month);
    final targetPath = _join(localDataState.monthlyNotesDirectory, '$label.md');

    if (await _hasMeaningfulFile(targetPath)) {
      return null;
    }

    final source = await _weeklySourceForMonth(localDataState, month);
    if (source.trim().isEmpty) {
      return null;
    }

    // 与 Rust 重生成路径（report_regeneration.rs）的周期格式保持一致。
    final english = resolveAppLanguage(localDataState.config.language) == 'en';
    final images = await _collectReportImages(
      localDataState,
      localDataState.weeklyNotesDirectory,
      await _weeklySourcePathsForMonthNewestFirst(localDataState, month),
    );
    final markdown = await aiClientService.generateMonthlyReport(
      appDataDir: localDataState.dataDirectory,
      config: localDataState.config,
      sourceMarkdown: source,
      periodLabel: english ? '$label Monthly Report' : '$label 月报',
      images: images,
    );
    if (markdown == null) {
      return null;
    }

    await noteService.writeMarkdown(targetPath, markdown);
    return GeneratedReport(kind: NoteKind.monthly, path: targetPath);
  }

  Future<List<DateTime>> _completedWeekStartsWithDailyNotes(
    LocalDataState localDataState, {
    required DateTime before,
  }) async {
    final weekStarts = <DateTime>{};
    final directory = Directory(localDataState.dailyNotesDirectory);
    if (!await directory.exists()) {
      return [];
    }

    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final date = _dailyDateFromPath(entity.path);
      if (date == null) {
        continue;
      }
      final weekStart = _startOfWeek(date);
      if (!weekStart.isBefore(before)) {
        continue;
      }
      final content = await _readMeaningfulMarkdown(entity.path);
      if (content == null) {
        continue;
      }
      weekStarts.add(weekStart);
    }

    return weekStarts.toList()..sort();
  }

  Future<List<DateTime>> _completedMonthsWithWeeklyReports(
    LocalDataState localDataState, {
    required DateTime before,
  }) async {
    final months = <DateTime>{};
    final directory = Directory(localDataState.weeklyNotesDirectory);
    if (!await directory.exists()) {
      return [];
    }

    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final weekStart = _weekStartFromPath(entity.path);
      if (weekStart == null) {
        continue;
      }
      final content = await _readMeaningfulMarkdown(entity.path);
      if (content == null) {
        continue;
      }
      for (var index = 0; index < 7; index++) {
        final date = weekStart.add(Duration(days: index));
        final month = DateTime(date.year, date.month);
        if (month.isBefore(before)) {
          months.add(month);
        }
      }
    }

    return months.toList()..sort();
  }

  Future<String> _dailySourceForWeek(
    LocalDataState localDataState,
    DateTime weekStart,
  ) async {
    final buffer = StringBuffer();
    for (var index = 0; index < 7; index++) {
      final date = weekStart.add(Duration(days: index));
      final path = _join(
        localDataState.dailyNotesDirectory,
        '${_formatDate(date)}.md',
      );
      final content = await _readMeaningfulMarkdown(path);
      if (content == null) {
        continue;
      }
      buffer
        ..writeln('## ${_formatDate(date)} 日报')
        ..writeln()
        ..writeln(content)
        ..writeln();
    }
    return buffer.toString().trimRight();
  }

  // 图片收集按日期从近到远，取最新引用的图片；文本聚合顺序保持不变。
  List<String> _dailySourcePathsForWeekNewestFirst(
    LocalDataState localDataState,
    DateTime weekStart,
  ) {
    return [
      for (var index = 6; index >= 0; index--)
        _join(
          localDataState.dailyNotesDirectory,
          '${_formatDate(weekStart.add(Duration(days: index)))}.md',
        ),
    ];
  }

  Future<List<String>> _weeklySourcePathsForMonthNewestFirst(
    LocalDataState localDataState,
    DateTime month,
  ) async {
    final monthStart = DateTime(month.year, month.month);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final paths = <String>[];
    for (
      var weekStart = _startOfWeek(monthStart);
      !weekStart.isAfter(monthEnd);
      weekStart = weekStart.add(const Duration(days: 7))
    ) {
      final label = _formatIsoWeek(weekStart);
      final upperPath = _join(
        localDataState.weeklyNotesDirectory,
        '$label.md',
      );
      // 与文本来源一致：大写文件不存在时回退到小写 w 文件名。
      paths.add(
        await File(upperPath).exists()
            ? upperPath
            : _join(
                localDataState.weeklyNotesDirectory,
                '${_lowercaseWeekLabel(label)}.md',
              ),
      );
    }
    return paths.reversed.toList();
  }

  Future<List<AiImageInput>> _collectReportImages(
    LocalDataState localDataState,
    String sourceNotesDirectory,
    List<String> notePathsNewestFirst,
  ) async {
    if (!aiClientService.reportImageInputAllowed(localDataState.config)) {
      return const [];
    }
    return reportImageService.collect(
      notePathsNewestFirst: notePathsNewestFirst,
      notesRootDirectory: Directory(sourceNotesDirectory).parent.path,
    );
  }

  Future<String> _weeklySourceForMonth(
    LocalDataState localDataState,
    DateTime month,
  ) async {
    final monthStart = DateTime(month.year, month.month);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final buffer = StringBuffer();

    for (
      var weekStart = _startOfWeek(monthStart);
      !weekStart.isAfter(monthEnd);
      weekStart = weekStart.add(const Duration(days: 7))
    ) {
      final label = _formatIsoWeek(weekStart);
      // 与 Rust 重生成路径（report_regeneration.rs）保持一致：兼容手工改为
      // 小写 w 的周报文件名（仅 Linux 等大小写敏感文件系统上才会体现差异）。
      final content =
          await _readMeaningfulMarkdown(
            _join(localDataState.weeklyNotesDirectory, '$label.md'),
          ) ??
          await _readMeaningfulMarkdown(
            _join(
              localDataState.weeklyNotesDirectory,
              '${_lowercaseWeekLabel(label)}.md',
            ),
          );
      if (content == null) {
        continue;
      }
      buffer
        ..writeln('## $label 周报')
        ..writeln()
        ..writeln(content)
        ..writeln();
    }

    return buffer.toString().trimRight();
  }

  Future<bool> _hasMeaningfulFile(String path) async {
    return _hasMeaningfulContent(await noteService.readMarkdown(path));
  }

  Future<String?> _readMeaningfulMarkdown(String path) async {
    final content = await noteService.readMarkdown(path);
    if (!_hasMeaningfulContent(content)) {
      return null;
    }
    return content.trimRight();
  }

  bool _hasMeaningfulContent(String content) {
    return content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .any((line) => line.isNotEmpty && !line.startsWith('#'));
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = _dateOnly(date);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  DateTime? _dailyDateFromPath(String path) {
    final match = RegExp(
      r'^(20\d{2})-(\d{2})-(\d{2})\.md$',
      caseSensitive: false,
    ).firstMatch(_fileName(path));
    if (match == null) {
      return null;
    }
    return _safeDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  DateTime? _weekStartFromPath(String path) {
    final match = RegExp(
      r'^(20\d{2})-W(\d{2})\.md$',
      caseSensitive: false,
    ).firstMatch(_fileName(path));
    if (match == null) {
      return null;
    }
    return _dateFromIsoWeek(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  DateTime? _safeDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  DateTime? _dateFromIsoWeek(int year, int week) {
    if (week < 1 || week > 53) {
      return null;
    }
    final jan4 = DateTime(year, 1, 4);
    final week1 = _startOfWeek(jan4);
    final date = week1.add(Duration(days: (week - 1) * 7));
    if (_formatIsoWeek(date) !=
        '${year.toString().padLeft(4, '0')}-W${week.toString().padLeft(2, '0')}') {
      return null;
    }
    return date;
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatMonth(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$year-$month';
  }

  String _formatIsoWeek(DateTime date) {
    final start = _startOfWeek(date);
    final isoYear = start.add(const Duration(days: 3)).year;
    final first = _startOfWeek(DateTime(isoYear, 1, 4));
    final week = (start.difference(first).inDays ~/ 7) + 1;
    return '${isoYear.toString().padLeft(4, '0')}-W${week.toString().padLeft(2, '0')}';
  }

  String _lowercaseWeekLabel(String label) {
    return label.replaceFirst('W', 'w');
  }

  String _join(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }

  String _fileName(String path) {
    return path.split(RegExp(r'[\\/]')).last;
  }
}

class GeneratedReport {
  const GeneratedReport({required this.kind, required this.path});

  final NoteKind kind;
  final String path;
}
