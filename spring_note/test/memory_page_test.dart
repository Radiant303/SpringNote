import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/custom_widgets/unordered_ordered_list.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/memory_message.dart';
import 'package:spring_note/core/services/memory_conversation_service.dart';
import 'package:spring_note/core/services/memory_search_service.dart';
import 'package:spring_note/features/memory/memory_page.dart';

void main() {
  test('memory reasoning collapses for content or tool calls', () {
    final streamingThought = MemoryMessage(
      role: 'ai',
      content: '',
      reasoningContent: '正在思考',
      createdAt: DateTime(2026, 6, 19),
    );
    final finalAnswer = MemoryMessage(
      role: 'ai',
      content: '最终回答',
      reasoningContent: '思考完成',
      createdAt: DateTime(2026, 6, 19),
    );
    final toolCallMessage = MemoryMessage(
      role: 'assistant',
      content: '',
      reasoningContent: '需要调用工具',
      createdAt: DateTime(2026, 6, 19),
      toolCalls: const [
        MemoryToolCallMessage(
          id: 'call-keyword',
          name: 'keyword_search',
          arguments: '{"keywords":["检索"]}',
        ),
      ],
    );

    expect(shouldCollapseMemoryReasoning(streamingThought), isFalse);
    expect(shouldCollapseMemoryReasoning(finalAnswer), isTrue);
    expect(shouldCollapseMemoryReasoning(toolCallMessage), isTrue);
  });

  test('memory tool result label uses content when there are no sources', () {
    final dateResult = MemoryMessage(
      role: 'tool',
      content: '{"date":"2026-06-19"}',
      createdAt: DateTime(2026, 6, 19),
      toolName: 'get_current_date',
      toolCallId: 'call-date',
    );
    final emptyResult = MemoryMessage(
      role: 'tool',
      content: '',
      createdAt: DateTime(2026, 6, 19),
      toolName: 'keyword_search',
      toolCallId: 'call-keyword',
    );

    expect(memoryToolResultLabel(dateResult), '已返回');
    expect(memoryToolResultLabel(emptyResult), '无结果');
    expect(memoryToolResultLabel(null), '无结果');
  });

  test('memory tool cache key is stable for reordered arguments', () {
    final left = memoryToolCacheKey('read_daily_note', {
      'date': '2026-06-24',
      'options': {'b': 2, 'a': 1},
    });
    final right = memoryToolCacheKey('read_daily_note', {
      'options': {'a': 1, 'b': 2},
      'date': '2026-06-24',
    });

    expect(left, right);
  });

  test('deduplicated memory tool content asks model to reuse result', () {
    final content = deduplicatedMemoryToolContent('{"date":"2026-06-24"}');

    expect(content, contains('"cached":true'));
    expect(content, contains('Use the cached result'));
    expect(content, contains('2026-06-24'));
  });

  testWidgets('memory markdown uses shared preview rendering', (tester) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryPage(
            localDataState: _localDataState(),
            conversationService: _FakeMemoryConversationService(
              initialMessages: [
                MemoryMessage(
                  role: 'ai',
                  content: '# 今日完成\n- [x] 修复任务\n正文',
                  createdAt: DateTime(2026, 7, 8),
                ),
              ],
            ),
            searchService: const _FakeMemorySearchService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final markdownTheme = tester.widget<GptMarkdownTheme>(
      find.byType(GptMarkdownTheme),
    );
    expect(markdownTheme.gptThemeData.h1?.height, 0.92);
    expect(markdownTheme.gptThemeData.h1?.color, const Color(0xFF333333));
    expect(find.byType(Checkbox), findsNothing);
    expect(
      find.byKey(const ValueKey('markdown-task-checkbox-checked')),
      findsOneWidget,
    );

    final checkboxSize = tester.getSize(
      find.byKey(const ValueKey('markdown-task-checkbox-checked')),
    );
    expect(checkboxSize.width, closeTo(11.2, 0.001));
    expect(checkboxSize.height, closeTo(11.2, 0.001));

    final lists = tester.widgetList<UnorderedListView>(
      find.byType(UnorderedListView),
    );
    expect(lists.any((list) => list.bulletSize == 0), isTrue);
  });

  test('memory image bases include source note and notes directories', () {
    final localDataState = _localDataState(
      dataDirectory: _joinPath('D:\\Temp', 'SpringNote'),
      dailyNotesDirectory: _joinPath(
        _joinPath('D:\\Temp\\SpringNote', 'notes'),
        'daily',
      ),
      weeklyNotesDirectory: _joinPath(
        _joinPath('D:\\Temp\\SpringNote', 'notes'),
        'weekly',
      ),
      monthlyNotesDirectory: _joinPath(
        _joinPath('D:\\Temp\\SpringNote', 'notes'),
        'monthly',
      ),
    );
    final dailyDirectory = localDataState.dailyNotesDirectory;
    final notesDirectory = _joinPath('D:\\Temp\\SpringNote', 'notes');
    final message = MemoryMessage(
      role: 'ai',
      content: '![chart](../images/chart.png)',
      createdAt: DateTime(2026, 7, 8),
      sources: [
        MemorySource(
          title: '日报 2026-07-08',
          path: _joinPath(dailyDirectory, '2026-07-08.md'),
          snippet: '![chart](../images/chart.png)',
          score: 100,
        ),
      ],
    );

    final paths = memoryImageBasePaths(message, localDataState);

    expect(paths, contains(dailyDirectory));
    expect(paths, contains(notesDirectory));
  });

  for (final shortcut in const [
    (name: 'ctrl enter', key: LogicalKeyboardKey.controlLeft),
    (name: 'meta enter', key: LogicalKeyboardKey.metaLeft),
  ]) {
    testWidgets('memory entry submits with ${shortcut.name}', (tester) async {
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final conversationService = _FakeMemoryConversationService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MemoryPage(
              localDataState: _localDataState(),
              conversationService: conversationService,
              searchService: const _FakeMemorySearchService(),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '用快捷键询问回忆');
      await tester.sendKeyDownEvent(shortcut.key);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(shortcut.key);

      for (var index = 0; index < 20; index++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (conversationService.savedMessages.any(
          (message) => message.role == 'user' && message.content == '用快捷键询问回忆',
        )) {
          break;
        }
      }

      expect(find.text('用快捷键询问回忆'), findsOneWidget);
      expect(
        conversationService.savedMessages,
        contains(
          isA<MemoryMessage>()
              .having((message) => message.role, 'role', 'user')
              .having((message) => message.content, 'content', '用快捷键询问回忆'),
        ),
      );
    });
  }
}

class _FakeMemoryConversationService extends MemoryConversationService {
  _FakeMemoryConversationService({this.initialMessages = const []});

  final List<MemoryMessage> initialMessages;
  List<MemoryMessage> savedMessages = const [];

  @override
  Future<List<MemoryMessage>> readMessages({required String appDataDir}) async {
    return initialMessages;
  }

  @override
  Future<void> saveMessages({
    required String appDataDir,
    required List<MemoryMessage> messages,
  }) async {
    savedMessages = messages;
  }
}

LocalDataState _localDataState({
  String dataDirectory = 'D:\\Temp\\SpringNote',
  String dailyNotesDirectory = 'D:\\Temp\\SpringNote\\notes\\daily',
  String weeklyNotesDirectory = 'D:\\Temp\\SpringNote\\notes\\weekly',
  String monthlyNotesDirectory = 'D:\\Temp\\SpringNote\\notes\\monthly',
}) {
  return LocalDataState(
    dataDirectory: dataDirectory,
    configPath: _joinPath(dataDirectory, 'config.json'),
    dailyNotesDirectory: dailyNotesDirectory,
    weeklyNotesDirectory: weeklyNotesDirectory,
    monthlyNotesDirectory: monthlyNotesDirectory,
    config: AppConfig.defaults(),
  );
}

String _joinPath(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

class _FakeMemorySearchService extends MemorySearchService {
  const _FakeMemorySearchService();

  @override
  Future<MemoryRecallResult> recall({
    required LocalDataState localDataState,
    required String question,
    required int limit,
  }) async {
    return const MemoryRecallResult(sources: [], steps: []);
  }
}
