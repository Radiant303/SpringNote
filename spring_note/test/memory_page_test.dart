import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/memory_message.dart';
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
}
