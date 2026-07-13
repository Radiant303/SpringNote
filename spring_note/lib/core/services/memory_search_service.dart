import 'dart:convert';
import 'dart:io';

import '../../src/rust/api/note_index_api.dart' as rust_note_index;
import '../../src/rust/note_index.dart';
import '../models/local_data_state.dart';
import '../models/memory_message.dart';

typedef MemoryIndexedNoteSearch =
    Future<NoteSearchResult> Function({
      required String dailyDirectoryPath,
      required String weeklyDirectoryPath,
      required String monthlyDirectoryPath,
      required List<String> queries,
      required int maxResults,
    });

class MemorySearchService {
  const MemorySearchService({
    this.indexedNoteSearch = rust_note_index.searchAllIndexedNotes,
  });

  final MemoryIndexedNoteSearch indexedNoteSearch;

  Future<MemoryToolExecution> executeTool({
    required LocalDataState localDataState,
    required String toolName,
    required Map<String, Object?> arguments,
    required int limit,
  }) async {
    List<MemorySource> sources;
    try {
      sources = switch (toolName) {
        'get_current_date' => <MemorySource>[],
        'keyword_search' => await search(
          localDataState: localDataState,
          keywords: _readStringList(arguments['keywords']),
          limit: _keywordSearchResultLimit(localDataState),
        ),
        'read_daily_note' => await _executeReadDaily(
          localDataState,
          arguments['date']?.toString() ?? '',
        ),
        'read_week_daily_notes' => await _executeReadWeek(
          localDataState,
          arguments['startDate']?.toString() ?? '',
          arguments['endDate']?.toString() ?? '',
        ),
        'read_month_report' => await _executeReadMonth(
          localDataState,
          arguments['month']?.toString() ?? '',
        ),
        _ => <MemorySource>[],
      };
    } catch (_) {
      return MemoryToolExecution(
        toolName: toolName,
        arguments: arguments,
        content: jsonEncode({
          'results': const <Object>[],
          'error': 'local_tool_execution_failed',
        }),
        sources: const [],
      );
    }

    final content = toolName == 'get_current_date'
        ? jsonEncode({'date': _formatDate(DateTime.now())})
        : _sourcesToJson(sources);
    return MemoryToolExecution(
      toolName: toolName,
      arguments: arguments,
      content: content,
      sources: sources,
    );
  }

  Future<MemoryRecallResult> recall({
    required LocalDataState localDataState,
    required String question,
    required int limit,
  }) async {
    final maxSteps = limit.clamp(1, 120);
    final steps = <MemoryReActStep>[];
    final sources = <MemorySource>[];

    for (final tool in await _runDateTools(localDataState, question)) {
      final step = _step(
        thought: '问题包含明确的日期、周或月份线索，先读取对应 Markdown，避免只依赖模糊关键词。',
        tool: tool,
      );
      steps.add(step);
      sources.addAll(tool.sources);
      if (steps.length >= maxSteps) {
        return MemoryRecallResult(sources: _dedupe(sources), steps: steps);
      }
    }

    final keywordSources = await search(
      localDataState: localDataState,
      keywords: _keywordArguments(question),
      limit: _keywordSearchResultLimit(localDataState),
    );
    final keywordTool = MemoryToolCall(
      name: 'keyword_search',
      label: '关键词搜索',
      arguments: {'keywords': _keywordArguments(question)},
      sources: keywordSources,
    );
    steps.add(
      _step(thought: '需要从全部日报、周报、月报中定位相关线索，因此执行关键词搜索。', tool: keywordTool),
    );
    sources.addAll(keywordSources);

    final shouldResolveDaily =
        steps.length < maxSteps &&
        _asksWhen(question) &&
        keywordSources.isNotEmpty;
    if (shouldResolveDaily) {
      final date = _dateFromSource(keywordSources.first);
      if (date != null) {
        final source = await _readDaily(localDataState, date);
        final tool = MemoryToolCall(
          name: 'read_daily_note',
          label: '查看命中日期的完整日报',
          arguments: {'date': _formatDate(date)},
          sources: source == null ? [] : [source],
        );
        steps.add(
          _step(thought: '关键词搜索已经命中具体日期，继续读取该日完整日报，以确认事件发生时间和上下文。', tool: tool),
        );
        sources.addAll(tool.sources);
      }
    }

    return MemoryRecallResult(
      sources: _dedupe(sources).take(maxSteps).toList(),
      steps: steps.take(maxSteps).toList(),
    );
  }

  Future<List<MemorySource>> search({
    required LocalDataState localDataState,
    required List<String> keywords,
    required int limit,
  }) async {
    final terms = keywords
        .map((keyword) => keyword.trim().toLowerCase())
        .where((keyword) => keyword.runes.length >= 2)
        .toSet()
        .toList();
    if (terms.isEmpty) {
      return const [];
    }

    final indexed = await indexedNoteSearch(
      dailyDirectoryPath: localDataState.dailyNotesDirectory,
      weeklyDirectoryPath: localDataState.weeklyNotesDirectory,
      monthlyDirectoryPath: localDataState.monthlyNotesDirectory,
      queries: terms,
      maxResults: 200,
    );
    if (!indexed.ok) {
      throw StateError(
        indexed.errorMessage.isEmpty
            ? 'Indexed note search failed.'
            : indexed.errorMessage,
      );
    }
    return _rankFiles(
      indexed.notes.map((note) => File(note.path)),
      terms,
      localDataState,
      limit,
    );
  }

  Future<List<MemorySource>> _rankFiles(
    Iterable<File> files,
    List<String> terms,
    LocalDataState localDataState,
    int limit,
  ) async {
    final scored = <MemorySource>[];

    for (final file in files) {
      String content;
      try {
        content = await file.readAsString();
      } on FileSystemException {
        continue;
      }
      final score = _score(content, terms);
      if (score <= 0) {
        continue;
      }
      scored.add(
        MemorySource(
          title: _title(file),
          path: file.path,
          snippet: _snippet(content, terms, localDataState),
          score: score,
        ),
      );
    }

    scored.sort((left, right) {
      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return right.path.compareTo(left.path);
    });
    return scored.take(limit.clamp(1, 200)).toList();
  }

  Future<List<MemorySource>> _executeReadDaily(
    LocalDataState state,
    String rawDate,
  ) async {
    final date = DateTime.tryParse(rawDate);
    if (date == null) {
      return [];
    }
    final source = await _readDaily(state, date);
    return source == null ? [] : [source];
  }

  Future<List<MemorySource>> _executeReadWeek(
    LocalDataState state,
    String rawStart,
    String rawEnd,
  ) async {
    final start = DateTime.tryParse(rawStart);
    final end = DateTime.tryParse(rawEnd);
    if (start == null || end == null || end.isBefore(start)) {
      return [];
    }
    final sources = <MemorySource>[];
    final weekLimit = _weekDailyNoteLimit(state);
    for (
      var date = DateTime(start.year, start.month, start.day);
      !date.isAfter(end);
      date = date.add(const Duration(days: 1))
    ) {
      final source = await _readDaily(state, date);
      if (source != null) {
        sources.add(source);
      }
      if (sources.length >= weekLimit) {
        break;
      }
    }
    return sources;
  }

  Future<List<MemorySource>> _executeReadMonth(
    LocalDataState state,
    String rawMonth,
  ) async {
    final match = RegExp(r'^(20\d{2})-(\d{2})$').firstMatch(rawMonth);
    if (match == null) {
      return [];
    }
    final month = _safeDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      1,
    );
    if (month == null) {
      return [];
    }
    return _readMonth(state, month);
  }

  List<String> _readStringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final single = value?.toString().trim() ?? '';
    return single.isEmpty ? [] : [single];
  }

  String _sourcesToJson(List<MemorySource> sources) {
    return jsonEncode({
      'results': sources.map((source) => source.toJson()).toList(),
    });
  }

  String buildContextMarkdown(List<MemorySource> sources) {
    if (sources.isEmpty) {
      return '未检索到相关历史 Markdown。';
    }
    return sources
        .map(
          (source) =>
              '## ${source.title}\n路径：${source.path}\n相关片段：\n${source.snippet}',
        )
        .join('\n\n---\n\n');
  }

  String buildReActTrace(List<MemoryReActStep> steps) {
    if (steps.isEmpty) {
      return '未执行工具。';
    }
    return steps
        .map(
          (step) =>
              'Thought: ${step.thought}\nAct: ${step.tool.name}(${step.tool.argumentText})\nObservation: ${step.observation}',
        )
        .join('\n\n');
  }

  MemoryReActStep _step({
    required String thought,
    required MemoryToolCall tool,
  }) {
    return MemoryReActStep(
      thought: thought,
      tool: tool,
      observation: _observation(tool),
    );
  }

  String _observation(MemoryToolCall tool) {
    if (tool.sources.isEmpty) {
      return '${tool.label} 未找到相关记录。';
    }
    final titles = tool.sources.take(4).map((source) => source.title).join('、');
    return '${tool.label} 找到 ${tool.sources.length} 条记录：$titles。';
  }

  Future<List<MemoryToolCall>> _runDateTools(
    LocalDataState state,
    String question,
  ) async {
    final tools = <MemoryToolCall>[];
    final dailyDate = _extractDailyDate(question);
    if (dailyDate != null || _mentionsDaily(question)) {
      final date = dailyDate ?? DateTime.now();
      final source = await _readDaily(state, date);
      tools.add(
        MemoryToolCall(
          name: 'read_daily_note',
          label: '查看某天的日报',
          arguments: {'date': _formatDate(date)},
          sources: source == null ? [] : [source],
        ),
      );
    }

    final weekStart = _extractWeekStart(question);
    if (weekStart != null || _mentionsWeek(question)) {
      final start = weekStart ?? _startOfWeek(DateTime.now());
      tools.add(
        MemoryToolCall(
          name: 'read_week_daily_notes',
          label: '查看某周日报',
          arguments: {
            'startDate': _formatDate(start),
            'endDate': _formatDate(start.add(const Duration(days: 6))),
          },
          sources: await _readWeek(state, start),
        ),
      );
    }

    final month = _extractMonth(question);
    if (month != null || _mentionsMonth(question)) {
      final target =
          month ?? DateTime(DateTime.now().year, DateTime.now().month);
      tools.add(
        MemoryToolCall(
          name: 'read_month_report',
          label: '查看某月月报',
          arguments: {'month': _formatMonth(target)},
          sources: await _readMonth(state, target),
        ),
      );
    }

    return tools;
  }

  Future<MemorySource?> _readDaily(LocalDataState state, DateTime date) async {
    final file = File(
      _join(state.dailyNotesDirectory, '${_formatDate(date)}.md'),
    );
    if (!await file.exists()) {
      return null;
    }
    final content = await file.readAsString();
    return MemorySource(
      title: '日报 ${_formatDate(date)}',
      path: file.path,
      snippet: _snippet(content, const [], state),
      score: 100,
    );
  }

  Future<List<MemorySource>> _readWeek(
    LocalDataState state,
    DateTime start,
  ) async {
    final sources = <MemorySource>[];
    for (var index = 0; index < 7; index++) {
      final source = await _readDaily(state, start.add(Duration(days: index)));
      if (source != null) {
        sources.add(source);
      }
    }
    final weekReport = await _readOptionalFile(
      state,
      _join(state.weeklyNotesDirectory, '${_formatIsoWeek(start)}.md'),
      title: '周报 ${_formatIsoWeek(start)}',
      score: 120,
    );
    if (weekReport != null) {
      sources.insert(0, weekReport);
    }
    return sources;
  }

  Future<List<MemorySource>> _readMonth(
    LocalDataState state,
    DateTime month,
  ) async {
    final monthReport = await _readOptionalFile(
      state,
      _join(state.monthlyNotesDirectory, '${_formatMonth(month)}.md'),
      title: '月报 ${_formatMonth(month)}',
      score: 140,
    );
    return monthReport == null ? [] : [monthReport];
  }

  Future<MemorySource?> _readOptionalFile(
    LocalDataState state,
    String path, {
    required String title,
    required int score,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final content = await file.readAsString();
    return MemorySource(
      title: title,
      path: file.path,
      snippet: _snippet(content, const [], state),
      score: score,
    );
  }

  List<MemorySource> _dedupe(List<MemorySource> sources) {
    final seen = <String>{};
    final result = <MemorySource>[];
    for (final source in sources) {
      if (seen.add(source.path)) {
        result.add(source);
      }
    }
    return result;
  }

  List<String> _terms(String question) {
    return question
        .toLowerCase()
        .split(
          RegExp(
            r'[\s,，。！？?!.、;；:：()\[\]{}<>《》"'
            '“”‘’]+',
          ),
        )
        .map((term) => term.trim())
        .where((term) => term.runes.length >= 2)
        .take(8)
        .toList();
  }

  List<String> _keywordArguments(String question) {
    final terms = _terms(question);
    if (terms.isEmpty) {
      final fallback = question.trim();
      return fallback.isEmpty ? [] : [fallback];
    }
    const stopWords = {'什么时候', '哪天', '日期', '查看', '一下', '的'};
    final filtered = terms
        .map((term) => _cleanKeyword(term, stopWords))
        .where((term) => term.runes.length >= 2)
        .where((term) => !RegExp(r'^20\d{2}').hasMatch(term))
        .toList();
    final selected = filtered.isEmpty ? terms : filtered;
    return selected.where((term) => term.runes.length >= 2).take(6).toList();
  }

  String _cleanKeyword(String term, Set<String> stopWords) {
    var result = term;
    for (final stopWord in stopWords) {
      result = result.replaceAll(stopWord, '');
    }
    return result.trim();
  }

  int _score(String content, List<String> terms) {
    final lower = content.toLowerCase();
    if (terms.isEmpty) {
      return lower.trim().isEmpty ? 0 : 1;
    }
    var score = 0;
    for (final term in terms) {
      score += RegExp(RegExp.escape(term)).allMatches(lower).length;
    }
    return score;
  }

  int _singleResultMaxCharacters(LocalDataState state) {
    return state.config.memoryResultMaxCharacters.round().clamp(1, 100000);
  }

  int _weekDailyNoteLimit(LocalDataState state) {
    return state.config.memoryWeekDailyNoteLimit.round().clamp(1, 31);
  }

  int _keywordSearchResultLimit(LocalDataState state) {
    return state.config.memoryKeywordSearchResultLimit.round().clamp(1, 200);
  }

  int _keywordContextBefore(LocalDataState state) {
    return state.config.memoryKeywordContextBefore.round().clamp(0, 100000);
  }

  int _keywordContextAfter(LocalDataState state) {
    return state.config.memoryKeywordContextAfter.round().clamp(0, 100000);
  }

  String _snippet(String content, List<String> terms, LocalDataState state) {
    final normalized = content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
    if (normalized.isEmpty) {
      return '（空文档）';
    }
    final maxCharacters = _singleResultMaxCharacters(state);
    final lower = normalized.toLowerCase();
    var index = -1;
    for (final term in terms) {
      index = lower.indexOf(term);
      if (index >= 0) {
        break;
      }
    }
    if (index < 0) {
      return normalized.length > maxCharacters
          ? '${normalized.substring(0, maxCharacters)}...'
          : normalized;
    }
    final contextBefore = _keywordContextBefore(state);
    final contextAfter = _keywordContextAfter(state);
    final start = (index - contextBefore).clamp(0, normalized.length);
    final end = (index + contextAfter).clamp(0, normalized.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < normalized.length ? '...' : '';
    final excerpt = normalized.substring(start, end);
    final clipped = excerpt.length > maxCharacters
        ? excerpt.substring(0, maxCharacters)
        : excerpt;
    final clippedSuffix = suffix.isNotEmpty || excerpt.length > maxCharacters
        ? '...'
        : '';
    return '$prefix$clipped$clippedSuffix';
  }

  String _title(File file) {
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    return name.replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
  }

  DateTime? _dateFromSource(MemorySource source) {
    final match = RegExp(r'(20\d{2})-(\d{2})-(\d{2})').firstMatch(source.title);
    if (match == null) {
      return null;
    }
    return _safeDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  DateTime? _extractDailyDate(String question) {
    final normalized = question.trim();
    final today = DateTime.now();
    if (normalized.contains('今天')) {
      return DateTime(today.year, today.month, today.day);
    }
    if (normalized.contains('昨天')) {
      final date = today.subtract(const Duration(days: 1));
      return DateTime(date.year, date.month, date.day);
    }
    if (normalized.contains('前天')) {
      final date = today.subtract(const Duration(days: 2));
      return DateTime(date.year, date.month, date.day);
    }

    final full = RegExp(
      r'(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})',
    ).firstMatch(normalized);
    if (full != null) {
      return _safeDate(
        int.parse(full.group(1)!),
        int.parse(full.group(2)!),
        int.parse(full.group(3)!),
      );
    }
    final short = RegExp(
      r'(?<!\d)(\d{1,2})月(\d{1,2})[日号]?',
    ).firstMatch(normalized);
    if (short != null) {
      return _safeDate(
        today.year,
        int.parse(short.group(1)!),
        int.parse(short.group(2)!),
      );
    }
    return null;
  }

  DateTime? _extractWeekStart(String question) {
    final today = DateTime.now();
    if (question.contains('本周') || question.contains('这周')) {
      return _startOfWeek(today);
    }
    if (question.contains('上周')) {
      return _startOfWeek(today).subtract(const Duration(days: 7));
    }
    final iso = RegExp(
      r'(20\d{2})[-\s]?W(\d{1,2})',
      caseSensitive: false,
    ).firstMatch(question);
    if (iso != null) {
      return _dateFromIsoWeek(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
      );
    }
    final zh = RegExp(r'(20\d{2})?年?第\s*(\d{1,2})\s*周').firstMatch(question);
    if (zh != null) {
      return _dateFromIsoWeek(
        zh.group(1) == null ? today.year : int.parse(zh.group(1)!),
        int.parse(zh.group(2)!),
      );
    }
    return null;
  }

  DateTime? _extractMonth(String question) {
    final today = DateTime.now();
    if (question.contains('本月') || question.contains('这个月')) {
      return DateTime(today.year, today.month);
    }
    if (question.contains('上月') || question.contains('上个月')) {
      return DateTime(today.year, today.month - 1);
    }
    final full = RegExp(r'(20\d{2})[-/.年](\d{1,2})月?').firstMatch(question);
    if (full != null) {
      return _safeDate(int.parse(full.group(1)!), int.parse(full.group(2)!), 1);
    }
    final short = RegExp(r'(?<!\d)(\d{1,2})月').firstMatch(question);
    if (short != null) {
      return _safeDate(today.year, int.parse(short.group(1)!), 1);
    }
    return null;
  }

  bool _mentionsDaily(String question) {
    return question.contains('日报') &&
        !question.contains('周') &&
        !question.contains('月');
  }

  bool _mentionsWeek(String question) {
    return question.contains('周报') ||
        question.contains('本周') ||
        question.contains('上周');
  }

  bool _mentionsMonth(String question) {
    return question.contains('月报') ||
        question.contains('本月') ||
        question.contains('上月');
  }

  bool _asksWhen(String question) {
    return question.contains('什么时候') ||
        question.contains('哪天') ||
        question.contains('日期') ||
        question.toLowerCase().contains('when');
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

  DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  DateTime _dateFromIsoWeek(int year, int week) {
    final jan4 = DateTime(year, 1, 4);
    final week1 = _startOfWeek(jan4);
    return week1.add(Duration(days: (week - 1) * 7));
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatMonth(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
  }

  String _formatIsoWeek(DateTime date) {
    final start = _startOfWeek(date);
    final first = _startOfWeek(DateTime(start.year, 1, 4));
    final week = (start.difference(first).inDays ~/ 7) + 1;
    return '${start.year.toString().padLeft(4, '0')}-W${week.toString().padLeft(2, '0')}';
  }

  String _join(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }
}

class MemoryRecallResult {
  const MemoryRecallResult({required this.sources, required this.steps});

  final List<MemorySource> sources;
  final List<MemoryReActStep> steps;

  List<MemoryToolCall> get tools => steps.map((step) => step.tool).toList();
}

class MemoryReActStep {
  const MemoryReActStep({
    required this.thought,
    required this.tool,
    required this.observation,
  });

  final String thought;
  final MemoryToolCall tool;
  final String observation;

  MemoryMessage toMessage() {
    return MemoryMessage(
      role: 'local_tool',
      content:
          'Thought：$thought\nAct：${tool.name}(${tool.argumentText})\nObservation：$observation',
      createdAt: DateTime.now(),
      toolName: tool.name,
      sources: tool.sources,
    );
  }
}

class MemoryToolCall {
  const MemoryToolCall({
    required this.name,
    required this.label,
    required this.arguments,
    required this.sources,
  });

  final String name;
  final String label;
  final Map<String, Object> arguments;
  final List<MemorySource> sources;

  String get query => argumentText;

  String get argumentText {
    return arguments.entries
        .map((entry) {
          final value = entry.value;
          if (value is List) {
            return '${entry.key}=[${value.join(', ')}]';
          }
          return '${entry.key}=$value';
        })
        .join(', ');
  }
}

class MemoryToolExecution {
  const MemoryToolExecution({
    required this.toolName,
    required this.arguments,
    required this.content,
    required this.sources,
  });

  final String toolName;
  final Map<String, Object?> arguments;
  final String content;
  final List<MemorySource> sources;
}
