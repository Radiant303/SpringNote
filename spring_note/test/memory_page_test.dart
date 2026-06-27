import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
      final localDataState = LocalDataState(
        dataDirectory: 'D:\\Temp\\SpringNote',
        configPath: 'D:\\Temp\\SpringNote\\config.json',
        dailyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\daily',
        weeklyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\weekly',
        monthlyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\monthly',
        config: AppConfig.defaults(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MemoryPage(
              localDataState: localDataState,
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
  List<MemoryMessage> savedMessages = const [];

  @override
  Future<List<MemoryMessage>> readMessages({required String appDataDir}) async {
    return const [];
  }

  @override
  Future<void> saveMessages({
    required String appDataDir,
    required List<MemoryMessage> messages,
  }) async {
    savedMessages = messages;
  }
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
