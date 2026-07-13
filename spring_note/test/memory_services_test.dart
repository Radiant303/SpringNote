import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/memory_message.dart';
import 'package:spring_note/core/services/memory_conversation_service.dart';
import 'package:spring_note/core/services/memory_search_service.dart';
import 'package:spring_note/src/rust/note_index.dart';

void main() {
  test(
    'memory conversation service persists and clears remember json',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'spring_note_memory_conversation_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });

      const service = MemoryConversationService();
      final messages = [
        MemoryMessage(
          role: 'user',
          content: '昨天做了什么？',
          createdAt: DateTime(2026, 6, 18),
        ),
        MemoryMessage(
          role: 'ai',
          content: '你完成了首页统计。',
          reasoningContent: '先检查昨天的日报。',
          reasoningDurationMs: 4700,
          createdAt: DateTime(2026, 6, 18, 0, 1),
        ),
      ];

      await service.saveMessages(appDataDir: temp.path, messages: messages);
      final reloaded = await service.readMessages(appDataDir: temp.path);
      expect(reloaded, hasLength(2));
      expect(reloaded.first.role, 'user');
      expect(reloaded.last.content, contains('首页统计'));
      expect(reloaded.last.reasoningDurationMs, 4700);

      await service.clear(appDataDir: temp.path);
      expect(await service.readMessages(appDataDir: temp.path), isEmpty);
      expect(
        File('${temp.path}${Platform.pathSeparator}remember.json').existsSync(),
        isTrue,
      );
    },
  );

  test('memory search service finds markdown sources by keyword', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_memory_search_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final daily = Directory('${temp.path}${Platform.pathSeparator}daily');
    final weekly = Directory('${temp.path}${Platform.pathSeparator}weekly');
    final monthly = Directory('${temp.path}${Platform.pathSeparator}monthly');
    await Future.wait([
      daily.create(recursive: true),
      weekly.create(recursive: true),
      monthly.create(recursive: true),
    ]);
    await File(
      '${daily.path}${Platform.pathSeparator}2026-06-18.md',
    ).writeAsString('# 日报\n\n完成了回忆书关键词检索，并修复 remember.json 持久化。');
    await File(
      '${weekly.path}${Platform.pathSeparator}2026-W25.md',
    ).writeAsString('# 周报\n\n处理了统计热力图。');

    final service = _indexedSearchService([
      File('${daily.path}${Platform.pathSeparator}2026-06-18.md'),
      File('${weekly.path}${Platform.pathSeparator}2026-W25.md'),
    ]);
    final result = await service.search(
      localDataState: LocalDataState(
        dataDirectory: temp.path,
        configPath: '${temp.path}${Platform.pathSeparator}config.json',
        dailyNotesDirectory: daily.path,
        weeklyNotesDirectory: weekly.path,
        monthlyNotesDirectory: monthly.path,
        config: AppConfig.defaults(),
      ),
      keywords: const ['回忆书', '检索'],
      limit: 2,
    );

    expect(result, isNotEmpty);
    expect(result.first.title, '2026-06-18');
    expect(result.first.snippet, contains('回忆书'));
  });

  test('memory search service ignores one-character keywords', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_memory_short_search_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final daily = Directory('${temp.path}${Platform.pathSeparator}daily');
    final weekly = Directory('${temp.path}${Platform.pathSeparator}weekly');
    final monthly = Directory('${temp.path}${Platform.pathSeparator}monthly');
    await Future.wait([
      daily.create(recursive: true),
      weekly.create(recursive: true),
      monthly.create(recursive: true),
    ]);
    await File(
      '${daily.path}${Platform.pathSeparator}2026-06-18.md',
    ).writeAsString('# 日报\n\n回忆书');

    const service = MemorySearchService();
    final result = await service.search(
      localDataState: LocalDataState(
        dataDirectory: temp.path,
        configPath: '${temp.path}${Platform.pathSeparator}config.json',
        dailyNotesDirectory: daily.path,
        weeklyNotesDirectory: weekly.path,
        monthlyNotesDirectory: monthly.path,
        config: AppConfig.defaults(),
      ),
      keywords: const ['回'],
      limit: 10,
    );

    expect(result, isEmpty);
  });

  test('memory search supports decoded non-ASCII note filenames', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_memory_percent_filename_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final daily = Directory('${temp.path}${Platform.pathSeparator}daily');
    final weekly = Directory('${temp.path}${Platform.pathSeparator}weekly');
    final monthly = Directory('${temp.path}${Platform.pathSeparator}monthly');
    await Future.wait([
      daily.create(recursive: true),
      weekly.create(recursive: true),
      monthly.create(recursive: true),
    ]);
    await File(
      '${daily.path}${Platform.pathSeparator}2026-06-20 - 副本.md',
    ).writeAsString('# 日报\n\n忽如一夜春风来。');

    final result =
        await _indexedSearchService([
          File('${daily.path}${Platform.pathSeparator}2026-06-20 - 副本.md'),
        ]).search(
          localDataState: LocalDataState(
            dataDirectory: temp.path,
            configPath: '${temp.path}${Platform.pathSeparator}config.json',
            dailyNotesDirectory: daily.path,
            weeklyNotesDirectory: weekly.path,
            monthlyNotesDirectory: monthly.path,
            config: AppConfig.defaults(),
          ),
          keywords: const ['春风'],
          limit: 2,
        );

    expect(result, hasLength(1));
    expect(result.single.title, '2026-06-20 - 副本');
  });

  test('memory search does not scan files when the index fails', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_memory_index_failure_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final daily = Directory('${temp.path}${Platform.pathSeparator}daily');
    await daily.create(recursive: true);
    await File(
      '${daily.path}${Platform.pathSeparator}2026-06-20.md',
    ).writeAsString('# 日报\n\n这里包含春风，但不应被全量扫描。');
    final state = LocalDataState(
      dataDirectory: temp.path,
      configPath: '${temp.path}${Platform.pathSeparator}config.json',
      dailyNotesDirectory: daily.path,
      weeklyNotesDirectory: '${temp.path}${Platform.pathSeparator}weekly',
      monthlyNotesDirectory: '${temp.path}${Platform.pathSeparator}monthly',
      config: AppConfig.defaults(),
    );
    final service = MemorySearchService(
      indexedNoteSearch:
          ({
            required dailyDirectoryPath,
            required weeklyDirectoryPath,
            required monthlyDirectoryPath,
            required queries,
            required maxResults,
          }) async => const NoteSearchResult(
            ok: false,
            errorMessage: 'index unavailable',
            notes: [],
          ),
    );

    final execution = await service.executeTool(
      localDataState: state,
      toolName: 'keyword_search',
      arguments: const {
        'keywords': ['春风'],
      },
      limit: 10,
    );

    expect(execution.sources, isEmpty);
    expect(execution.content, contains('local_tool_execution_failed'));
    expect(execution.content, isNot(contains('2026-06-20')));
  });

  test('memory recall uses daily weekly and monthly tools', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_memory_tools_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final daily = Directory('${temp.path}${Platform.pathSeparator}daily');
    final weekly = Directory('${temp.path}${Platform.pathSeparator}weekly');
    final monthly = Directory('${temp.path}${Platform.pathSeparator}monthly');
    await Future.wait([
      daily.create(recursive: true),
      weekly.create(recursive: true),
      monthly.create(recursive: true),
    ]);
    await File(
      '${daily.path}${Platform.pathSeparator}2026-06-18.md',
    ).writeAsString('# 日报\n\n删除 nacos 配置。');
    await File(
      '${weekly.path}${Platform.pathSeparator}2026-W25.md',
    ).writeAsString('# 周报\n\n本周处理配置中心问题。');
    await File(
      '${monthly.path}${Platform.pathSeparator}2026-06.md',
    ).writeAsString('# 月报\n\n六月复盘了配置治理。');

    final state = LocalDataState(
      dataDirectory: temp.path,
      configPath: '${temp.path}${Platform.pathSeparator}config.json',
      dailyNotesDirectory: daily.path,
      weeklyNotesDirectory: weekly.path,
      monthlyNotesDirectory: monthly.path,
      config: AppConfig.defaults(),
    );
    final service = _indexedSearchService([
      File('${daily.path}${Platform.pathSeparator}2026-06-18.md'),
      File('${weekly.path}${Platform.pathSeparator}2026-W25.md'),
      File('${monthly.path}${Platform.pathSeparator}2026-06.md'),
    ]);

    final dailyRecall = await service.recall(
      localDataState: state,
      question: '查看2026-06-18日报',
      limit: 3,
    );
    expect(
      dailyRecall.tools.map((tool) => tool.name),
      contains('read_daily_note'),
    );
    expect(dailyRecall.sources.first.snippet, contains('nacos'));

    final weeklyRecall = await service.recall(
      localDataState: state,
      question: '查看2026-W25周报',
      limit: 3,
    );
    expect(
      weeklyRecall.tools.map((tool) => tool.name),
      contains('read_week_daily_notes'),
    );
    expect(
      weeklyRecall.sources.map((source) => source.title),
      contains('周报 2026-W25'),
    );

    final monthlyRecall = await service.recall(
      localDataState: state,
      question: '查看2026年6月月报',
      limit: 3,
    );
    expect(
      monthlyRecall.tools.map((tool) => tool.name),
      contains('read_month_report'),
    );
    expect(
      monthlyRecall.sources.map((source) => source.title),
      contains('月报 2026-06'),
    );
    expect(
      monthlyRecall.sources.map((source) => source.title),
      isNot(contains('日报 2026-06-18')),
    );
    expect(monthlyRecall.sources.single.snippet, contains('六月复盘'));
  });

  test('local recall steps use a UI-only message role', () {
    final message = MemoryReActStep(
      thought: '先查关键词',
      tool: const MemoryToolCall(
        name: 'keyword_search',
        label: '关键词搜索',
        arguments: {
          'keywords': ['回忆书'],
        },
        sources: [],
      ),
      observation: '找到一条日报',
    ).toMessage();

    expect(message.role, 'local_tool');
    expect(message.toolCallId, isNull);
    expect(message.content, contains('Observation'));
  });

  test(
    'memory recall follows ReAct loop from keyword hit to full daily note',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'spring_note_memory_react_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final daily = Directory('${temp.path}${Platform.pathSeparator}daily');
      final weekly = Directory('${temp.path}${Platform.pathSeparator}weekly');
      final monthly = Directory('${temp.path}${Platform.pathSeparator}monthly');
      await Future.wait([
        daily.create(recursive: true),
        weekly.create(recursive: true),
        monthly.create(recursive: true),
      ]);
      await File(
        '${daily.path}${Platform.pathSeparator}2026-06-18.md',
      ).writeAsString('# 日报\n\n上午删除 nacos 配置，下午验证服务启动。');

      final service = _indexedSearchService([
        File('${daily.path}${Platform.pathSeparator}2026-06-18.md'),
      ]);
      final recall = await service.recall(
        localDataState: LocalDataState(
          dataDirectory: temp.path,
          configPath: '${temp.path}${Platform.pathSeparator}config.json',
          dailyNotesDirectory: daily.path,
          weeklyNotesDirectory: weekly.path,
          monthlyNotesDirectory: monthly.path,
          config: AppConfig.defaults(),
        ),
        question: '什么时候删除 nacos 配置',
        limit: 3,
      );

      expect(recall.steps.map((step) => step.tool.name), [
        'keyword_search',
        'read_daily_note',
      ]);
      expect(recall.steps.first.tool.arguments['keywords'], contains('nacos'));
      expect(recall.steps.first.thought, contains('关键词搜索'));
      expect(recall.steps.last.observation, contains('日报 2026-06-18'));
      final trace = service.buildReActTrace(recall.steps);
      expect(trace, contains('Act: keyword_search(keywords=['));
      expect(trace, contains('nacos'));
    },
  );
}

MemorySearchService _indexedSearchService(List<File> files) {
  return MemorySearchService(
    indexedNoteSearch:
        ({
          required dailyDirectoryPath,
          required weeklyDirectoryPath,
          required monthlyDirectoryPath,
          required queries,
          required maxResults,
        }) async {
          return NoteSearchResult(
            ok: true,
            errorMessage: '',
            notes: files
                .map(
                  (file) => NoteIndexEntry(
                    path: file.path,
                    name: file.uri.pathSegments.last,
                    title: '',
                    preview: '',
                    kind: 'daily',
                    modifiedMillis: 0,
                    sizeBytes: 0,
                  ),
                )
                .toList(),
          );
        },
  );
}
