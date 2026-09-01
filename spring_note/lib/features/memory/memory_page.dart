import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/models/local_data_state.dart';
import '../../core/models/memory_message.dart';
import '../../core/attachments/pending_image.dart';
import '../../core/services/ai_client_service.dart';
import '../../core/services/memory_conversation_service.dart';
import '../../core/services/memory_search_service.dart';
import '../../core/services/pending_image_clipboard_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/spring_tree.dart';
import 'memory_input_modes.dart';
import '../../core/widgets/spring_markdown.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';

bool shouldCollapseMemoryReasoning(MemoryMessage message) {
  return message.content.trim().isNotEmpty || message.toolCalls.isNotEmpty;
}

String memoryToolResultLabel(
  AppLocalizations strings,
  MemoryMessage? resultMessage,
) {
  final resultCount = resultMessage?.sources.length ?? 0;
  if (resultCount > 0) {
    return strings.memoryToolResultCount(resultCount);
  }
  if (resultMessage?.content.trim().isNotEmpty ?? false) {
    return strings.memoryToolResultReturned;
  }
  return strings.memoryToolResultNone;
}

String memoryToolCacheKey(String toolName, Map<String, Object?> arguments) {
  return '$toolName:${jsonEncode(_normalizeJsonValue(arguments))}';
}

String deduplicatedMemoryToolContent(String content) {
  final trimmed = content.trim();
  return jsonEncode({
    'cached': true,
    'note':
        'This exact tool call already returned earlier in this conversation. Use the cached result and continue to answer instead of calling the same tool again.',
    'result': trimmed.isEmpty ? content : trimmed,
  });
}

Duration? memoryReasoningDuration(MemoryMessage message) {
  final milliseconds = message.reasoningDurationMs;
  if (milliseconds == null || milliseconds < 0) {
    return null;
  }
  return Duration(milliseconds: milliseconds);
}

Object? _normalizeJsonValue(Object? value) {
  if (value is Map) {
    final entries =
        value.entries
            .map((entry) => MapEntry(entry.key.toString(), entry.value))
            .toList()
          ..sort((left, right) => left.key.compareTo(right.key));
    return {
      for (final entry in entries) entry.key: _normalizeJsonValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_normalizeJsonValue).toList();
  }
  return value;
}

bool _usesPlainLightMemoryColors(
  BuildContext context,
  SpringThemeColors colors,
) {
  return Theme.of(context).brightness == Brightness.light &&
      colors.surface == SpringThemeColors.light.surface &&
      colors.surfaceMuted == SpringThemeColors.light.surfaceMuted &&
      colors.border == SpringThemeColors.light.border &&
      colors.text == SpringThemeColors.light.text &&
      colors.textMuted == SpringThemeColors.light.textMuted &&
      colors.textSubtle == SpringThemeColors.light.textSubtle;
}

Color _memoryLightFallbackColor(
  BuildContext context,
  SpringThemeColors colors, {
  required Color themed,
  required Color fallback,
}) {
  return _usesPlainLightMemoryColors(context, colors) ? fallback : themed;
}

class MemoryPage extends StatefulWidget {
  const MemoryPage({
    super.key,
    required this.localDataState,
    this.aiClientService = const AiClientService(),
    this.conversationService = const MemoryConversationService(),
    this.searchService = const MemorySearchService(),
    this.pendingImageClipboardService = const PendingImageClipboardService(),
  });

  final LocalDataState localDataState;
  final AiClientService aiClientService;
  final MemoryConversationService conversationService;
  final MemorySearchService searchService;
  final PendingImageClipboardService pendingImageClipboardService;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  final TextEditingController _entryController = MemoryComposerController();
  final TextEditingController _chatController = MemoryComposerController();
  final LayerLink _entryMenuLink = LayerLink();
  final LayerLink _chatMenuLink = LayerLink();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _entryFocusNode = FocusNode();
  final FocusNode _chatFocusNode = FocusNode();
  final GlobalKey _chatListKey = GlobalKey();

  /// Scroll anchors for the right-side conversation nav: one GlobalKey per
  /// user message (keyed by its index in `_messages`), so a nav tap can
  /// scroll that round into view.
  final Map<int, GlobalKey> _navAnchorKeys = {};
  int _activeNavIndex = 0;

  /// True while a nav tap jump is scrolling: the tapped entry keeps the
  /// highlight for the whole glide instead of waiting for the threshold.
  bool _navJumpInProgress = false;

  /// Deduplicates post-frame highlight syncs so a scroll burst schedules at
  /// most one recalculation per frame.
  bool _navUpdateScheduled = false;

  List<MemoryMessage> _messages = [];
  bool _loading = true;
  bool _answering = false;
  bool _waitingForMemoryResponse = false;
  bool _thinkingEnabled = true;
  String _reasoningEffort = 'high';
  Timer? _reasoningDurationTimer;
  int? _reasoningDurationMessageIndex;
  DateTime? _reasoningDurationStartedAt;

  /// Images pasted into the composer but not sent yet. Shared by the entry
  /// and chat composers (only one is visible at a time), like the mode
  /// tags carried between the two controllers.
  List<PendingImage> _pendingImages = [];

  /// Serial for assigning collision-free ids to pasted images (clipboard
  /// ids repeat between paste operations; see `_addPendingImages`).
  int _pendingImageSerial = 0;
  String? _attachmentError;
  bool _pastingImages = false;

  bool get _inChat => _messages.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scheduleActiveNavUpdate);
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
        _navAnchorKeys.removeWhere((index, _) => index >= messages.length);
        _activeNavIndex = 0;
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
      _navAnchorKeys.clear();
      _activeNavIndex = 0;
      _entryController.clear();
      _chatController.clear();
      _pendingImages = [];
      _attachmentError = null;
    });
    _entryFocusNode.requestFocus();
  }

  Future<void> _sendFromEntry() =>
      _send(_entryController.text, tagSource: _entryController);

  Future<void> _sendFromChat() =>
      _send(_chatController.text, tagSource: _chatController);

  Future<void> _send(
    String rawQuestion, {
    TextEditingController? tagSource,
  }) async {
    // Mode tags (e.g. 思维导图) live in the input text; strip them from the
    // displayed question and turn their prompts into a model-only suffix.
    // Quick-action buttons send canned text, so their caller passes the
    // composer as [tagSource]: the tags sitting in it apply to that
    // message too — a visible tag means the mode is on, however the
    // message is sent.
    var resolved = resolveMemoryInputModes(rawQuestion);
    if (tagSource != null) {
      final tagModes = resolveMemoryInputModes(tagSource.text).modes;
      resolved = MemoryInputModeResolution(
        userText: resolved.userText,
        modes: [
          for (final mode in memoryInputModes)
            if (resolved.modes.contains(mode) || tagModes.contains(mode)) mode,
        ],
      );
    }
    final question = resolved.userText.trim();
    if ((question.isEmpty && _pendingImages.isEmpty) || _answering) {
      return;
    }
    // 提示文案在异步间隙之前取好。
    final strings = l10n(context);
    final modelQuestion = resolved.modes.isEmpty
        ? null
        : '$question\n\n${resolved.promptSuffix}';

    // 粘贴的图片先落盘到 memory_images/，remember.json 只记录文件名。
    var imageNames = const <String>[];
    if (_pendingImages.isNotEmpty) {
      try {
        imageNames = await widget.conversationService.saveImages(
          appDataDir: widget.localDataState.dataDirectory,
          images: _pendingImages,
        );
      } catch (_) {
        if (mounted) {
          setState(() => _attachmentError = strings.memoryImageSaveFailed);
        }
        return;
      }
    }
    if (!mounted) {
      return;
    }

    final now = DateTime.now();
    final userMessage = MemoryMessage(
      role: 'user',
      content: question,
      createdAt: now,
      // Record which modes were active so later requests can explain the
      // resulting reply's format without guessing from its content.
      modeIds: [for (final mode in resolved.modes) mode.id],
      imageNames: imageNames,
    );

    setState(() {
      _messages = [..._messages, userMessage];
      _answering = true;
      _waitingForMemoryResponse = false;
      _entryController.clear();
      // Keep the mode tags instead of clearing them: after a send the
      // conversation view shows the chat composer, so the tags live
      // there — the user sees the mode is still on and can delete the
      // tag with one Backspace instead of re-selecting it every message.
      // (Empty when no mode was active, which clears the composer.)
      _chatController.text = [
        for (final mode in resolved.modes) mode.token,
      ].join();
      _pendingImages = [];
      _attachmentError = null;
    });
    await _persist();
    _scrollToBottom();

    final aiMessage = await _runToolCallingLoop(
      question,
      modelQuestion: modelQuestion,
    );
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

  TextEditingController get _activeComposerController =>
      _inChat ? _chatController : _entryController;

  FocusNode get _activeComposerFocusNode =>
      _inChat ? _chatFocusNode : _entryFocusNode;

  Future<void> _handlePasteShortcut() async {
    if (_answering || _pastingImages) {
      return;
    }

    _pastingImages = true;
    try {
      final images = await widget.pendingImageClipboardService
          .readPendingImages();
      if (!mounted) {
        return;
      }
      if (images.isEmpty) {
        await _pasteClipboardText();
        return;
      }
      final strings = l10n(context);
      if (!widget.aiClientService.memoryModelSupportsImageInput(
        widget.localDataState.config,
      )) {
        setState(() => _attachmentError = strings.memoryImageModelUnsupported);
        return;
      }
      setState(() => _attachmentError = _addPendingImages(images, strings));
      _activeComposerFocusNode.requestFocus();
    } catch (_) {
      if (mounted) {
        setState(
          () => _attachmentError = l10n(context).homeClipboardImageError,
        );
      }
    } finally {
      _pastingImages = false;
    }
  }

  /// Adds pasted images to the composer, enforcing the same per-image and
  /// per-message limits as note generation. Returns the error to show when
  /// any image was rejected.
  ///
  /// Each image gets a fresh id on insertion: clipboard-sourced
  /// [PendingImage] ids repeat across paste operations (`clipboard-png-0`),
  /// and chip removal matches by id — reusing them would delete every chip
  /// sharing the id at once.
  String? _addPendingImages(
    List<PendingImage> images,
    AppLocalizations strings,
  ) {
    var rejected = false;
    for (final image in images) {
      if (_pendingImages.length >= maxAiImageInputs) {
        return strings.memoryImageCountLimit;
      }
      final aiImage = AiImageInput.fromBytes(
        name: image.name,
        bytes: image.bytes,
        extension: image.extension,
      );
      if (!isSupportedAiImageInput(aiImage)) {
        rejected = true;
        continue;
      }
      _pendingImages.add(
        PendingImage(
          id: 'memory-pending-${_pendingImageSerial++}',
          bytes: image.bytes,
          name: image.name,
          extension: image.extension,
        ),
      );
    }
    return rejected ? strings.memoryImageInvalid : null;
  }

  Future<void> _pasteClipboardText() async {
    final ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      if (mounted) {
        setState(() => _attachmentError = l10n(context).homeClipboardTextError);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    _insertComposerText(text);
    _activeComposerFocusNode.requestFocus();
  }

  void _insertComposerText(String text) {
    final controller = _activeComposerController;
    final value = controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, text);
    final offset = start + text.length;
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  void _removePendingImage(PendingImage image) {
    setState(() {
      _pendingImages = _pendingImages
          .where((item) => item.id != image.id)
          .toList();
      if (_pendingImages.isEmpty) {
        _attachmentError = null;
      }
    });
  }

  /// The conversation as the model should see it: identical to [_messages]
  /// except the latest user message additionally carries the active
  /// input-mode prompt. Storage and bubbles keep the clean text.
  ///
  /// User messages sent with mode tags record their mode ids (see
  /// [MemoryMessage.modeIds]); in the request view they carry a note so
  /// the model knows the following reply's special format was tag-driven.
  /// Without it the history reads as "ordinary question → specially
  /// formatted answer", and the model keeps emitting that format after
  /// the user drops the tag.
  List<MemoryMessage> _requestMessages(String? modelQuestion) {
    final view = <MemoryMessage>[];
    final historyModes = <MemoryInputMode>{};
    for (final message in _messages) {
      if (message.role == 'user' && message.modeIds.isNotEmpty) {
        final modes = memoryInputModesForIds(message.modeIds);
        if (modes.isNotEmpty) {
          historyModes.addAll(modes);
          view.add(
            MemoryMessage(
              role: message.role,
              content:
                  '${message.content.trimRight()}\n\n${modeRequestNote(modes)}',
              createdAt: message.createdAt,
              modeIds: message.modeIds,
              imageNames: message.imageNames,
            ),
          );
          continue;
        }
      }
      view.add(message);
    }

    var requestQuestion = modelQuestion;
    if (requestQuestion == null && historyModes.isNotEmpty) {
      // No mode tag this turn: explicitly cancel the output format the
      // annotated history would otherwise keep suggesting.
      for (var i = view.length - 1; i >= 0; i--) {
        if (view[i].role == 'user') {
          requestQuestion =
              '${view[i].content}\n\n${noModeReplyReminder(historyModes)}';
          break;
        }
      }
    }
    if (requestQuestion != null) {
      for (var i = view.length - 1; i >= 0; i--) {
        if (view[i].role == 'user') {
          view[i] = MemoryMessage(
            role: 'user',
            content: requestQuestion,
            createdAt: view[i].createdAt,
            imageNames: view[i].imageNames,
          );
          break;
        }
      }
    }
    return view;
  }

  Future<MemoryMessage?> _runToolCallingLoop(
    String question, {
    String? modelQuestion,
  }) async {
    final maxTurns = widget.localDataState.config.memorySearchLimit
        .round()
        .clamp(1, 12);
    final turnSources = <MemorySource>[];
    final toolResultCache = <String, MemoryToolExecution>{};
    // 提示文案在异步间隙之前取好。
    final strings = l10n(context);

    for (var turn = 0; turn < maxTurns; turn++) {
      final requestStartedAt = DateTime.now();
      _setWaitingForMemoryResponse(true);
      final stream = await widget.aiClientService.memoryToolChatStream(
        appDataDir: widget.localDataState.dataDirectory,
        config: widget.localDataState.config,
        messages: _requestMessages(modelQuestion),
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
                ? strings.memoryModelRequestFailed
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
          content: content.trim().isEmpty
              ? strings.memoryNoUsableAnswer
              : content.trim(),
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
        final arguments = _decodeToolArguments(toolCall.arguments);
        final cacheKey = memoryToolCacheKey(toolCall.name, arguments);
        final cachedExecution = toolResultCache[cacheKey];
        final execution =
            cachedExecution ??
            await widget.searchService.executeTool(
              localDataState: widget.localDataState,
              toolName: toolCall.name,
              arguments: arguments,
              limit: maxTurns,
            );
        toolResultCache[cacheKey] = execution;
        if (cachedExecution == null) {
          turnSources.addAll(execution.sources);
        }
        final toolMessage = MemoryMessage(
          role: 'tool',
          content: cachedExecution == null
              ? execution.content
              : deduplicatedMemoryToolContent(execution.content),
          createdAt: DateTime.now(),
          toolName: execution.toolName,
          toolCallId: toolCall.id,
          sources: cachedExecution == null ? execution.sources : const [],
        );
        setState(() => _messages = [..._messages, toolMessage]);
        await _persist();
      }
    }

    return MemoryMessage(
      role: 'ai',
      content: strings.memoryToolCallsLimitReached,
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
      modeIds: message.modeIds,
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
    final strings = l10n(context);
    if (recall.sources.isEmpty) {
      return strings.memoryMockAnswerEmpty(question);
    }
    final toolList = recall.steps
        .map(
          (step) => strings.memoryMockAnswerToolStep(
            step.thought,
            step.tool.label,
            step.tool.query,
            step.observation,
          ),
        )
        .join('\n');
    final sourceList = recall.sources
        .take(3)
        .map(
          (source) =>
              strings.memoryMockAnswerSourceItem(source.snippet, source.title),
        )
        .join('\n');
    return strings.memoryMockAnswerWithSources(toolList, sourceList, question);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      color: colors.background,
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
    final colors = AppTheme.colors(context);
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
                l10n(context).memoryEntryTitle,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 22),
              _MemoryComposer(
                controller: _entryController,
                focusNode: _entryFocusNode,
                hintText: l10n(context).memoryEntryHint,
                answering: _answering,
                onSubmit: _sendFromEntry,
                menuLink: _entryMenuLink,
                submitWithEnter: widget.localDataState.config.submitWithEnter,
                pendingImages: _pendingImages,
                attachmentError: _attachmentError,
                onPasteShortcut: _handlePasteShortcut,
                onRemoveImage: _removePendingImage,
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _QuickPromptChip(
                    icon: Icons.history_rounded,
                    label: l10n(context).memoryQuickPromptTodayDaily,
                    onTap: () => _send(
                      l10n(context).memoryQuickPromptTodayDaily,
                      tagSource: _entryController,
                    ),
                  ),
                  _QuickPromptChip(
                    icon: Icons.auto_awesome_rounded,
                    label: l10n(context).memoryQuickPromptWeekDaily,
                    onTap: () => _send(
                      l10n(context).memoryQuickPromptWeekDaily,
                      tagSource: _entryController,
                    ),
                  ),
                  _QuickPromptChip(
                    icon: Icons.calendar_month_rounded,
                    label: l10n(context).memoryQuickPromptMonthReport,
                    onTap: () => _send(
                      l10n(context).memoryQuickPromptMonthReport,
                      tagSource: _entryController,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isVisibleChatMessage(MemoryMessage message) {
    return message.role == 'user' ||
        message.role == 'ai' ||
        (message.role == 'assistant' &&
            (message.content.trim().isNotEmpty ||
                message.reasoningContent.trim().isNotEmpty ||
                message.toolCalls.isNotEmpty));
  }

  GlobalKey _navKeyFor(int messageIndex) {
    return _navAnchorKeys.putIfAbsent(messageIndex, GlobalKey.new);
  }

  /// One nav entry per user question: the question text is what identifies
  /// each round of the conversation in the right-side history nav.
  List<_MemoryConversationNavEntry> _conversationNavEntries() {
    final entries = <_MemoryConversationNavEntry>[];
    for (var i = 0; i < _messages.length; i++) {
      final message = _messages[i];
      if (message.role != 'user') {
        continue;
      }
      final label = message.content.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (label.isEmpty) {
        continue;
      }
      entries.add(
        _MemoryConversationNavEntry(label: label, anchorKey: _navKeyFor(i)),
      );
    }
    return entries;
  }

  /// Scroll listeners fire mid-frame, before the layout for the new scroll
  /// offset exists, so reading bubble geometry there is one frame stale —
  /// at the end of a scroll that leaves the highlight one round behind.
  /// Defer the recalculation to after the frame instead.
  void _scheduleActiveNavUpdate() {
    if (_navUpdateScheduled) {
      return;
    }
    _navUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navUpdateScheduled = false;
      _updateActiveNavIndex();
    });
  }

  /// Keeps the nav highlight in sync with the scroll position: the active
  /// round is the last one whose question bubble has entered the viewport,
  /// so the final round also lights up at the end of the list even when its
  /// bubble is still sitting low on the screen.
  void _updateActiveNavIndex() {
    // During a nav tap jump the tapped entry owns the highlight; skip
    // position-based updates until the scroll settles.
    if (!mounted || _navJumpInProgress) {
      return;
    }
    final entries = _conversationNavEntries();
    final listContext = _chatListKey.currentContext;
    if (entries.isEmpty || listContext == null) {
      return;
    }
    final listBox = listContext.findRenderObject();
    if (listBox is! RenderBox || !listBox.attached) {
      return;
    }
    final viewportBottom =
        listBox.localToGlobal(Offset.zero).dy + listBox.size.height;
    var active = 0;
    for (var i = 0; i < entries.length; i++) {
      final anchorContext = entries[i].anchorKey.currentContext;
      if (anchorContext == null) {
        continue;
      }
      final box = anchorContext.findRenderObject();
      if (box is! RenderBox || !box.attached) {
        continue;
      }
      if (box.localToGlobal(Offset.zero).dy <= viewportBottom - 60) {
        active = i;
      }
    }
    if (active != _activeNavIndex) {
      setState(() => _activeNavIndex = active);
    }
  }

  void _jumpToConversation(GlobalKey anchorKey, int navIndex) {
    final anchorContext = anchorKey.currentContext;
    if (anchorContext == null) {
      return;
    }
    // Highlight the tapped round right away instead of waiting for the
    // scroll to carry it past the active threshold.
    setState(() => _activeNavIndex = navIndex);
    _navJumpInProgress = true;
    Scrollable.ensureVisible(
      anchorContext,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    ).whenComplete(() {
      // The tapped round keeps the highlight after the jump: recomputing
      // from the scroll position here would stomp the explicit choice with
      // whatever round happens to sit lowest on screen (e.g. tapping round
      // 3 but landing on round 4). Defer the handoff one frame so scroll
      // updates scheduled by the final animation frames drain while still
      // suppressed; position-based tracking resumes on the next scroll.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navJumpInProgress = false;
      });
    });
  }

  Widget _buildChatState() {
    final colors = AppTheme.colors(context);
    final visibleMessages = <MapEntry<int, MemoryMessage>>[
      for (var i = 0; i < _messages.length; i++)
        if (_isVisibleChatMessage(_messages[i])) MapEntry(i, _messages[i]),
    ];
    final navEntries = _conversationNavEntries();

    return LayoutBuilder(
      key: const ValueKey('memory-chat'),
      builder: (context, constraints) {
        // The collapsed rail lives entirely inside the list's right padding,
        // so it never covers messages — show it from three rounds up and
        // only hide it when the window gets really narrow.
        final showNav = navEntries.length >= 3 && constraints.maxWidth >= 720;
        return Stack(
          children: [
            ListView(
              key: _chatListKey,
              controller: _scrollController,
              // Extra room while pasted images wait above the composer.
              padding: EdgeInsets.fromLTRB(
                32,
                36,
                32,
                _pendingImages.isEmpty ? 150 : 214,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final entry in visibleMessages)
                          _MemoryMessageView(
                            key: entry.value.role == 'user'
                                ? _navKeyFor(entry.key)
                                : null,
                            message: entry.value,
                            localDataState: widget.localDataState,
                            attachments: _toolAttachmentsFor(entry.value),
                            imagePaths: [
                              for (final name in entry.value.imageNames)
                                widget.conversationService.imagePath(
                                  appDataDir:
                                      widget.localDataState.dataDirectory,
                                  name: name,
                                ),
                            ],
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
              // No fixed height: the strip of pasted image chips above the
              // composer makes the whole area grow while composing.
              child: Stack(
                children: [
                  // The gradient strip is purely decorative. Ignore its
                  // pointers so the bottom corners stay scrollable/selectable
                  // instead of becoming dead zones. (A nested
                  // IgnorePointer(ignoring: false) cannot re-enable hit
                  // testing, so the composer must live outside it.)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colors.background.withValues(alpha: 0),
                              colors.background,
                              colors.background,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _MemoryComposer(
                          controller: _chatController,
                          focusNode: _chatFocusNode,
                          hintText: l10n(context).memoryChatHint,
                          answering: _answering,
                          onSubmit: _sendFromChat,
                          menuOpensUpward: true,
                          menuLink: _chatMenuLink,
                          submitWithEnter:
                              widget.localDataState.config.submitWithEnter,
                          pendingImages: _pendingImages,
                          attachmentError: _attachmentError,
                          onPasteShortcut: _handlePasteShortcut,
                          onRemoveImage: _removePendingImage,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showNav)
              Positioned(
                top: 24,
                bottom: 150,
                right: 8,
                child: Center(
                  child: _MemoryConversationNav(
                    key: const ValueKey('memory-conversation-nav'),
                    entries: navEntries,
                    activeIndex: _activeNavIndex.clamp(
                      0,
                      navEntries.length - 1,
                    ),
                    onSelect: (entry) => _jumpToConversation(
                      entry.anchorKey,
                      navEntries.indexOf(entry),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
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

class _MemoryConversationNavEntry {
  const _MemoryConversationNavEntry({
    required this.label,
    required this.anchorKey,
  });

  /// Single-line question preview identifying the round.
  final String label;

  /// Anchors the round's user message in the chat list for jump scrolling.
  final GlobalKey anchorKey;
}

/// Minimal right-side conversation history nav, styled after DeepSeek's
/// scroll nav: collapsed it is a thin rail of short dashes — one per round —
/// tucked into the list's right padding, the active round's dash longer and
/// darker. Hovering fades in a small framed card of right-aligned question
/// labels, each followed by its dash; tapping an entry scrolls that round
/// into view.
class _MemoryConversationNav extends StatefulWidget {
  const _MemoryConversationNav({
    super.key,
    required this.entries,
    required this.activeIndex,
    required this.onSelect,
  });

  final List<_MemoryConversationNavEntry> entries;
  final int activeIndex;
  final ValueChanged<_MemoryConversationNavEntry> onSelect;

  @override
  State<_MemoryConversationNav> createState() => _MemoryConversationNavState();
}

class _MemoryConversationNavState extends State<_MemoryConversationNav> {
  /// With more rounds than this, the rail shows a window around the active
  /// round and the hover card gets its own scrollbar.
  static const int _maxVisibleEntries = 9;

  /// Fixed row height so the rail window and the card's scroll viewport
  /// line up exactly.
  static const double _rowHeight = 28;

  bool _expanded = false;
  int? _hoveredIndex;
  final ScrollController _cardScrollController = ScrollController();

  @override
  void dispose() {
    _cardScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final scrollable = widget.entries.length > _maxVisibleEntries;
    return MouseRegion(
      onEnter: (_) {
        setState(() => _expanded = true);
        _syncCardScrollToActive();
      },
      onExit: (_) => setState(() {
        _expanded = false;
        _hoveredIndex = null;
      }),
      // Hover fades the framed card in over the bare rail, DeepSeek style.
      // The right inset, row height and label layout are constant, so the
      // dashes never move when the card appears.
      child: SizedBox(
        width: _expanded ? 184 : (scrollable ? 30 : 24),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                opacity: _expanded ? 1 : 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: 0.08),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: _expanded ? 8 : 0,
                top: _expanded ? 8 : 0,
                bottom: _expanded ? 8 : 0,
                // The rail reserves the 6px scrollbar gutter too, so the
                // dashes line up between the two states. The expanded card
                // keeps only 2px on the right: the ListView reaches almost
                // to the card edge, which pushes the platform scrollbar
                // (added by the desktop scroll behavior) into the padding,
                // clear of the dashes.
                right: !_expanded
                    ? (scrollable ? 14 : 8)
                    : (scrollable ? 2 : 8),
              ),
              child: _expanded ? _buildCard(colors) : _buildRail(colors),
            ),
          ],
        ),
      ),
    );
  }

  /// The first rail index shown: a window around the active round when the
  /// full list does not fit.
  int get _windowStart {
    final count = widget.entries.length;
    if (count <= _maxVisibleEntries) {
      return 0;
    }
    return (widget.activeIndex - _maxVisibleEntries ~/ 2).clamp(
      0,
      count - _maxVisibleEntries,
    );
  }

  /// Opens the card already scrolled to the same window the rail shows, so
  /// the rows line up with the dashes they grew out of.
  void _syncCardScrollToActive() {
    if (widget.entries.length <= _maxVisibleEntries) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_cardScrollController.hasClients) {
        return;
      }
      _cardScrollController.jumpTo(_windowStart * _rowHeight);
    });
  }

  Widget _buildRail(SpringThemeColors colors) {
    final count = widget.entries.length;
    final start = _windowStart;
    final end = count > _maxVisibleEntries ? start + _maxVisibleEntries : count;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [for (var i = start; i < end; i++) _buildItem(colors, i)],
    );
  }

  Widget _buildCard(SpringThemeColors colors) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: _maxVisibleEntries * _rowHeight,
      ),
      // Slimmer than the desktop default (6px), even when hovered.
      child: ScrollbarTheme(
        data: ScrollbarThemeData(
          thickness: WidgetStateProperty.all(3),
          radius: const Radius.circular(1.5),
        ),
        child: ListView.builder(
          controller: _cardScrollController,
          primary: false,
          // The 12px gutter keeps the dashes aligned with the rail (2px card
          // padding + 12px here = 14px) and leaves room for the platform
          // scrollbar against the card's right edge.
          padding: EdgeInsets.only(
            right: widget.entries.length > _maxVisibleEntries ? 12 : 0,
          ),
          shrinkWrap: true,
          itemCount: widget.entries.length,
          itemBuilder: (context, i) => _buildItem(colors, i),
        ),
      ),
    );
  }

  Widget _buildItem(SpringThemeColors colors, int index) {
    final entry = widget.entries[index];
    final active = index == widget.activeIndex;
    final hovered = index == _hoveredIndex;
    final baseStyle = Theme.of(context).textTheme.bodySmall;
    final textColor = active
        ? colors.text
        : hovered
        ? colors.textMuted
        : colors.textSubtle;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelect(entry),
        child: SizedBox(
          height: _rowHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                // Always laid out, even while hidden, so the row height —
                // and with it the dash position — never changes.
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  opacity: _expanded ? 1 : 0,
                  child: Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: (baseStyle ?? const TextStyle(fontSize: 12))
                        .copyWith(
                          color: textColor,
                          fontWeight: active
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // The fixed-width slot keeps the label in place no matter how
              // long the dash is; the dash itself changes instantly.
              // Inactive dashes alternate thick (3px) and thin (1.5px) by
              // index parity, giving the rail a quiet rhythm.
              SizedBox(
                width: 8,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    width: active ? 8 : 5.6,
                    height: active || index.isEven ? 3 : 1.5,
                    decoration: BoxDecoration(
                      color: active
                          ? colors.text
                          : hovered
                          ? colors.textSubtle
                          : colors.border,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    final colors = AppTheme.colors(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Text(
            l10n(context).memoryPageTitle,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.text,
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
          Tooltip(
            message: l10n(context).memoryNewConversationTooltip,
            waitDuration: const Duration(milliseconds: 450),
            child: IconButton(
              onPressed: onNewConversation,
              style: IconButton.styleFrom(
                fixedSize: const Size(34, 34),
                minimumSize: const Size(34, 34),
                maximumSize: const Size(34, 34),
                backgroundColor: Colors.transparent,
                hoverColor: colors.surfaceMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: _MemoryNewConversationIcon(
                size: 17,
                color: colors.textSubtle,
              ),
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
    required this.menuLink,
    required this.pendingImages,
    required this.onPasteShortcut,
    required this.onRemoveImage,
    this.attachmentError,
    this.menuOpensUpward = false,
    this.submitWithEnter = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final bool answering;
  final VoidCallback onSubmit;

  /// Pasted images waiting to be sent with the next message; rendered as
  /// removable chips above the input bar.
  final List<PendingImage> pendingImages;

  /// Paste/attachment problem shown under the input bar, if any.
  final String? attachmentError;

  /// Intercepts Ctrl/Cmd+V so clipboard images can be attached; the
  /// handler falls back to plain text paste when the clipboard holds no
  /// image.
  final VoidCallback onPasteShortcut;
  final ValueChanged<PendingImage> onRemoveImage;

  /// Links the composer box to the floating mode menu: the menu anchors to
  /// the whole composer so it can span the composer's full width.
  final LayerLink menuLink;

  /// Chat composers sit at the bottom of the page: open the mode menu above
  /// the "+" button. Entry composers open it below.
  final bool menuOpensUpward;

  /// True when plain Enter submits and Ctrl/Cmd+Enter inserts the newline;
  /// false keeps the default (Ctrl/Cmd+Enter submits, Enter newlines).
  final bool submitWithEnter;

  /// Inserts a mode tag at the cursor. The tag is a single code point in
  /// the text, so it edits like any other character — Backspace/Delete
  /// remove it whole and the mode is off again. One tag per mode.
  void _insertModeToken(MemoryInputMode mode) {
    final value = controller.value;
    if (value.text.contains(mode.token)) {
      return;
    }
    final selection = value.selection;
    final offset = selection.isValid
        ? selection.baseOffset.clamp(0, value.text.length)
        : value.text.length;
    controller.value = TextEditingValue(
      text: value.text.replaceRange(offset, offset, mode.token),
      selection: TextSelection.collapsed(offset: offset + 1),
    );
    // Opening the "+" menu stole the focus — give it back so the caret
    // lands right after the inserted tag and typing continues seamlessly.
    focusNode.requestFocus();
  }

  /// Inserts a line break at the caret, replacing any selected text. Used
  /// for the newline shortcut when [submitWithEnter] is on: the field's
  /// default Enter handling is intercepted for submit, so the modifier
  /// combo has to insert the newline manually.
  void _insertNewline() {
    final value = controller.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(0, text.length)
        : text.length;
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  /// Bare-Enter handling for the composer. This cannot be a
  /// CallbackShortcuts binding: while an IME composition is active the key
  /// must stay unhandled so the platform input method confirms the
  /// candidate instead of sending the half-composed message.
  KeyEventResult _handleEnterKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed) {
      // Modifier combos are covered by the CallbackShortcuts bindings.
      return KeyEventResult.ignored;
    }
    final composing = controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (!submitWithEnter) {
      // Ctrl/Cmd+Enter mode: a bare Enter keeps its default newline.
      return KeyEventResult.ignored;
    }
    onSubmit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pendingImages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MemoryPendingImageStrip(
              images: pendingImages,
              enabled: !answering,
              onRemove: onRemoveImage,
            ),
          ),
        _buildPill(AppTheme.colors(context)),
        if (attachmentError != null)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 6),
            child: Text(
              attachmentError!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: dark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  /// The rounded input bar itself: mode menu button, text field, send.
  Widget _buildPill(SpringThemeColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 280.0;
        return CompositedTransformTarget(
          link: menuLink,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.fromLTRB(7, 5, 8, 5),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.08),
                  blurRadius: 28,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                _InputModeMenuButton(
                  link: menuLink,
                  panelWidth: panelWidth,
                  opensUpward: menuOpensUpward,
                  onSelected: _insertModeToken,
                ),
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleEnterKey,
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(
                          LogicalKeyboardKey.keyV,
                          control: true,
                        ): onPasteShortcut,
                        const SingleActivator(
                          LogicalKeyboardKey.keyV,
                          meta: true,
                        ): onPasteShortcut,
                        if (submitWithEnter) ...{
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            control: true,
                          ): _insertNewline,
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            meta: true,
                          ): _insertNewline,
                          const SingleActivator(
                            LogicalKeyboardKey.numpadEnter,
                            control: true,
                          ): _insertNewline,
                          const SingleActivator(
                            LogicalKeyboardKey.numpadEnter,
                            meta: true,
                          ): _insertNewline,
                        } else ...{
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            control: true,
                          ): onSubmit,
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            meta: true,
                          ): onSubmit,
                        },
                      },
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: true,
                        // Desktop fields select all on focus gain — that
                        // would highlight a just-inserted mode tag.
                        selectAllOnFocus: false,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.newline,
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
                  ),
                ),
                IconButton.filled(
                  onPressed: answering ? null : onSubmit,
                  style: IconButton.styleFrom(
                    backgroundColor: colors.text,
                    disabledBackgroundColor: colors.surfaceMuted,
                  ),
                  icon: answering
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.textSubtle,
                          ),
                        )
                      : Icon(
                          Icons.arrow_upward_rounded,
                          color: colors.onAccent,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The strip of pasted-image chips shown above the composer, styled after
/// the home page's pending-image strip.
class _MemoryPendingImageStrip extends StatelessWidget {
  const _MemoryPendingImageStrip({
    required this.images,
    required this.enabled,
    required this.onRemove,
  });

  final List<PendingImage> images;
  final bool enabled;
  final ValueChanged<PendingImage> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final image in images)
          _MemoryPendingImageChip(
            image: image,
            enabled: enabled,
            onRemove: () => onRemove(image),
          ),
      ],
    );
  }
}

class _MemoryPendingImageChip extends StatelessWidget {
  const _MemoryPendingImageChip({
    required this.image,
    required this.enabled,
    required this.onRemove,
  });

  final PendingImage image;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Tooltip(
      message: image.name,
      child: Container(
        height: 40,
        padding: const EdgeInsets.only(left: 6, right: 4),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Image.memory(
                  image.bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => DecoratedBox(
                    decoration: BoxDecoration(color: colors.surfaceMuted),
                    child: Icon(
                      Icons.image_outlined,
                      size: 16,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              image.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textMuted,
                fontSize: 12,
                height: 1.2,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? onRemove : null,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: enabled
                      ? colors.textSubtle
                      : colors.textSubtle.withValues(alpha: 0.48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "+" button and its floating mode menu: a rounded panel that follows
/// the button (below it for the entry composer, above it for the bottom
/// chat composer) and closes on any outside tap. Styled after the attachment
/// menus in chat apps: icon, label and a muted description per row.
class _InputModeMenuButton extends StatefulWidget {
  const _InputModeMenuButton({
    required this.link,
    required this.panelWidth,
    required this.onSelected,
    this.opensUpward = false,
  });

  /// Shared with the composer's [CompositedTransformTarget] so the menu
  /// anchors to the whole composer.
  final LayerLink link;

  /// The composer's width — the menu panel spans it.
  final double panelWidth;
  final ValueChanged<MemoryInputMode> onSelected;
  final bool opensUpward;

  @override
  State<_InputModeMenuButton> createState() => _InputModeMenuButtonState();
}

class _InputModeMenuButtonState extends State<_InputModeMenuButton> {
  final Object _tapRegionGroupId = Object();
  OverlayEntry? _menuEntry;

  void _toggleMenu() {
    if (_menuEntry == null) {
      _openMenu();
    } else {
      _closeMenu();
    }
  }

  void _openMenu() {
    final entry = OverlayEntry(builder: _buildMenuPanel);
    _menuEntry = entry;
    Overlay.of(context).insert(entry);
  }

  void _closeMenu() {
    // remove() only detaches the entry; dispose() releases it for real.
    final entry = _menuEntry;
    _menuEntry = null;
    entry?.remove();
    entry?.dispose();
  }

  void _select(MemoryInputMode mode) {
    _closeMenu();
    widget.onSelected(mode);
  }

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  Widget _buildMenuPanel(BuildContext context) {
    final colors = AppTheme.colors(context);
    // Overlay entries get tight full-screen constraints; the Positioned
    // loosens them so the follower sizes to the panel and the anchors apply
    // to the panel itself instead of a full-screen box.
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: widget.link,
            targetAnchor: widget.opensUpward
                ? Alignment.topLeft
                : Alignment.bottomLeft,
            followerAnchor: widget.opensUpward
                ? Alignment.bottomLeft
                : Alignment.topLeft,
            offset: Offset(0, widget.opensUpward ? -8 : 8),
            child: TapRegion(
              groupId: _tapRegionGroupId,
              child: Material(
                color: colors.surface,
                elevation: 8,
                shadowColor: colors.shadow.withValues(alpha: 0.24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: colors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  key: const ValueKey('input-mode-menu-panel'),
                  width: widget.panelWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final mode in memoryInputModes)
                        InkWell(
                          onTap: () => _select(mode),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  mode.icon,
                                  size: 18,
                                  color: colors.textMuted,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  memoryInputModeLabel(context, mode),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: colors.text,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    memoryInputModeDescription(context, mode),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textMuted,
                                    ),
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
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return TapRegion(
      groupId: _tapRegionGroupId,
      onTapOutside: (_) => _closeMenu(),
      child: IconButton(
        tooltip: l10n(context).memoryInputModeTooltip,
        onPressed: _toggleMenu,
        icon: Icon(Icons.add_rounded, color: colors.textMuted),
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
    final colors = AppTheme.colors(context);
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: colors.textSubtle),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textMuted,
        side: BorderSide(color: colors.border),
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
    final colors = AppTheme.colors(context);
    final backgroundColor = _memoryLightFallbackColor(
      context,
      colors,
      themed: colors.surfaceMuted,
      fallback: const Color(0xFFEDEDED),
    );
    final borderColor = _memoryLightFallbackColor(
      context,
      colors,
      themed: colors.border,
      fallback: const Color(0xFFE0E0E0),
    );
    final thumbColor = _memoryLightFallbackColor(
      context,
      colors,
      themed: colors.surface,
      fallback: Colors.white,
    );
    final thumbShadowColor = _memoryLightFallbackColor(
      context,
      colors,
      themed: colors.shadow.withValues(alpha: 0.12),
      fallback: const Color(0x14171717),
    );
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
          final segmentWidth = (constraints.maxWidth - 6) / 3;
          return Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: backgroundColor,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  left: selectedIndex * segmentWidth,
                  top: 0,
                  bottom: 0,
                  width: segmentWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: thumbColor,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: thumbShadowColor,
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
    final colors = AppTheme.colors(context);
    final selectedColor = _memoryLightFallbackColor(
      context,
      colors,
      themed: colors.text,
      fallback: const Color(0xFF171717),
    );
    final textColor = _memoryLightFallbackColor(
      context,
      colors,
      themed: colors.textSubtle,
      fallback: const Color(0xFF666666),
    );
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 140),
            style:
                style?.copyWith(color: selected ? selectedColor : textColor) ??
                TextStyle(color: selected ? selectedColor : textColor),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class _MemoryMessageView extends StatelessWidget {
  const _MemoryMessageView({
    super.key,
    required this.message,
    required this.localDataState,
    required this.attachments,
    this.imagePaths = const [],
  });

  final MemoryMessage message;
  final LocalDataState localDataState;
  final List<_MemoryToolAttachment> attachments;

  /// Absolute paths of the images attached to a user message, resolved
  /// from [MemoryMessage.imageNames] by the caller.
  final List<String> imagePaths;

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
    final colors = AppTheme.colors(context);
    if (message.role == 'user') {
      final bubbleColor = _memoryLightFallbackColor(
        context,
        colors,
        themed: colors.surfaceMuted,
        fallback: const Color(0xFFF5F5F5),
      );
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          margin: const EdgeInsets.only(bottom: 28),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imagePaths.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: message.content.isEmpty ? 0 : 10,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final path in imagePaths)
                        _MemorySentImage(path: path),
                    ],
                  ),
                ),
              if (message.content.isNotEmpty)
                SelectableText(
                  message.content,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.text,
                    height: 1.7,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    Widget buildMarkdown(String markdown) {
      return SizedBox(
        width: double.infinity,
        child: GptMarkdownTheme(
          gptThemeData: springMarkdownThemeData(
            context,
            GptMarkdownTheme.of(context),
          ),
          child: GptMarkdown(
            prepareSpringMarkdownText(markdown),
            followLinkColor: true,
            useDollarSignsForLatex: true,
            latexBuilder: springMarkdownLatexBuilder,
            components: springMarkdownComponents,
            inlineComponents: springMarkdownInlineComponents,
            unOrderedListBuilder: springMarkdownUnorderedListBuilder,
            tableBuilder: springMarkdownTableBuilder,
            // The memoir page is a single scrollable page with no note
            // switching, so springtree blocks render without the inline
            // node cap.
            codeBuilder: (context, name, code, closed) => buildSpringCodeBlock(
              context,
              name,
              code,
              closed,
              inlineNodeLimit: null,
            ),
            imageBuilder: (context, url, width, height) => SpringMarkdownImage(
              url: url,
              width: width,
              height: height,
              localImageBasePaths: memoryImageBasePaths(
                message,
                localDataState,
              ),
            ),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: springMarkdownTextColor(
                context,
                darkFallback: colors.textMuted,
              ),
              fontSize: 14,
              height: 1.55,
            ),
            onLinkTap: openSpringMarkdownLink,
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
              buildMarkdown(message.content),
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

/// A thumbnail of an image attached to a sent user message, loaded from
/// the conversation's `memory_images` directory.
class _MemorySentImage extends StatelessWidget {
  const _MemorySentImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        File(path),
        width: 160,
        height: 120,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => Container(
          width: 160,
          height: 120,
          color: colors.surfaceMuted,
          child: Icon(Icons.broken_image_outlined, color: colors.textMuted),
        ),
      ),
    );
  }
}

List<String> memoryImageBasePaths(
  MemoryMessage message,
  LocalDataState localDataState,
) {
  final paths = <String>[];
  for (final source in message.sources) {
    final sourceDirectory = _parentDirectoryPath(source.path);
    if (sourceDirectory != null) {
      paths.add(sourceDirectory);
      final notesDirectory = _parentDirectoryPath(sourceDirectory);
      if (notesDirectory != null) {
        paths.add(notesDirectory);
      }
    }
  }
  paths.addAll([
    localDataState.dailyNotesDirectory,
    localDataState.weeklyNotesDirectory,
    localDataState.monthlyNotesDirectory,
  ]);
  for (final directory in [
    localDataState.dailyNotesDirectory,
    localDataState.weeklyNotesDirectory,
    localDataState.monthlyNotesDirectory,
  ]) {
    final notesDirectory = _parentDirectoryPath(directory);
    if (notesDirectory != null) {
      paths.add(notesDirectory);
    }
  }

  return _dedupeNonEmptyPaths(paths);
}

List<String> _dedupeNonEmptyPaths(Iterable<String> paths) {
  final seen = <String>{};
  final result = <String>[];
  for (final path in paths) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      continue;
    }
    result.add(trimmed);
  }
  return result;
}

String? _parentDirectoryPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final slash = trimmed.lastIndexOf('/');
  final backslash = trimmed.lastIndexOf('\\');
  final index = slash > backslash ? slash : backslash;
  if (index <= 0) {
    return null;
  }
  return trimmed.substring(0, index);
}

class _MemoryWaitingIndicator extends StatelessWidget {
  const _MemoryWaitingIndicator();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          child: Row(
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.textSubtle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n(context).memoryWaitingIndicator,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSubtle),
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
    final colors = AppTheme.colors(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final resultLabel = memoryToolResultLabel(
      l10n(context),
      attachment.resultMessage,
    );
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
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF0B3024)
                      : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: dark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _toolLabel(context, attachment.toolCall.name),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                resultLabel,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSubtle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showToolDialog(BuildContext context, _MemoryToolAttachment attachment) {
    final colors = AppTheme.colors(context);
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.dialogSurface(context),
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
                    Icon(
                      Icons.build_circle_outlined,
                      size: 20,
                      color: colors.text,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _toolLabel(context, attachment.toolCall.name),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colors.text,
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
                          title: l10n(context).memoryToolNameLabel,
                          content: attachment.toolCall.name,
                        ),
                        _ToolDetailBlock(
                          title: l10n(context).memoryToolArgumentsLabel,
                          content: _prettyJson(attachment.toolCall.arguments),
                        ),
                        _ToolDetailBlock(
                          title: l10n(context).memoryToolResultLabel,
                          content: _prettyJson(
                            attachment.resultMessage?.content ??
                                l10n(context).memoryToolNoResult,
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

  String _toolLabel(BuildContext context, String name) {
    final strings = l10n(context);
    return switch (name) {
      'get_current_date' => strings.memoryToolLabelGetCurrentDate,
      'keyword_search' => strings.memoryToolLabelKeywordSearch,
      'search_daily_notes' => strings.memoryToolLabelSearchDailyNotes,
      'search_weekly_notes' => strings.memoryToolLabelSearchWeeklyNotes,
      'search_monthly_notes' => strings.memoryToolLabelSearchMonthlyNotes,
      'read_daily_note' => strings.memoryToolLabelReadDailyNote,
      'read_week_daily_notes' => strings.memoryToolLabelReadWeekDailyNotes,
      'read_weekly_note' => strings.memoryToolLabelReadWeeklyNote,
      'read_month_weekly_notes' => strings.memoryToolLabelReadMonthWeeklyNotes,
      'read_month_report' => strings.memoryToolLabelReadMonthReport,
      'resolve_iso_week' => strings.memoryToolLabelResolveIsoWeek,
      'run_tool_sequence' => strings.memoryToolLabelRunToolSequence,
      'run_tool_batch' => strings.memoryToolLabelRunToolBatch,
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
    final colors = AppTheme.colors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.textSubtle,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              content,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textMuted,
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
    final colors = AppTheme.colors(context);
    final backgroundColor = _memoryLightFallbackColor(
      context,
      colors,
      themed: colors.surfaceMuted,
      fallback: const Color(0xFFF5F5F5),
    );
    final titleColor = _memoryLightFallbackColor(
      context,
      colors,
      themed: colors.textSubtle,
      fallback: const Color(0xFF666666),
    );
    final iconColor = _memoryLightFallbackColor(
      context,
      colors,
      themed: colors.textMuted,
      fallback: const Color(0xFF4F4F4F),
    );
    final durationColor = _memoryLightFallbackColor(
      context,
      colors,
      themed: colors.textSubtle.withValues(alpha: 0.7),
      fallback: const Color(0xB36B7280),
    );
    final titleStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: titleColor,
      fontWeight: FontWeight.w700,
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
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
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 17,
                      color: iconColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: l10n(context).memoryReasoningTitle),
                            if (widget.duration != null)
                              TextSpan(
                                text:
                                    ' (${_formatReasoningDuration(widget.duration!)})',
                                style: titleStyle?.copyWith(
                                  color: durationColor,
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
                      color: titleColor,
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
    final colors = AppTheme.colors(context);
    final bodyColor = _memoryLightFallbackColor(
      context,
      colors,
      themed: colors.textSubtle,
      fallback: const Color(0xFF666666),
    );
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: bodyColor, height: 1.65);
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
