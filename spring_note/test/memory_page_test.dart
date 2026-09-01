import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/custom_widgets/unordered_ordered_list.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:spring_note/core/attachments/pending_image.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/memory_message.dart';
import 'package:spring_note/core/services/ai_client_service.dart';
import 'package:spring_note/core/services/memory_conversation_service.dart';
import 'package:spring_note/core/services/memory_search_service.dart';
import 'package:spring_note/core/services/pending_image_clipboard_service.dart';
import 'package:spring_note/core/widgets/spring_markdown.dart';
import 'package:spring_note/core/widgets/spring_tree.dart';
import 'package:spring_note/features/memory/memory_input_modes.dart';
import 'package:spring_note/features/memory/memory_page.dart';
import 'package:spring_note/l10n/app_localizations_zh.dart';
import 'package:spring_note/src/rust/ai.dart' as rust_ai;

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

    expect(memoryToolResultLabel(AppLocalizationsZh(), dateResult), '已返回');
    expect(memoryToolResultLabel(AppLocalizationsZh(), emptyResult), '无结果');
    expect(memoryToolResultLabel(AppLocalizationsZh(), null), '无结果');
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
                  content: '# 今日完成\n- [x] 修复任务\n\\[E = mc^2\\]\n正文',
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
    final markdown = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
    expect(markdownTheme.gptThemeData.h1?.height, 0.92);
    expect(markdownTheme.gptThemeData.h1?.color, const Color(0xFF333333));
    expect(markdown.onLinkTap, same(openSpringMarkdownLink));
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
    expect(find.byKey(const ValueKey('markdown-display-math')), findsOneWidget);

    final lists = tester.widgetList<UnorderedListView>(
      find.byType(UnorderedListView),
    );
    expect(lists.any((list) => list.bulletSize == 0), isTrue);
  });

  testWidgets('springtree message stays inside the reading column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 760);
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
                  content: '普通回答',
                  createdAt: DateTime(2026, 7, 8),
                ),
                MemoryMessage(
                  role: 'ai',
                  content: '导图如下\n```springtree\n- 根节点\n  - 子节点\n```\n补充说明',
                  reasoningContent: '推理过程',
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

    // Every message — including one with a mind map — renders inside the
    // same centered 820 reading column; nothing stretches to the window.
    expect(
      tester.getSize(find.byType(SpringTreeBlock)).width,
      lessThanOrEqualTo(820),
    );
    final markdownWidths = tester
        .widgetList<GptMarkdown>(find.byType(GptMarkdown))
        .map((widget) => tester.getSize(find.byWidget(widget)).width);
    expect(markdownWidths.every((width) => width <= 820), isTrue);
    expect(find.textContaining('深度思考'), findsOneWidget);
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

  testWidgets('memory keeps the next draft while an answer is streaming', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final aiClientService = _DelayedMemoryAiClientService();
    addTearDown(aiClientService.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryPage(
            localDataState: _localDataState(),
            aiClientService: aiClientService,
            conversationService: _FakeMemoryConversationService(),
            searchService: const _FakeMemorySearchService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '第一条回忆问题');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    for (var index = 0; index < 20 && !aiClientService.started; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(aiClientService.started, isTrue);
    await tester.pump(const Duration(milliseconds: 200));

    final inputFinder = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == '继续追问你的回忆...',
    );
    final inputField = tester.widget<TextField>(inputFinder);
    final inputController = inputField.controller!;
    expect(inputField.enabled, isTrue);
    await tester.enterText(inputFinder, '下一条预先输入的回忆问题');
    expect(inputController.text, '下一条预先输入的回忆问题');

    aiClientService.complete();
    await tester.pumpAndSettle();

    expect(inputController.text, '下一条预先输入的回忆问题');
  });

  testWidgets('input mode menu opens as a panel below the entry + button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryPage(
            localDataState: _localDataState(),
            conversationService: _FakeMemoryConversationService(),
            searchService: const _FakeMemorySearchService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    final composer = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.constraints == const BoxConstraints(minHeight: 52),
    );
    expect(composer, findsOneWidget);
    final panel = find.byKey(const ValueKey('input-mode-menu-panel'));
    expect(panel, findsOneWidget);

    // The panel spans the composer: same left edge and width, just below it.
    expect(tester.getTopLeft(panel).dx, tester.getTopLeft(composer).dx);
    expect(tester.getSize(panel).width, tester.getSize(composer).width);
    expect(
      tester.getTopLeft(panel).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(composer).dy),
    );
    expect(
      tester.getTopLeft(panel).dy,
      lessThan(tester.getBottomLeft(composer).dy + 24),
    );
    expect(find.text('以思维导图呈现回答'), findsOneWidget);
  });

  testWidgets(
    'mind map mode tag edits like text and injects the prompt only for the model',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final aiClientService = _DelayedMemoryAiClientService();
      addTearDown(aiClientService.dispose);
      final conversationService = _FakeMemoryConversationService(
        initialMessages: [
          MemoryMessage(
            role: 'ai',
            content: '之前的回答',
            createdAt: DateTime(2026, 7, 8),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MemoryPage(
              localDataState: _localDataState(),
              aiClientService: aiClientService,
              conversationService: conversationService,
              searchService: const _FakeMemorySearchService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);
      EditableText composer() =>
          tester.widget<EditableText>(find.byType(EditableText));
      String composerText() => composer().controller.text;

      // The "+" menu inserts the 思维导图 tag into the input text.
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('思维导图'));
      await tester.pumpAndSettle();
      expect(composerText(), mindMapInputMode.token);
      // The caret lands right after the tag and the field keeps its focus —
      // no select-all-on-focus highlighting the fresh tag.
      expect(
        composer().controller.selection,
        const TextSelection.collapsed(offset: 1),
      );
      expect(composer().focusNode.hasFocus, isTrue);

      // The tag is one code point: Backspace removes it whole, turning the
      // mode off again.
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(composerText(), isEmpty);

      // Type the question first, then tag it: the tag joins the draft.
      await tester.enterText(inputFinder, '整理上周周报');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('思维导图'));
      await tester.pumpAndSettle();
      expect(composerText(), '整理上周周报${mindMapInputMode.token}');
      expect(
        composer().controller.selection,
        TextSelection.collapsed(offset: '整理上周周报'.length + 1),
      );
      expect(composer().focusNode.hasFocus, isTrue);

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      for (var index = 0; index < 20 && !aiClientService.started; index++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(aiClientService.started, isTrue);

      // The model receives the question plus the springtree prompt, without
      // the tag itself; the bubble and storage keep the clean text.
      final modelUserMessage = aiClientService.capturedMessages!.lastWhere(
        (message) => message.role == 'user',
      );
      expect(modelUserMessage.content, contains('整理上周周报'));
      expect(modelUserMessage.content, contains('SpringTree 输出模式'));
      expect(modelUserMessage.content, isNot(contains(mindMapInputMode.token)));

      final savedUserMessage = conversationService.savedMessages.lastWhere(
        (message) => message.role == 'user',
      );
      expect(savedUserMessage.content, '整理上周周报');

      aiClientService.complete();
      await tester.pumpAndSettle();
    },
  );

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

  testWidgets('removing one pasted image chip keeps the others', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The real clipboard service returns the same id for every pasted
    // bitmap (`clipboard-png-0`); removal matches chips by id, so this
    // regression test pastes two images with identical ids and expects
    // deleting one to keep the other.
    final clipboard = _FakePendingImageClipboardService([
      PendingImage(
        id: 'clipboard-png-0',
        bytes: Uint8List.fromList([1, 2, 3]),
        name: 'one.png',
        extension: 'png',
      ),
      PendingImage(
        id: 'clipboard-png-0',
        bytes: Uint8List.fromList([4, 5, 6]),
        name: 'two.png',
        extension: 'png',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryPage(
            localDataState: _localDataState(),
            conversationService: _FakeMemoryConversationService(),
            searchService: const _FakeMemorySearchService(),
            aiClientService: const _ImageCapableMemoryAiClientService(),
            pendingImageClipboardService: clipboard,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    for (var index = 0; index < 20; index++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byIcon(Icons.close).evaluate().length == 2) {
        break;
      }
    }

    expect(find.text('one.png'), findsOneWidget);
    expect(find.text('two.png'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text('one.png'), findsNothing);
    expect(find.text('two.png'), findsOneWidget);
  });

  testWidgets(
    'memory entry does not submit with bare enter in ctrl enter mode',
    (tester) async {
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

      await tester.enterText(find.byType(TextField), '回车不应该发送');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      for (var index = 0; index < 20; index++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(conversationService.savedMessages, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '回车不应该发送',
      );
    },
  );

  testWidgets('memory entry submits with bare enter in enter mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final conversationService = _FakeMemoryConversationService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryPage(
            localDataState: _localDataState(
              config: AppConfig.defaults().copyWith(submitShortcut: 'enter'),
            ),
            conversationService: conversationService,
            searchService: const _FakeMemorySearchService(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '回车直接询问回忆');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var index = 0; index < 20; index++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (conversationService.savedMessages.any(
        (message) => message.role == 'user' && message.content == '回车直接询问回忆',
      )) {
        break;
      }
    }

    expect(
      conversationService.savedMessages,
      contains(
        isA<MemoryMessage>()
            .having((message) => message.role, 'role', 'user')
            .having((message) => message.content, 'content', '回车直接询问回忆'),
      ),
    );
  });

  testWidgets('conversation nav shows with multiple rounds and jumps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String longAnswer(int index) =>
        '回答 $index\n${List.filled(12, '这是一段很长的回答内容，用来撑开滚动高度。').join('\n')}';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryPage(
            localDataState: _localDataState(),
            conversationService: _FakeMemoryConversationService(
              initialMessages: [
                for (var index = 1; index <= 8; index++) ...[
                  MemoryMessage(
                    role: 'user',
                    content: '问题 $index',
                    createdAt: DateTime(2026, 7, 8, 10, index),
                  ),
                  MemoryMessage(
                    role: 'ai',
                    content: longAnswer(index),
                    createdAt: DateTime(2026, 7, 8, 11, index),
                  ),
                ],
              ],
            ),
            searchService: const _FakeMemorySearchService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nav = find.byKey(const ValueKey('memory-conversation-nav'));
    expect(nav, findsOneWidget);

    final listScrollable = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((state) => state.position.maxScrollExtent > 0);
    expect(listScrollable.position.pixels, 0);

    // Collapsed it is only the dash rail: labels fade in on hover.
    Iterable<AnimatedOpacity> fades() => tester.widgetList<AnimatedOpacity>(
      find.descendant(of: nav, matching: find.byType(AnimatedOpacity)),
    );
    expect(fades().every((fade) => fade.opacity == 0), isTrue);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(nav));
    await tester.pump(const Duration(milliseconds: 150));
    expect(fades().every((fade) => fade.opacity == 1), isTrue);
    for (var index = 1; index <= 8; index++) {
      expect(
        find.descendant(of: nav, matching: find.text('问题 $index')),
        findsOneWidget,
      );
    }

    await tester.tap(find.descendant(of: nav, matching: find.text('问题 8')));
    // The tapped entry's dash starts growing on the very next frame: the
    // highlight does not wait for the jump scroll to finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(
      tester
          .getSize(
            find
                .descendant(of: nav, matching: find.byType(AnimatedContainer))
                .at(7),
          )
          .width,
      greaterThan(5.6),
    );
    await tester.pumpAndSettle();

    expect(listScrollable.position.pixels, greaterThan(0));
    // After the jump the last round's bubble is on screen as well.
    expect(find.text('问题 8'), findsNWidgets(2));

    // Moving the mouse away collapses the nav back to the dash rail.
    await mouse.moveTo(const Offset(80, 400));
    await tester.pumpAndSettle();
    expect(fades().every((fade) => fade.opacity == 0), isTrue);
  });

  testWidgets('conversation nav keeps the tapped round highlighted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String longAnswer(int index) =>
        '回答 $index\n${List.filled(12, '这是一段很长的回答内容，用来撑开滚动高度。').join('\n')}';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryPage(
            localDataState: _localDataState(),
            conversationService: _FakeMemoryConversationService(
              initialMessages: [
                for (var index = 1; index <= 8; index++) ...[
                  MemoryMessage(
                    role: 'user',
                    content: '问题 $index',
                    createdAt: DateTime(2026, 7, 8, 10, index),
                  ),
                  MemoryMessage(
                    role: 'ai',
                    content: longAnswer(index),
                    createdAt: DateTime(2026, 7, 8, 11, index),
                  ),
                ],
              ],
            ),
            searchService: const _FakeMemorySearchService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nav = find.byKey(const ValueKey('memory-conversation-nav'));
    final dashes = find.descendant(
      of: nav,
      matching: find.byType(AnimatedContainer),
    );
    final chatScrollable = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((state) => state.position.maxScrollExtent > 0);

    // Position the list so rounds 3 and 4 are both on screen and round 4
    // is the lowest round past the active threshold.
    final top = tester.getTopLeft(find.text('问题 4').first).dy;
    chatScrollable.position.jumpTo(top + chatScrollable.position.pixels - 650);
    await tester.pumpAndSettle();
    expect(tester.getSize(dashes.at(3)).width, 8);

    // Tap round 3: it is already visible, so the list does not even
    // scroll — the highlight must stay on round 3 instead of snapping
    // back to round 4, the lowest round on screen.
    await tester.tap(dashes.at(2));
    await tester.pumpAndSettle();
    expect(tester.getSize(dashes.at(2)).width, 8);
    expect(tester.getSize(dashes.at(3)).width, 5.6);
  });

  testWidgets('conversation nav stays hidden below three rounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nav = find.byKey(const ValueKey('memory-conversation-nav'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryPage(
            localDataState: _localDataState(),
            conversationService: _FakeMemoryConversationService(
              initialMessages: [
                MemoryMessage(
                  role: 'user',
                  content: '唯一的问题',
                  createdAt: DateTime(2026, 7, 8),
                ),
                MemoryMessage(
                  role: 'ai',
                  content: '唯一的回答',
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

    // Only the message bubble — a single round means no nav.
    expect(find.text('唯一的问题'), findsOneWidget);
    expect(nav, findsNothing);

    // Two rounds are still not enough to show the nav. A different data
    // directory makes didUpdateWidget reload the conversation.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryPage(
            localDataState: _localDataState(
              dataDirectory: 'D:\\Temp\\SpringNoteTwoRounds',
            ),
            conversationService: _FakeMemoryConversationService(
              initialMessages: [
                for (var index = 1; index <= 2; index++) ...[
                  MemoryMessage(
                    role: 'user',
                    content: '问题 $index',
                    createdAt: DateTime(2026, 7, 8, 10, index),
                  ),
                  MemoryMessage(
                    role: 'ai',
                    content: '回答 $index',
                    createdAt: DateTime(2026, 7, 8, 11, index),
                  ),
                ],
              ],
            ),
            searchService: const _FakeMemorySearchService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('问题 2'), findsOneWidget);
    expect(nav, findsNothing);
  });

  testWidgets('conversation nav stays hidden on narrow windows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 760);
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
                  role: 'user',
                  content: '问题一',
                  createdAt: DateTime(2026, 7, 8),
                ),
                MemoryMessage(
                  role: 'ai',
                  content: '回答一',
                  createdAt: DateTime(2026, 7, 8),
                ),
                MemoryMessage(
                  role: 'user',
                  content: '问题二',
                  createdAt: DateTime(2026, 7, 8, 11),
                ),
                MemoryMessage(
                  role: 'ai',
                  content: '回答二',
                  createdAt: DateTime(2026, 7, 8, 11),
                ),
                MemoryMessage(
                  role: 'user',
                  content: '问题三',
                  createdAt: DateTime(2026, 7, 8, 12),
                ),
                MemoryMessage(
                  role: 'ai',
                  content: '回答三',
                  createdAt: DateTime(2026, 7, 8, 12),
                ),
              ],
            ),
            searchService: const _FakeMemorySearchService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 700 is below the minimal sane page width: no nav at all.
    expect(find.byKey(const ValueKey('memory-conversation-nav')), findsNothing);
    expect(find.text('问题一'), findsOneWidget);
    expect(find.text('问题二'), findsOneWidget);
  });

  testWidgets('conversation nav caps the rail and tracks the last round', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String longAnswer(int index) =>
        '回答 $index\n${List.filled(12, '这是一段很长的回答内容，用来撑开滚动高度。').join('\n')}';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryPage(
            localDataState: _localDataState(),
            conversationService: _FakeMemoryConversationService(
              initialMessages: [
                for (var index = 1; index <= 12; index++) ...[
                  MemoryMessage(
                    role: 'user',
                    content: '问题 $index',
                    createdAt: DateTime(2026, 7, 8, 10, index),
                  ),
                  MemoryMessage(
                    role: 'ai',
                    // The last answer stays short so the final bubble is
                    // still visible on screen at the bottom of the list.
                    content: index == 12 ? '简短回答' : longAnswer(index),
                    createdAt: DateTime(2026, 7, 8, 11, index),
                  ),
                ],
              ],
            ),
            searchService: const _FakeMemorySearchService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nav = find.byKey(const ValueKey('memory-conversation-nav'));
    final dashes = find.descendant(
      of: nav,
      matching: find.byType(AnimatedContainer),
    );
    // The rail never shows more than 9 dashes even with 12 rounds.
    expect(dashes, findsNWidgets(9));

    final listScrollable = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((state) => state.position.maxScrollExtent > 0);
    unawaited(
      listScrollable.position.animateTo(
        listScrollable.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      ),
    );
    await tester.pumpAndSettle();

    // At the bottom the highlight reaches the last round: the 9-dash
    // window slid down and the final dash is the long active one.
    expect(dashes, findsNWidgets(9));
    expect(tester.getSize(dashes.at(8)).width, 8);

    // Inactive dashes alternate thick (3px) and thin (1.5px) by parity:
    // the window starts at round 3, so the first dash is the thin one.
    expect(tester.getSize(dashes.at(0)).height, 1.5);
    expect(tester.getSize(dashes.at(1)).height, 3);
  });

  testWidgets('conversation nav card scrollbar stays clear of the dashes', (
    tester,
  ) async {
    // The hover card relies on the desktop scroll behavior's scrollbar.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1400, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String longAnswer(int index) =>
        '回答 $index\n${List.filled(12, '这是一段很长的回答内容，用来撑开滚动高度。').join('\n')}';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoryPage(
            localDataState: _localDataState(),
            conversationService: _FakeMemoryConversationService(
              initialMessages: [
                for (var index = 1; index <= 12; index++) ...[
                  MemoryMessage(
                    role: 'user',
                    content: '问题 $index',
                    createdAt: DateTime(2026, 7, 8, 10, index),
                  ),
                  MemoryMessage(
                    role: 'ai',
                    content: longAnswer(index),
                    createdAt: DateTime(2026, 7, 8, 11, index),
                  ),
                ],
              ],
            ),
            searchService: const _FakeMemorySearchService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nav = find.byKey(const ValueKey('memory-conversation-nav'));
    final cardList = find.descendant(of: nav, matching: find.byType(ListView));
    final scrollbar = find.descendant(
      of: nav,
      matching: find.byType(Scrollbar),
    );
    // Collapsed there is no card, no list and no scrollbar at all.
    expect(cardList, findsNothing);
    expect(scrollbar, findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(nav));
    await tester.pump(const Duration(milliseconds: 150));

    // The desktop scroll behavior adds exactly one platform scrollbar.
    expect(cardList, findsOneWidget);
    expect(scrollbar, findsOneWidget);

    // It stays a slim 3px even when hovered.
    final scrollbarTheme = tester.widget<ScrollbarTheme>(
      find.descendant(of: nav, matching: find.byType(ScrollbarTheme)),
    );
    expect(scrollbarTheme.data.thickness!.resolve({WidgetState.hovered}), 3);

    // The list reaches almost to the card's right edge, so the platform
    // scrollbar sits in the right padding, clear of the dashes.
    final firstDash = find
        .descendant(of: nav, matching: find.byType(AnimatedContainer))
        .first;
    expect(
      tester.getRect(cardList).right - tester.getRect(firstDash).right,
      greaterThanOrEqualTo(10),
    );

    // The framework asserts debug overrides are unset before tearDown runs.
    debugDefaultTargetPlatformOverride = null;
  });
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

class _DelayedMemoryAiClientService extends AiClientService {
  final StreamController<rust_ai.MemoryToolChatStreamEvent> _controller =
      StreamController();
  bool started = false;
  List<MemoryMessage>? capturedMessages;

  @override
  Future<Stream<rust_ai.MemoryToolChatStreamEvent>?> memoryToolChatStream({
    required String appDataDir,
    required AppConfig config,
    required List<MemoryMessage> messages,
    required bool thinkingEnabled,
    required String reasoningEffort,
  }) async {
    started = true;
    capturedMessages = messages;
    return _controller.stream;
  }

  void complete() {
    _controller
      ..add(
        const rust_ai.MemoryToolChatStreamEvent(
          eventType: 'done',
          contentDelta: '',
          reasoningDelta: '',
          content: '回答完成',
          reasoningContent: '',
          toolCalls: [],
          errorCode: '',
          errorMessage: '',
          inputTokens: 0,
          outputTokens: 0,
          cachedTokens: 0,
        ),
      )
      ..close();
  }

  Future<void> dispose() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

LocalDataState _localDataState({
  String dataDirectory = 'D:\\Temp\\SpringNote',
  String dailyNotesDirectory = 'D:\\Temp\\SpringNote\\notes\\daily',
  String weeklyNotesDirectory = 'D:\\Temp\\SpringNote\\notes\\weekly',
  String monthlyNotesDirectory = 'D:\\Temp\\SpringNote\\notes\\monthly',
  AppConfig? config,
}) {
  return LocalDataState(
    dataDirectory: dataDirectory,
    configPath: _joinPath(dataDirectory, 'config.json'),
    dailyNotesDirectory: dailyNotesDirectory,
    weeklyNotesDirectory: weeklyNotesDirectory,
    monthlyNotesDirectory: monthlyNotesDirectory,
    config: config ?? AppConfig.defaults(),
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

class _FakePendingImageClipboardService extends PendingImageClipboardService {
  _FakePendingImageClipboardService(this.images);

  final List<PendingImage> images;

  @override
  Future<List<PendingImage>> readPendingImages() async => images;
}

class _ImageCapableMemoryAiClientService extends AiClientService {
  const _ImageCapableMemoryAiClientService();

  @override
  bool memoryModelSupportsImageInput(AppConfig config) => true;

  @override
  Future<Stream<rust_ai.MemoryToolChatStreamEvent>?> memoryToolChatStream({
    required String appDataDir,
    required AppConfig config,
    required List<MemoryMessage> messages,
    required bool thinkingEnabled,
    required String reasoningEffort,
  }) async {
    return const Stream.empty();
  }
}
