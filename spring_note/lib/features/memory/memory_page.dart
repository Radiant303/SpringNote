import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/models/local_data_state.dart';
import '../../core/models/memory_message.dart';
import '../../core/services/ai_client_service.dart';
import '../../core/services/memory_conversation_service.dart';
import '../../core/services/memory_search_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/markdown_code_block.dart';

bool shouldCollapseMemoryReasoning(MemoryMessage message) {
  return message.content.trim().isNotEmpty || message.toolCalls.isNotEmpty;
}

String memoryToolResultLabel(MemoryMessage? resultMessage) {
  final resultCount = resultMessage?.sources.length ?? 0;
  if (resultCount > 0) {
    return '$resultCount 条结果';
  }
  if (resultMessage?.content.trim().isNotEmpty ?? false) {
    return '已返回';
  }
  return '无结果';
}

Duration? memoryReasoningDuration(MemoryMessage message) {
  final milliseconds = message.reasoningDurationMs;
  if (milliseconds == null || milliseconds < 0) {
    return null;
  }
  return Duration(milliseconds: milliseconds);
}

class MemoryPage extends StatefulWidget {
  const MemoryPage({
    super.key,
    required this.localDataState,
    this.aiClientService = const AiClientService(),
    this.conversationService = const MemoryConversationService(),
    this.searchService = const MemorySearchService(),
  });

  final LocalDataState localDataState;
  final AiClientService aiClientService;
  final MemoryConversationService conversationService;
  final MemorySearchService searchService;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  final TextEditingController _entryController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _entryFocusNode = FocusNode();
  final FocusNode _chatFocusNode = FocusNode();

  List<MemoryMessage> _messages = [];
  bool _loading = true;
  bool _answering = false;
  bool _waitingForMemoryResponse = false;
  bool _thinkingEnabled = true;
  String _reasoningEffort = 'high';
  Timer? _reasoningDurationTimer;
  int? _reasoningDurationMessageIndex;
  DateTime? _reasoningDurationStartedAt;

  bool get _inChat => _messages.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void didUpdateWidget(covariant MemoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.localDataState.dataDirectory !=
        oldWidget.localDataState.dataDirectory) {
      _loadMessages();
    }
  }

  @override
  void dispose() {
    _stopReasoningDurationTimer();
    _entryController.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    _entryFocusNode.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final messages = await widget.conversationService.readMessages(
      appDataDir: widget.localDataState.dataDirectory,
    );
    if (mounted) {
      setState(() {
        _messages = messages;
        _waitingForMemoryResponse = false;
        _loading = false;
      });
    }
  }

  Future<void> _newConversation() async {
    _stopReasoningDurationTimer();
    await widget.conversationService.clear(
      appDataDir: widget.localDataState.dataDirectory,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _messages = [];
      _answering = false;
      _waitingForMemoryResponse = false;
      _entryController.clear();
      _chatController.clear();
    });
    _entryFocusNode.requestFocus();
  }

  Future<void> _sendFromEntry() => _send(_entryController.text);

  Future<void> _sendFromChat() => _send(_chatController.text);

  Future<void> _send(String rawQuestion) async {
    final question = rawQuestion.trim();
    if (question.isEmpty || _answering) {
      return;
    }

    final now = DateTime.now();
    final userMessage = MemoryMessage(
      role: 'user',
      content: question,
      createdAt: now,
    );

    setState(() {
      _messages = [..._messages, userMessage];
      _answering = true;
      _waitingForMemoryResponse = false;
      _entryController.clear();
      _chatController.clear();
    });
    await _persist();
    _scrollToBottom();

    final aiMessage = await _runToolCallingLoop(question);
    if (!mounted) {
      return;
    }
    setState(() {
      if (aiMessage != null) {
        _messages = [..._messages, aiMessage];
      }
      _waitingForMemoryResponse = false;
      _answering = false;
    });
    await _persist();
    _scrollToBottom();
    _chatFocusNode.requestFocus();
  }

  Future<MemoryMessage?> _runToolCallingLoop(String question) async {
    final maxTurns = widget.localDataState.config.memorySearchLimit
        .round()
        .clamp(1, 12);
    final turnSources = <MemorySource>[];

    for (var turn = 0; turn < maxTurns; turn++) {
      final requestStartedAt = DateTime.now();
      _setWaitingForMemoryResponse(true);
      final stream = widget.aiClientService.memoryToolChatStream(
        appDataDir: widget.localDataState.dataDirectory,
        config: widget.localDataState.config,
        messages: _messages,
        thinkingEnabled: _thinkingEnabled,
        reasoningEffort: _reasoningEffort,
      );

      if (stream == null) {
        _setWaitingForMemoryResponse(false);
        _stopReasoningDurationTimer();
        return _fallbackLocalAnswer(question);
      }

      var visibleIndex = -1;
      var content = '';
      var reasoningContent = '';
      int? reasoningDurationMs;
      var toolCalls = <MemoryToolCallMessage>[];
      await for (final event in stream) {
        if (event.eventType == 'error') {
          _setWaitingForMemoryResponse(false);
          _stopReasoningDurationTimer();
          return MemoryMessage(
            role: 'ai',
            content: event.errorMessage.trim().isEmpty
                ? '模型请求失败。'
                : event.errorMessage.trim(),
            createdAt: DateTime.now(),
            sources: turnSources,
          );
        }
        if (event.eventType == 'delta') {
          content = event.content;
          reasoningContent = event.reasoningContent;
          final hasReasoning = reasoningContent.trim().isNotEmpty;
          final hasContent = content.trim().isNotEmpty;
          if (hasReasoning && hasContent) {
            reasoningDurationMs ??= _reasoningDurationMs(
              reasoningContent,
              requestStartedAt,
            );
            _stopReasoningDurationTimer();
          }
          if (_hasVisibleModelOutput(content, reasoningContent)) {
            _setWaitingForMemoryResponse(false);
          }
          visibleIndex = _upsertStreamingMessage(
            visibleIndex,
            content: content,
            reasoningContent: reasoningContent,
            requestStartedAt: requestStartedAt,
            reasoningDurationMs: reasoningDurationMs,
            sources: turnSources,
          );
          if (hasReasoning && reasoningDurationMs == null) {
            _startReasoningDurationTimer(visibleIndex, requestStartedAt);
          }
          _scrollToBottom();
        }
        if (event.eventType == 'done') {
          content = event.content;
          reasoningContent = event.reasoningContent;
          _setWaitingForMemoryResponse(false);
          reasoningDurationMs ??= _reasoningDurationMs(
            reasoningContent,
            requestStartedAt,
          );
          _stopReasoningDurationTimer();
          toolCalls = event.toolCalls
              .map(
                (toolCall) => MemoryToolCallMessage(
                  id: toolCall.id,
                  name: toolCall.name,
                  arguments: toolCall.arguments,
                ),
              )
              .toList();
        }
      }
      _stopReasoningDurationTimer();

      if (toolCalls.isEmpty) {
        final finalMessage = MemoryMessage(
          role: 'ai',
          content: content.trim().isEmpty ? '我没有拿到可用回答。' : content.trim(),
          reasoningContent: reasoningContent.trim(),
          reasoningDurationMs: reasoningDurationMs,
          createdAt: DateTime.now(),
          sources: turnSources,
        );
        if (visibleIndex >= 0) {
          setState(() {
            final updated = [..._messages];
            updated[visibleIndex] = finalMessage;
            _messages = updated;
          });
          await _persist();
          return null;
        }
        return finalMessage;
      }

      final assistantToolMessage = MemoryMessage(
        role: 'assistant',
        content: content,
        reasoningContent: reasoningContent,
        reasoningDurationMs: reasoningDurationMs,
        createdAt: DateTime.now(),
        toolCalls: toolCalls,
      );
      setState(() {
        if (visibleIndex >= 0 && visibleIndex < _messages.length) {
          final updated = [..._messages];
          updated[visibleIndex] = assistantToolMessage;
          _messages = updated;
        } else {
          _messages = [..._messages, assistantToolMessage];
        }
      });
      await _persist();

      for (final toolCall in toolCalls) {
        final execution = await widget.searchService.executeTool(
          localDataState: widget.localDataState,
          toolName: toolCall.name,
          arguments: _decodeToolArguments(toolCall.arguments),
          limit: maxTurns,
        );
        turnSources.addAll(execution.sources);
        final toolMessage = MemoryMessage(
          role: 'tool',
          content: execution.content,
          createdAt: DateTime.now(),
          toolName: execution.toolName,
          toolCallId: toolCall.id,
          sources: execution.sources,
        );
        setState(() => _messages = [..._messages, toolMessage]);
        await _persist();
      }
    }

    return MemoryMessage(
      role: 'ai',
      content: '工具调用轮次已达到上限。请把问题缩小到具体日期、项目名或关键词后再试。',
      createdAt: DateTime.now(),
      sources: turnSources,
    );
  }

  bool _hasVisibleModelOutput(String content, String reasoningContent) {
    return content.trim().isNotEmpty || reasoningContent.trim().isNotEmpty;
  }

  int? _reasoningDurationMs(
    String reasoningContent,
    DateTime requestStartedAt,
  ) {
    if (reasoningContent.trim().isEmpty) {
      return null;
    }
    final milliseconds = DateTime.now()
        .difference(requestStartedAt)
        .inMilliseconds;
    return milliseconds < 0 ? 0 : milliseconds;
  }

  void _startReasoningDurationTimer(
    int messageIndex,
    DateTime requestStartedAt,
  ) {
    if (messageIndex < 0) {
      return;
    }
    if (_reasoningDurationMessageIndex == messageIndex &&
        _reasoningDurationStartedAt == requestStartedAt &&
        _reasoningDurationTimer != null) {
      _refreshReasoningDuration();
      return;
    }

    _stopReasoningDurationTimer();
    _reasoningDurationMessageIndex = messageIndex;
    _reasoningDurationStartedAt = requestStartedAt;
    _reasoningDurationTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _refreshReasoningDuration(),
    );
    _refreshReasoningDuration();
  }

  void _stopReasoningDurationTimer() {
    _reasoningDurationTimer?.cancel();
    _reasoningDurationTimer = null;
    _reasoningDurationMessageIndex = null;
    _reasoningDurationStartedAt = null;
  }

  void _refreshReasoningDuration() {
    if (!mounted) {
      _stopReasoningDurationTimer();
      return;
    }
    final messageIndex = _reasoningDurationMessageIndex;
    final startedAt = _reasoningDurationStartedAt;
    if (messageIndex == null ||
        startedAt == null ||
        messageIndex < 0 ||
        messageIndex >= _messages.length) {
      _stopReasoningDurationTimer();
      return;
    }

    final message = _messages[messageIndex];
    if (message.reasoningContent.trim().isEmpty) {
      return;
    }

    final reasoningDurationMs = _elapsedMillisecondsSince(startedAt);
    if (message.reasoningDurationMs == reasoningDurationMs) {
      return;
    }

    setState(() {
      if (messageIndex >= _messages.length) {
        return;
      }
      final current = _messages[messageIndex];
      if (current.reasoningContent.trim().isEmpty) {
        return;
      }
      final updated = [..._messages];
      updated[messageIndex] = _copyMemoryMessageWithDuration(
        current,
        reasoningDurationMs,
      );
      _messages = updated;
    });
  }

  int _elapsedMillisecondsSince(DateTime startedAt) {
    final milliseconds = DateTime.now().difference(startedAt).inMilliseconds;
    return milliseconds < 0 ? 0 : milliseconds;
  }

  MemoryMessage _copyMemoryMessageWithDuration(
    MemoryMessage message,
    int reasoningDurationMs,
  ) {
    return MemoryMessage(
      role: message.role,
      content: message.content,
      createdAt: message.createdAt,
      reasoningContent: message.reasoningContent,
      reasoningDurationMs: reasoningDurationMs,
      toolName: message.toolName,
      toolCallId: message.toolCallId,
      toolCalls: message.toolCalls,
      sources: message.sources,
    );
  }

  void _setWaitingForMemoryResponse(bool value) {
    if (!mounted || _waitingForMemoryResponse == value) {
      return;
    }
    setState(() => _waitingForMemoryResponse = value);
    if (value) {
      _scrollToBottom();
    }
  }

  int _upsertStreamingMessage(
    int visibleIndex, {
    required String content,
    required String reasoningContent,
    required DateTime requestStartedAt,
    required int? reasoningDurationMs,
    required List<MemorySource> sources,
  }) {
    final message = MemoryMessage(
      role: 'ai',
      content: content,
      reasoningContent: reasoningContent,
      reasoningDurationMs:
          reasoningDurationMs ??
          _reasoningDurationMs(reasoningContent, requestStartedAt),
      createdAt: DateTime.now(),
      sources: sources,
    );
    if (visibleIndex >= 0 && visibleIndex < _messages.length) {
      setState(() {
        final updated = [..._messages];
        updated[visibleIndex] = message;
        _messages = updated;
      });
      return visibleIndex;
    }
    setState(() {
      _messages = [..._messages, message];
    });
    return _messages.length - 1;
  }

  Map<String, Object?> _decodeToolArguments(String rawArguments) {
    Object? decoded;
    try {
      decoded = jsonDecode(rawArguments.isEmpty ? '{}' : rawArguments);
    } on FormatException {
      return {};
    }
    if (decoded is! Map) {
      return {};
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<MemoryMessage> _fallbackLocalAnswer(String question) async {
    final recall = await widget.searchService.recall(
      localDataState: widget.localDataState,
      question: question,
      limit: widget.localDataState.config.memorySearchLimit.round(),
    );
    final toolMessages = recall.steps.map((step) => step.toMessage()).toList();
    setState(() => _messages = [..._messages, ...toolMessages]);
    await _persist();
    return MemoryMessage(
      role: 'ai',
      content: _mockAnswer(question, recall),
      createdAt: DateTime.now(),
      sources: recall.sources,
    );
  }

  Future<void> _persist() {
    return widget.conversationService.saveMessages(
      appDataDir: widget.localDataState.dataDirectory,
      messages: _messages,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _mockAnswer(String question, MemoryRecallResult recall) {
    if (recall.sources.isEmpty) {
      return '## AI 回答\n\n我还没有在日报、周报或月报中检索到和「$question」直接相关的记录。你可以换一个更具体的关键词，例如项目名、模块名、问题现象或日期。';
    }
    final toolList = recall.steps
        .map(
          (step) =>
              '- Thought：${step.thought}\n  Act：${step.tool.label}（${step.tool.query}）\n  Observation：${step.observation}',
        )
        .join('\n');
    final sourceList = recall.sources
        .take(3)
        .map((source) => '- **${source.title}**：${source.snippet}')
        .join('\n');
    return '## 使用的工具\n\n$toolList\n\n## 找到的相关回忆\n\n$sourceList\n\n---\n\n## AI 回答\n\n当前未配置可用的回忆书模型，所以先基于本地工具检索给出摘要。上面这些记录可能和「$question」有关，你可以配置回忆书模型后获得更完整的解释、归纳和追问建议。';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _MemoryHeader(
            thinkingEnabled: _thinkingEnabled,
            reasoningEffort: _reasoningEffort,
            onThinkingEnabledChanged: (value) =>
                setState(() => _thinkingEnabled = value),
            onReasoningEffortChanged: (value) =>
                setState(() => _reasoningEffort = value),
            onNewConversation: _newConversation,
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _inChat ? _buildChatState() : _buildEntryState(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryState() {
    return Center(
      key: const ValueKey('memory-entry'),
      child: Transform.translate(
        offset: const Offset(0, -80),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '准备好了，随时开始',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 22),
              _MemoryComposer(
                controller: _entryController,
                focusNode: _entryFocusNode,
                hintText: '问问你的回忆...',
                answering: _answering,
                onSubmit: _sendFromEntry,
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _QuickPromptChip(
                    icon: Icons.history_rounded,
                    label: '查看今天日报',
                    onTap: () => _send('查看今天的日报'),
                  ),
                  _QuickPromptChip(
                    icon: Icons.auto_awesome_rounded,
                    label: '查看本周日报',
                    onTap: () => _send('查看本周的日报'),
                  ),
                  _QuickPromptChip(
                    icon: Icons.calendar_month_rounded,
                    label: '查看本月月报',
                    onTap: () => _send('查看本月月报'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatState() {
    final visibleMessages = _messages
        .where(
          (message) =>
              message.role == 'user' ||
              message.role == 'ai' ||
              (message.role == 'assistant' &&
                  (message.content.trim().isNotEmpty ||
                      message.reasoningContent.trim().isNotEmpty ||
                      message.toolCalls.isNotEmpty)),
        )
        .toList();

    return Stack(
      key: const ValueKey('memory-chat'),
      children: [
        ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 150),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final message in visibleMessages)
                      _MemoryMessageView(
                        message: message,
                        attachments: _toolAttachmentsFor(message),
                      ),
                    if (_waitingForMemoryResponse)
                      const _MemoryWaitingIndicator(),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 132,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00FFFFFF), Colors.white, Colors.white],
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _MemoryComposer(
                  controller: _chatController,
                  focusNode: _chatFocusNode,
                  hintText: '继续追问你的回忆...',
                  answering: _answering,
                  onSubmit: _sendFromChat,
                  multiline: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<_MemoryToolAttachment> _toolAttachmentsFor(MemoryMessage message) {
    if (message.toolCalls.isEmpty) {
      return const [];
    }
    final toolMessages = {
      for (final item in _messages)
        if (item.role == 'tool' && item.toolCallId != null)
          item.toolCallId!: item,
    };
    return message.toolCalls
        .map(
          (toolCall) => _MemoryToolAttachment(
            toolCall: toolCall,
            resultMessage: toolMessages[toolCall.id],
          ),
        )
        .toList();
  }
}

class _MemoryHeader extends StatelessWidget {
  const _MemoryHeader({
    required this.thinkingEnabled,
    required this.reasoningEffort,
    required this.onThinkingEnabledChanged,
    required this.onReasoningEffortChanged,
    required this.onNewConversation,
  });

  final bool thinkingEnabled;
  final String reasoningEffort;
  final ValueChanged<bool> onThinkingEnabledChanged;
  final ValueChanged<String> onReasoningEffortChanged;
  final VoidCallback onNewConversation;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Text(
            '回忆书',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppTheme.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          _ThinkingControl(
            enabled: thinkingEnabled,
            effort: reasoningEffort,
            onEnabledChanged: onThinkingEnabledChanged,
            onEffortChanged: onReasoningEffortChanged,
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: '开启新对话',
            onPressed: onNewConversation,
            style: IconButton.styleFrom(
              fixedSize: const Size(34, 34),
              minimumSize: const Size(34, 34),
              maximumSize: const Size(34, 34),
              backgroundColor: Colors.transparent,
              hoverColor: const Color(0xFFEDEDED),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const _MemoryNewConversationIcon(
              size: 17,
              color: AppTheme.textSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryNewConversationIcon extends StatelessWidget {
  const _MemoryNewConversationIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CustomPaint(
        size: Size.square(size),
        painter: _MemoryNewConversationPainter(color: color),
      ),
    );
  }
}

class _MemoryNewConversationPainter extends CustomPainter {
  const _MemoryNewConversationPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24;
    final sy = size.height / 24;
    final strokeScale = sx < sy ? sx : sy;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * strokeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bubblePath = Path()
      ..moveTo(7.4 * sx, 19.2 * sy)
      ..lineTo(4 * sx, 20 * sy)
      ..lineTo(4.8 * sx, 16.7 * sy)
      ..cubicTo(3.65 * sx, 15.35 * sy, 3 * sx, 13.72 * sy, 3 * sx, 12 * sy)
      ..cubicTo(3 * sx, 7.04 * sy, 7.5 * sx, 3 * sy, 13 * sx, 3 * sy)
      ..cubicTo(18.4 * sx, 3 * sy, 22 * sx, 6.45 * sy, 22 * sx, 11 * sy)
      ..cubicTo(22 * sx, 15.65 * sy, 18.08 * sx, 19.4 * sy, 13 * sx, 19.4 * sy)
      ..cubicTo(10.82 * sx, 19.4 * sy, 9 * sx, 19.05 * sy, 7.4 * sx, 19.2 * sy);

    for (final metric in bubblePath.computeMetrics()) {
      var distance = 0.0;
      final dashLength = 3.4 * strokeScale;
      final gapLength = 2.7 * strokeScale;
      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MemoryNewConversationPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _MemoryComposer extends StatelessWidget {
  const _MemoryComposer({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.answering,
    required this.onSubmit,
    this.multiline = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final bool answering;
  final VoidCallback onSubmit;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(7, 5, 8, 5),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A171717),
            blurRadius: 28,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: null,
            icon: const Icon(Icons.add_rounded),
            color: AppTheme.text,
            disabledColor: AppTheme.text,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: !answering,
              minLines: 1,
              maxLines: multiline ? 3 : 1,
              textInputAction: multiline
                  ? TextInputAction.newline
                  : TextInputAction.send,
              onSubmitted: multiline ? null : (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: hintText,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isDense: true,
              ),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          IconButton.filled(
            onPressed: answering ? null : onSubmit,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.text,
              disabledBackgroundColor: const Color(0xFFE0E0E0),
            ),
            icon: answering
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.textSubtle,
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _QuickPromptChip extends StatelessWidget {
  const _QuickPromptChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: AppTheme.textSubtle),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textMuted,
        side: const BorderSide(color: AppTheme.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        minimumSize: const Size(0, 36),
        textStyle: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _ThinkingControl extends StatelessWidget {
  const _ThinkingControl({
    required this.enabled,
    required this.effort,
    required this.onEnabledChanged,
    required this.onEffortChanged,
  });

  final bool enabled;
  final String effort;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String> onEffortChanged;

  @override
  Widget build(BuildContext context) {
    final value = enabled ? effort : 'disabled';
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, height: 1);

    final selectedIndex = switch (value) {
      'high' => 1,
      'max' => 2,
      _ => 0,
    };

    return SizedBox(
      width: 214,
      height: 36,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / 3;
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEDEDED),
              border: Border.all(color: const Color(0xFFE0E0E0)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  left: selectedIndex * segmentWidth + 3,
                  top: 3,
                  width: segmentWidth - 6,
                  height: 28,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14171717),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    _ThinkingSegment(
                      label: 'Disable',
                      selected: selectedIndex == 0,
                      style: labelStyle,
                      onTap: () => onEnabledChanged(false),
                    ),
                    _ThinkingSegment(
                      label: 'High',
                      selected: selectedIndex == 1,
                      style: labelStyle,
                      onTap: () {
                        if (!enabled) {
                          onEnabledChanged(true);
                        }
                        onEffortChanged('high');
                      },
                    ),
                    _ThinkingSegment(
                      label: 'Max',
                      selected: selectedIndex == 2,
                      style: labelStyle,
                      onTap: () {
                        if (!enabled) {
                          onEnabledChanged(true);
                        }
                        onEffortChanged('max');
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ThinkingSegment extends StatelessWidget {
  const _ThinkingSegment({
    required this.label,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final TextStyle? style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 140),
            style:
                style?.copyWith(
                  color: selected ? AppTheme.text : AppTheme.textSubtle,
                ) ??
                TextStyle(
                  color: selected ? AppTheme.text : AppTheme.textSubtle,
                ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class _MemoryMessageView extends StatelessWidget {
  const _MemoryMessageView({required this.message, required this.attachments});

  final MemoryMessage message;
  final List<_MemoryToolAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final messageWidth = constraints.maxWidth < 820
            ? constraints.maxWidth
            : 820.0;
        return Center(
          child: SizedBox(width: messageWidth, child: _buildMessage(context)),
        );
      },
    );
  }

  Widget _buildMessage(BuildContext context) {
    if (message.role == 'user') {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          margin: const EdgeInsets.only(bottom: 28),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(22),
          ),
          child: SelectableText(
            message.content,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppTheme.text, height: 1.7),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 36),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.reasoningContent.trim().isNotEmpty) ...[
              _ReasoningBlock(
                reasoning: message.reasoningContent,
                duration: memoryReasoningDuration(message),
                collapsed: shouldCollapseMemoryReasoning(message),
              ),
              const SizedBox(height: 12),
            ],
            if (message.content.trim().isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: GptMarkdown(
                  message.content,
                  codeBuilder: (context, name, code, closed) =>
                      MarkdownCodeBlock(language: name, code: code),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.textMuted,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ),
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 14),
              _ToolAttachmentStrip(attachments: attachments),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemoryWaitingIndicator extends StatelessWidget {
  const _MemoryWaitingIndicator();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          child: Row(
            children: [
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.textSubtle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '正在思考并调用工具...',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSubtle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryToolAttachment {
  const _MemoryToolAttachment({
    required this.toolCall,
    required this.resultMessage,
  });

  final MemoryToolCallMessage toolCall;
  final MemoryMessage? resultMessage;
}

class _ToolAttachmentStrip extends StatelessWidget {
  const _ToolAttachmentStrip({required this.attachments});

  final List<_MemoryToolAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final attachment in attachments)
          _ToolAttachmentChip(attachment: attachment),
      ],
    );
  }
}

class _ToolAttachmentChip extends StatelessWidget {
  const _ToolAttachmentChip({required this.attachment});

  final _MemoryToolAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final resultLabel = memoryToolResultLabel(attachment.resultMessage);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        onTap: () => _showToolDialog(context, attachment),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _toolLabel(attachment.toolCall.name),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                resultLabel,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.textSubtle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showToolDialog(BuildContext context, _MemoryToolAttachment attachment) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.build_circle_outlined,
                      size: 20,
                      color: AppTheme.text,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _toolLabel(attachment.toolCall.name),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppTheme.text,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ToolDetailBlock(
                          title: '工具名称',
                          content: attachment.toolCall.name,
                        ),
                        _ToolDetailBlock(
                          title: '传入参数',
                          content: _prettyJson(attachment.toolCall.arguments),
                        ),
                        _ToolDetailBlock(
                          title: '返回结果',
                          content: _prettyJson(
                            attachment.resultMessage?.content ?? '暂无返回结果',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _prettyJson(String raw) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(jsonDecode(raw));
    } on FormatException {
      return raw;
    }
  }

  String _toolLabel(String name) {
    return switch (name) {
      'get_current_date' => '获取当前日期',
      'keyword_search' => '关键词搜索',
      'read_daily_note' => '读取日报',
      'read_week_daily_notes' => '读取周内日报',
      'read_month_report' => '读取月报',
      _ => name,
    };
  }
}

class _ToolDetailBlock extends StatelessWidget {
  const _ToolDetailBlock({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppTheme.textSubtle,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              content,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textMuted,
                height: 1.55,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasoningBlock extends StatefulWidget {
  const _ReasoningBlock({
    required this.reasoning,
    required this.duration,
    required this.collapsed,
  });

  final String reasoning;
  final Duration? duration;
  final bool collapsed;

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  late bool _expanded;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _expanded = !widget.collapsed;
  }

  @override
  void didUpdateWidget(covariant _ReasoningBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.collapsed && widget.collapsed) {
      _expanded = false;
    }
    if (_expanded &&
        !widget.collapsed &&
        widget.reasoning != oldWidget.reasoning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) {
          return;
        }
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: AppTheme.textSubtle,
      fontWeight: FontWeight.w700,
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_outlined,
                      size: 17,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: '深度思考'),
                            if (widget.duration != null)
                              TextSpan(
                                text:
                                    ' (${_formatReasoningDuration(widget.duration!)})',
                                style: titleStyle?.copyWith(
                                  color: const Color(0xB36B7280),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        style: titleStyle,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppTheme.textSubtle,
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildReasoningBody(context),
        ],
      ),
    );
  }

  String _formatReasoningDuration(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(1)}s';
    }
    final minutes = seconds / 60;
    return '${minutes.toStringAsFixed(1)}m';
  }

  Widget _buildReasoningBody(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AppTheme.textSubtle, height: 1.65);
    final text = Text(widget.reasoning.trim(), style: style);
    final body = widget.collapsed
        ? Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: SizedBox(width: double.infinity, child: text),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: SizedBox(
              width: double.infinity,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 118),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  child: text,
                ),
              ),
            ),
          );

    return ClipRect(
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topCenter,
        heightFactor: _expanded ? 1 : 0,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          opacity: _expanded ? 1 : 0,
          child: IgnorePointer(ignoring: !_expanded, child: body),
        ),
      ),
    );
  }
}
