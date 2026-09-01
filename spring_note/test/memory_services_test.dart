import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/attachments/pending_image.dart';
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

  test('memory conversation service saves and clears attached images', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_memory_images_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    const service = MemoryConversationService();
    final names = await service.saveImages(
      appDataDir: temp.path,
      images: [
        PendingImage(
          id: 'a',
          bytes: Uint8List.fromList([1, 2, 3]),
          name: 'a.png',
          extension: 'png',
        ),
        PendingImage(
          id: 'b',
          bytes: Uint8List.fromList([4, 5, 6]),
          name: 'b.jpg',
          extension: 'jpg',
        ),
      ],
    );

    expect(names, hasLength(2));
    expect(names.first, endsWith('.png'));
    expect(names.last, endsWith('.jpg'));
    expect(
      service.imagePath(appDataDir: temp.path, name: names.first),
      contains('memory_images'),
    );

    final message = MemoryMessage(
      role: 'user',
      content: '看图',
      createdAt: DateTime(2026, 9, 1),
      imageNames: names,
    );
    await service.saveMessages(appDataDir: temp.path, messages: [message]);
    final reloaded = await service.readMessages(appDataDir: temp.path);
    expect(reloaded.single.imageNames, names);
    // remember.json 只存文件名，不存图片字节。
    expect(
      File(
        '${temp.path}${Platform.pathSeparator}remember.json',
      ).readAsStringSync(),
      isNot(contains('AQID')),
    );

    expect(
      await service.readImageBytes(appDataDir: temp.path, name: names.first),
      [1, 2, 3],
    );
    // 路径穿越的文件名一律拒绝。
    expect(
      await service.readImageBytes(appDataDir: temp.path, name: '../x.png'),
      isNull,
    );

    await service.clear(appDataDir: temp.path);
    expect(
      await service.readImageBytes(appDataDir: temp.path, name: names.first),
      isNull,
    );
    expect(
      Directory(
        '${temp.path}${Platform.pathSeparator}memory_images',
      ).existsSync(),
      isFalse,
    );
  });

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

  test('scoped memory tools query only their requested note kind', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_memory_scoped_tools_',
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
    final files = <String, File>{
      'daily': File('${daily.path}${Platform.pathSeparator}2026-06-20.md'),
      'weekly': File('${weekly.path}${Platform.pathSeparator}2026-W25.md'),
      'monthly': File('${monthly.path}${Platform.pathSeparator}2026-06.md'),
    };
    await Future.wait(
      files.entries.map(
        (entry) => entry.value.writeAsString('# ${entry.key}\n\n范围检索'),
      ),
    );
    final calls = <String>[];
    final service = MemorySearchService(
      indexedNoteKindSearch:
          ({
            required directoryPath,
            required kind,
            required queries,
            required maxResults,
          }) async {
            calls.add('$kind:$directoryPath');
            return NoteSearchResult(
              ok: true,
              errorMessage: '',
              notes: [_noteIndexEntry(files[kind]!, kind)],
            );
          },
    );
    final state = LocalDataState(
      dataDirectory: temp.path,
      configPath: '${temp.path}${Platform.pathSeparator}config.json',
      dailyNotesDirectory: daily.path,
      weeklyNotesDirectory: weekly.path,
      monthlyNotesDirectory: monthly.path,
      config: AppConfig.defaults(),
    );

    final executions = <MemoryToolExecution>[];
    for (final toolName in const [
      'search_daily_notes',
      'search_weekly_notes',
      'search_monthly_notes',
    ]) {
      executions.add(
        await service.executeTool(
          localDataState: state,
          toolName: toolName,
          arguments: const {
            'keywords': ['范围检索'],
          },
          limit: 10,
        ),
      );
    }

    expect(executions.map((execution) => execution.sources.single.path), [
      files['daily']!.path,
      files['weekly']!.path,
      files['monthly']!.path,
    ]);
    expect(calls, [
      'daily:${daily.path}',
      'weekly:${weekly.path}',
      'monthly:${monthly.path}',
    ]);
  });

  test(
    'read weekly note tool returns only the requested weekly report',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'spring_note_memory_read_weekly_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final weekly = Directory('${temp.path}${Platform.pathSeparator}weekly');
      await weekly.create(recursive: true);
      await File(
        '${weekly.path}${Platform.pathSeparator}2026-W28.md',
      ).writeAsString('# 周报\n\n本周完成读取周报工具。');
      final state = LocalDataState(
        dataDirectory: temp.path,
        configPath: '${temp.path}${Platform.pathSeparator}config.json',
        dailyNotesDirectory: '${temp.path}${Platform.pathSeparator}daily',
        weeklyNotesDirectory: weekly.path,
        monthlyNotesDirectory: '${temp.path}${Platform.pathSeparator}monthly',
        config: AppConfig.defaults(),
      );

      final execution = await const MemorySearchService().executeTool(
        localDataState: state,
        toolName: 'read_weekly_note',
        arguments: const {'week': '2026-W28'},
        limit: 10,
      );

      expect(execution.sources, hasLength(1));
      expect(execution.sources.single.title, '周报 2026-W28');
      expect(execution.sources.single.snippet, contains('读取周报工具'));
      expect(execution.sources.single.path, endsWith('2026-W28.md'));
    },
  );

  test('read tools include truncation metadata in tool results', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_memory_truncation_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final daily = Directory('${temp.path}${Platform.pathSeparator}daily');
    await daily.create(recursive: true);
    final longBody = '很长的一天' * 100;
    await File(
      '${daily.path}${Platform.pathSeparator}2026-07-01.md',
    ).writeAsString('# 日报\n\n$longBody');
    await File(
      '${daily.path}${Platform.pathSeparator}2026-07-02.md',
    ).writeAsString('# 日报\n\n短。');
    final state = LocalDataState(
      dataDirectory: temp.path,
      configPath: '${temp.path}${Platform.pathSeparator}config.json',
      dailyNotesDirectory: daily.path,
      weeklyNotesDirectory: '${temp.path}${Platform.pathSeparator}weekly',
      monthlyNotesDirectory: '${temp.path}${Platform.pathSeparator}monthly',
      config: AppConfig.defaults().copyWith(memoryResultMaxCharacters: 100),
    );

    final truncatedExecution = await const MemorySearchService().executeTool(
      localDataState: state,
      toolName: 'read_daily_note',
      arguments: const {'date': '2026-07-01'},
      limit: 10,
    );
    final fullExecution = await const MemorySearchService().executeTool(
      localDataState: state,
      toolName: 'read_daily_note',
      arguments: const {'date': '2026-07-02'},
      limit: 10,
    );

    final truncatedSource = truncatedExecution.sources.single;
    expect(truncatedSource.truncated, isTrue);
    expect(truncatedSource.totalCharacters, greaterThan(100));
    expect(truncatedSource.snippet, endsWith('...'));
    final truncatedJson =
        jsonDecode(truncatedExecution.content) as Map<String, dynamic>;
    final truncatedResult =
        (truncatedJson['results'] as List).single as Map<String, dynamic>;
    expect(truncatedResult['truncated'], isTrue);
    expect(truncatedResult['totalCharacters'], truncatedSource.totalCharacters);

    final fullSource = fullExecution.sources.single;
    expect(fullSource.truncated, isFalse);
    expect(fullSource.totalCharacters, fullSource.snippet.length);
    final fullJson = jsonDecode(fullExecution.content) as Map<String, dynamic>;
    final fullResult =
        (fullJson['results'] as List).single as Map<String, dynamic>;
    expect(fullResult['truncated'], isFalse);
  });

  test('current date tool returns date and ISO week information', () async {
    final execution = await const MemorySearchService().executeTool(
      localDataState: LocalDataState(
        dataDirectory: '',
        configPath: '',
        dailyNotesDirectory: '',
        weeklyNotesDirectory: '',
        monthlyNotesDirectory: '',
        config: AppConfig.defaults(),
      ),
      toolName: 'get_current_date',
      arguments: const {},
      limit: 10,
    );

    final content = jsonDecode(execution.content) as Map<String, dynamic>;
    expect(content['date'], matches(r'^20\d{2}-\d{2}-\d{2}$'));
    expect(content['isoWeek'], matches(r'^20\d{2}-W\d{2}$'));
    expect(content['weekNumber'], isA<int>());
    expect(content['weekNumber'], inInclusiveRange(1, 53));
    expect(
      content['isoWeek'],
      endsWith('W${(content['weekNumber'] as int).toString().padLeft(2, '0')}'),
    );
  });

  test('resolve ISO week tool returns Monday to Sunday date range', () async {
    Future<Map<String, dynamic>> resolve(String week) async {
      final execution = await const MemorySearchService().executeTool(
        localDataState: LocalDataState(
          dataDirectory: '',
          configPath: '',
          dailyNotesDirectory: '',
          weeklyNotesDirectory: '',
          monthlyNotesDirectory: '',
          config: AppConfig.defaults(),
        ),
        toolName: 'resolve_iso_week',
        arguments: {'week': week},
        limit: 10,
      );
      expect(execution.sources, isEmpty);
      return jsonDecode(execution.content) as Map<String, dynamic>;
    }

    final firstWeek = await resolve('2026-W01');
    expect(firstWeek['startDate'], '2025-12-29');
    expect(firstWeek['endDate'], '2026-01-04');

    final midWeek = await resolve('2026-W28');
    expect(midWeek['startDate'], '2026-07-06');
    expect(midWeek['endDate'], '2026-07-12');

    // 2026 与 2020 都是 53 周的 ISO 年，周数跨年仍要落在正确日期。
    final week53 = await resolve('2026-W53');
    expect(week53['startDate'], '2026-12-28');
    expect(week53['endDate'], '2027-01-03');

    final leapWeek53 = await resolve('2020-W53');
    expect(leapWeek53['startDate'], '2020-12-28');
    expect(leapWeek53['endDate'], '2021-01-03');

    // 2027 年只有 52 个 ISO 周，W53 不存在；W54 超出格式约束。
    expect((await resolve('2027-W53'))['error'], 'iso_week_not_exists');
    expect((await resolve('2026-W54'))['error'], 'invalid_iso_week');
  });

  test('tool sequence chains results into later arguments', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_memory_sequence_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final daily = Directory('${temp.path}${Platform.pathSeparator}daily');
    await daily.create(recursive: true);
    await File(
      '${daily.path}${Platform.pathSeparator}2026-07-06.md',
    ).writeAsString('# 日报\n\n周一部署了回忆书编排工具。');
    await File(
      '${daily.path}${Platform.pathSeparator}2026-07-08.md',
    ).writeAsString('# 日报\n\n周三补充了顺序链测试。');
    final state = LocalDataState(
      dataDirectory: temp.path,
      configPath: '${temp.path}${Platform.pathSeparator}config.json',
      dailyNotesDirectory: daily.path,
      weeklyNotesDirectory: '${temp.path}${Platform.pathSeparator}weekly',
      monthlyNotesDirectory: '${temp.path}${Platform.pathSeparator}monthly',
      config: AppConfig.defaults(),
    );

    final execution = await const MemorySearchService().executeTool(
      localDataState: state,
      toolName: 'run_tool_sequence',
      arguments: const {
        'steps': [
          {
            'tool': 'resolve_iso_week',
            'arguments': {'week': '2026-W28'},
          },
          {
            'tool': 'read_week_daily_notes',
            'arguments': {
              'startDate': r'$steps[0].startDate',
              'endDate': r'$steps[0].endDate',
            },
          },
        ],
      },
      limit: 10,
    );

    final content = jsonDecode(execution.content) as Map<String, dynamic>;
    final steps = content['steps'] as List;
    expect(steps, hasLength(2));
    expect(content, isNot(contains('stoppedEarly')));

    final first = steps[0] as Map<String, dynamic>;
    expect(first['result']['startDate'], '2026-07-06');

    // 第二步的参数已被第一步结果替换，回显的是解析后的值。
    final second = steps[1] as Map<String, dynamic>;
    expect(second['arguments'], {
      'startDate': '2026-07-06',
      'endDate': '2026-07-12',
    });
    final results = second['result']['results'] as List;
    expect(results, hasLength(2));
    expect(
      results.map((item) => item['title']),
      containsAll(['日报 2026-07-06', '日报 2026-07-08']),
    );

    // 子工具的 sources 聚合去重后作为编排工具的 sources。
    expect(
      execution.sources.map((source) => source.title),
      containsAll(['日报 2026-07-06', '日报 2026-07-08']),
    );
  });

  test('tool sequence stops at the first failing step', () async {
    final state = LocalDataState(
      dataDirectory: '',
      configPath: '',
      dailyNotesDirectory: '',
      weeklyNotesDirectory: '',
      monthlyNotesDirectory: '',
      config: AppConfig.defaults(),
    );

    final failing = await const MemorySearchService().executeTool(
      localDataState: state,
      toolName: 'run_tool_sequence',
      arguments: const {
        'steps': [
          {
            'tool': 'resolve_iso_week',
            'arguments': {'week': '2027-W53'},
          },
          {
            'tool': 'read_daily_note',
            'arguments': {'date': r'$steps[0].startDate'},
          },
        ],
      },
      limit: 10,
    );
    final failingContent = jsonDecode(failing.content) as Map<String, dynamic>;
    expect(failingContent['stoppedEarly'], isTrue);
    final failingSteps = failingContent['steps'] as List;
    // 第二步未执行，输出只保留失败的第一步。
    expect(failingSteps, hasLength(1));
    expect(
      (failingSteps.single as Map<String, dynamic>)['error'],
      'iso_week_not_exists',
    );

    // 占位符路径不存在同样中止，且已完成步骤的结果保留。
    final badPlaceholder = await const MemorySearchService().executeTool(
      localDataState: state,
      toolName: 'run_tool_sequence',
      arguments: const {
        'steps': [
          {
            'tool': 'resolve_iso_week',
            'arguments': {'week': '2026-W28'},
          },
          {
            'tool': 'read_daily_note',
            'arguments': {'date': r'$steps[0].missing'},
          },
        ],
      },
      limit: 10,
    );
    final badContent =
        jsonDecode(badPlaceholder.content) as Map<String, dynamic>;
    expect(badContent['stoppedEarly'], isTrue);
    final badSteps = badContent['steps'] as List;
    expect(badSteps, hasLength(2));
    expect((badSteps[0] as Map<String, dynamic>)['result'], isNotNull);
    expect(
      (badSteps[1] as Map<String, dynamic>)['error'],
      contains('placeholder_path_not_found'),
    );
  });

  test('tool sequence rejects nested orchestration calls', () async {
    final execution = await const MemorySearchService().executeTool(
      localDataState: LocalDataState(
        dataDirectory: '',
        configPath: '',
        dailyNotesDirectory: '',
        weeklyNotesDirectory: '',
        monthlyNotesDirectory: '',
        config: AppConfig.defaults(),
      ),
      toolName: 'run_tool_sequence',
      arguments: const {
        'steps': [
          {
            'tool': 'run_tool_batch',
            'arguments': {
              'calls': [
                {'tool': 'get_current_date', 'arguments': <String, Object?>{}},
              ],
            },
          },
        ],
      },
      limit: 10,
    );

    final content = jsonDecode(execution.content) as Map<String, dynamic>;
    expect(content['stoppedEarly'], isTrue);
    expect(
      ((content['steps'] as List).single as Map<String, dynamic>)['error'],
      'nested_orchestration_not_supported',
    );
  });

  test('tool batch runs calls independently with per-call errors', () async {
    final execution = await const MemorySearchService().executeTool(
      localDataState: LocalDataState(
        dataDirectory: '',
        configPath: '',
        dailyNotesDirectory: '',
        weeklyNotesDirectory: '',
        monthlyNotesDirectory: '',
        config: AppConfig.defaults(),
      ),
      toolName: 'run_tool_batch',
      arguments: const {
        'calls': [
          {
            'tool': 'resolve_iso_week',
            'arguments': {'week': '2026-W01'},
          },
          {
            'tool': 'resolve_iso_week',
            'arguments': {'week': '2027-W53'},
          },
          {
            'tool': 'run_tool_sequence',
            'arguments': {'steps': <Object?>[]},
          },
        ],
      },
      limit: 10,
    );

    final content = jsonDecode(execution.content) as Map<String, dynamic>;
    final results = content['results'] as List;
    expect(results, hasLength(3));

    final first = results[0] as Map<String, dynamic>;
    expect(first['result']['startDate'], '2025-12-29');
    expect(first['result']['endDate'], '2026-01-04');

    // 单个调用失败不影响其他调用，各自带 error 字段。
    expect(
      (results[1] as Map<String, dynamic>)['error'],
      'iso_week_not_exists',
    );
    expect(
      (results[2] as Map<String, dynamic>)['error'],
      'nested_orchestration_not_supported',
    );
  });

  test('orchestration tools reject malformed call lists', () async {
    const service = MemorySearchService();
    final state = LocalDataState(
      dataDirectory: '',
      configPath: '',
      dailyNotesDirectory: '',
      weeklyNotesDirectory: '',
      monthlyNotesDirectory: '',
      config: AppConfig.defaults(),
    );

    final empty = await service.executeTool(
      localDataState: state,
      toolName: 'run_tool_batch',
      arguments: const {'calls': <Object?>[]},
      limit: 10,
    );
    expect(
      (jsonDecode(empty.content) as Map<String, dynamic>)['error'],
      'invalid_calls',
    );

    final overLimit = await service.executeTool(
      localDataState: state,
      toolName: 'run_tool_sequence',
      arguments: {
        'steps': List.generate(
          9,
          (_) => {'tool': 'get_current_date', 'arguments': <String, Object?>{}},
        ),
      },
      limit: 10,
    );
    expect(
      (jsonDecode(overLimit.content) as Map<String, dynamic>)['error'],
      'invalid_steps',
    );
  });

  test(
    'read month weekly notes includes only ISO weeks overlapping month',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'spring_note_memory_read_month_weekly_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final weekly = Directory('${temp.path}${Platform.pathSeparator}weekly');
      await weekly.create(recursive: true);
      for (final week in const [
        '2020-W53',
        '2021-W01',
        '2021-W04',
        '2021-W05',
      ]) {
        await File(
          '${weekly.path}${Platform.pathSeparator}$week.md',
        ).writeAsString('# 周报\n\n$week');
      }
      final state = LocalDataState(
        dataDirectory: temp.path,
        configPath: '${temp.path}${Platform.pathSeparator}config.json',
        dailyNotesDirectory: '${temp.path}${Platform.pathSeparator}daily',
        weeklyNotesDirectory: weekly.path,
        monthlyNotesDirectory: '${temp.path}${Platform.pathSeparator}monthly',
        config: AppConfig.defaults(),
      );

      final execution = await const MemorySearchService().executeTool(
        localDataState: state,
        toolName: 'read_month_weekly_notes',
        arguments: const {'month': '2021-01'},
        limit: 10,
      );

      expect(execution.sources.map((source) => source.title), [
        '周报 2020-W53',
        '周报 2021-W01',
        '周报 2021-W04',
      ]);
      expect(
        execution.sources.map((source) => source.title),
        isNot(contains('周报 2021-W05')),
      );
    },
  );

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
            notes: files.map((file) => _noteIndexEntry(file, 'daily')).toList(),
          );
        },
  );
}

NoteIndexEntry _noteIndexEntry(File file, String kind) {
  return NoteIndexEntry(
    path: file.path,
    name: file.uri.pathSegments.last,
    title: '',
    preview: '',
    kind: kind,
    modifiedMillis: 0,
    sizeBytes: 0,
  );
}
