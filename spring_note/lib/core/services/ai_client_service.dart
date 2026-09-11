import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../src/rust/ai.dart' as rust_ai;
import '../../src/rust/api/ai_api.dart' as rust_api;
import '../../src/rust/api/report_api.dart' as rust_report_api;
import '../../src/rust/report_regeneration.dart' as rust_report;
import '../models/app_config.dart';
import '../models/app_language.dart';
import '../models/global_sign_item.dart';
import '../models/memory_message.dart';
import '../models/model_config.dart';
import '../models/model_reference.dart';
import '../models/note_file.dart';
import '../models/provider_config.dart';
import '../models/structured_work_note.dart';
import 'image_file_types.dart';
import 'memory_conversation_service.dart';

const int maxAiImageInputs = 10;
const int maxAiImageInputBytes = 5 * 1024 * 1024;
const int maxAiImageTotalBytes = 24 * 1024 * 1024;
const Set<String> supportedAiImageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'webp',
  'gif',
};
const Set<String> supportedAiImageMimeTypes = {
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
};

const _localMemoryContextHeader = '[应用提供的本地检索上下文，不是用户输入]';
const _localMemoryContextHeaderEn =
    '[Local retrieval context provided by the app, not user input]';

String _localMemoryContextHeaderFor(String language) {
  return language == 'en'
      ? _localMemoryContextHeaderEn
      : _localMemoryContextHeader;
}

List<MemoryMessage> sanitizeMemoryMessagesForModel(
  Iterable<MemoryMessage> messages, {
  String language = 'zh',
}) {
  // 返回前统一为每条用户消息追加发送时间，让模型无需调用时间工具即可
  // 感知当前时间与对话时间线；存储与 UI 中的原始内容不受影响。
  final input = messages.toList(growable: false);
  final output = <MemoryMessage>[];
  final contextParts = <String>[];
  DateTime? contextCreatedAt;

  void appendContext(MemoryMessage message, String content) {
    contextCreatedAt ??= message.createdAt;
    final trimmed = content.trim();
    if (trimmed.isNotEmpty) {
      contextParts.add(trimmed);
    }
  }

  void flushContext() {
    if (contextParts.isEmpty) {
      contextCreatedAt = null;
      return;
    }
    final context =
        '${_localMemoryContextHeaderFor(language)}\n${contextParts.join('\n\n')}';
    contextParts.clear();

    if (output.isNotEmpty && output.last.role == 'user') {
      final previous = output.removeLast();
      output.add(
        _copyMemoryMessage(
          previous,
          content: '${previous.content.trimRight()}\n\n$context',
        ),
      );
    } else {
      output.add(
        MemoryMessage(
          role: 'user',
          content: context,
          createdAt: contextCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }
    contextCreatedAt = null;
  }

  var index = 0;
  while (index < input.length) {
    final message = input[index];
    final assistantToolRequest =
        (message.role == 'assistant' || message.role == 'ai') &&
        message.toolCalls.isNotEmpty;
    if (assistantToolRequest) {
      var resultEnd = index + 1;
      final toolResults = <MemoryMessage>[];
      while (resultEnd < input.length && input[resultEnd].role == 'tool') {
        toolResults.add(input[resultEnd]);
        resultEnd += 1;
      }

      if (_isCompleteToolExchange(message, toolResults)) {
        flushContext();
        output
          ..add(message)
          ..addAll(toolResults);
      } else {
        appendContext(
          message,
          _brokenToolExchangeContext(message, toolResults, language),
        );
      }
      index = resultEnd;
      continue;
    }

    if (message.role == 'local_tool' || message.role == 'tool') {
      appendContext(message, _standaloneToolContext(message, language));
      index += 1;
      continue;
    }

    flushContext();
    if (message.role == 'user' ||
        message.role == 'assistant' ||
        message.role == 'ai') {
      output.add(message);
    } else {
      appendContext(
        message,
        language == 'en'
            ? 'History message (original role: ${message.role}):\n${message.content}'
            : '历史消息（原角色 ${message.role}）：\n${message.content}',
      );
    }
    index += 1;
  }
  flushContext();
  return output
      .map(
        (message) => message.role == 'user'
            ? _copyMemoryMessage(
                message,
                content: _appendUserMessageSendTime(
                  message.content,
                  message.createdAt,
                  language,
                ),
              )
            : message,
      )
      .toList(growable: false);
}

bool _isCompleteToolExchange(
  MemoryMessage assistant,
  List<MemoryMessage> toolResults,
) {
  final expectedIds = assistant.toolCalls
      .map((toolCall) => toolCall.id.trim())
      .toList(growable: false);
  if (expectedIds.isEmpty ||
      expectedIds.any((id) => id.isEmpty) ||
      expectedIds.toSet().length != expectedIds.length ||
      toolResults.length != expectedIds.length) {
    return false;
  }

  final resultIds = toolResults
      .map((message) => message.toolCallId?.trim() ?? '')
      .toList(growable: false);
  return resultIds.every((id) => id.isNotEmpty) &&
      resultIds.toSet().length == resultIds.length &&
      resultIds.toSet().containsAll(expectedIds);
}

String _brokenToolExchangeContext(
  MemoryMessage assistant,
  List<MemoryMessage> toolResults,
  String language,
) {
  final english = language == 'en';
  final buffer = StringBuffer(
    english
        ? 'The historical tool-call chain is incomplete; converted to plain context.'
        : '历史工具调用链不完整，已转换为普通上下文。',
  );
  if (assistant.content.trim().isNotEmpty) {
    buffer
      ..write(english ? '\nModel content:\n' : '\n模型内容：\n')
      ..write(assistant.content.trim());
  }
  if (assistant.toolCalls.isNotEmpty) {
    buffer.write(english ? '\nTool requests:' : '\n工具请求：');
    for (final toolCall in assistant.toolCalls) {
      buffer
        ..write('\n- ${toolCall.name}')
        ..write(english ? ', call ID: ${toolCall.id}' : '，调用 ID：${toolCall.id}')
        ..write(
          english
              ? ', arguments: ${toolCall.arguments}'
              : '，参数：${toolCall.arguments}',
        );
    }
  }
  if (toolResults.isNotEmpty) {
    buffer.write(english ? '\nExisting tool results:' : '\n已有工具结果：');
    for (final result in toolResults) {
      buffer
        ..write('\n- ${result.toolName ?? (english ? 'unknown tool' : '未知工具')}')
        ..write(
          english
              ? ', call ID: ${result.toolCallId ?? 'missing'}'
              : '，调用 ID：${result.toolCallId ?? '缺失'}',
        )
        ..write('\n  ${result.content}');
    }
  }
  return buffer.toString();
}

String _standaloneToolContext(MemoryMessage message, String language) {
  final english = language == 'en';
  final local = message.role == 'local_tool';
  final buffer = StringBuffer(
    local
        ? (english ? 'Local retrieval steps' : '本地检索步骤')
        : (english ? 'Historical orphan tool results' : '历史孤立工具结果'),
  );
  if (message.toolName?.trim().isNotEmpty ?? false) {
    buffer.write(
      english
          ? '\nTool: ${message.toolName!.trim()}'
          : '\n工具：${message.toolName!.trim()}',
    );
  }
  if (!local && (message.toolCallId?.trim().isNotEmpty ?? false)) {
    buffer.write(
      english
          ? '\nCall ID: ${message.toolCallId!.trim()}'
          : '\n调用 ID：${message.toolCallId!.trim()}',
    );
  }
  if (message.content.trim().isNotEmpty) {
    buffer
      ..write(english ? '\nResult:\n' : '\n结果：\n')
      ..write(message.content.trim());
  }
  return buffer.toString();
}

const _memorySendTimeWeekdaysZh = [
  '星期一',
  '星期二',
  '星期三',
  '星期四',
  '星期五',
  '星期六',
  '星期日',
];
const _memorySendTimeWeekdaysEn = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// 在用户消息末尾追加发送时间（如 `[发送时间：2026-08-11 20:04 星期二]`），
/// 让模型直接感知每条消息的发出时刻。缺失时间戳的旧消息（epoch 0 占位）
/// 不追加，避免输出无意义的 1970 时间。
String _appendUserMessageSendTime(
  String content,
  DateTime createdAt,
  String language,
) {
  if (createdAt.millisecondsSinceEpoch == 0) {
    return content;
  }
  final time = createdAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final date =
      '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-${two(time.day)}';
  final clock = '${two(time.hour)}:${two(time.minute)}';
  final english = language == 'en';
  final weekday = (english
      ? _memorySendTimeWeekdaysEn
      : _memorySendTimeWeekdaysZh)[time.weekday - 1];
  final stamp = english
      ? '[Sent at: $date $clock $weekday]'
      : '[发送时间：$date $clock $weekday]';
  final body = content.trimRight();
  return body.isEmpty ? stamp : '$body\n\n$stamp';
}

MemoryMessage _copyMemoryMessage(
  MemoryMessage message, {
  required String content,
}) {
  return MemoryMessage(
    role: message.role,
    content: content,
    createdAt: message.createdAt,
    reasoningContent: message.reasoningContent,
    reasoningDurationMs: message.reasoningDurationMs,
    toolName: message.toolName,
    toolCallId: message.toolCallId,
    toolCalls: message.toolCalls,
    sources: message.sources,
    modeIds: message.modeIds,
    imageNames: message.imageNames,
  );
}

/// 解析 AI 返回的全局签 JSON（允许包裹 Markdown 代码围栏）。
/// 任一不合法时返回 null，调用方按 AI 失败处理。
List<GlobalSignDraftItem>? parseGlobalSignDrafts(String content) {
  Object? decoded;
  try {
    decoded = jsonDecode(_stripMarkdownFence(content));
  } catch (_) {
    return null;
  }
  if (decoded is! Map) {
    return null;
  }
  final items = decoded['items'];
  if (items is! List) {
    return null;
  }
  final drafts = <GlobalSignDraftItem>[];
  for (final entry in items) {
    if (entry is! Map) {
      return null;
    }
    final id = entry['id'];
    final text = entry['content'];
    if (text is! String || text.trim().isEmpty) {
      return null;
    }
    drafts.add(
      GlobalSignDraftItem(id: id is String ? id.trim() : '', content: text),
    );
  }
  return drafts;
}

String _stripMarkdownFence(String content) {
  var text = content.trim();
  if (!text.startsWith('```')) {
    return text;
  }
  final firstNewline = text.indexOf('\n');
  if (firstNewline >= 0) {
    text = text.substring(firstNewline + 1);
  }
  text = text.trimRight();
  if (text.endsWith('```')) {
    text = text.substring(0, text.length - 3);
  }
  return text.trim();
}

class AiClientService {
  const AiClientService({
    this.memoryConversationService = const MemoryConversationService(),
  });

  final MemoryConversationService memoryConversationService;

  Future<StructuredWorkNote?> generateStructuredNote({
    required String appDataDir,
    required AppConfig config,
    required String input,
    List<AiImageInput> images = const [],
  }) async {
    final selection = _selectModel(config, 'intelligentGenerationModel');
    if (selection == null) {
      return null;
    }
    final safeImages = _imageCapableModel(selection.model)
        ? selectAiImagesWithinBudget(images)
        : const <AiImageInput>[];

    final response = await rust_api.generateStructuredNote(
      request: rust_ai.StructuredNoteRequest(
        appDataDir: appDataDir,
        provider: _toRustProvider(selection.provider),
        model: _toRustModel(selection.model),
        input: input,
        images: safeImages.map(_toRustImageAttachment).toList(),
        sections: [
          for (final section in config.structuredNoteSections)
            rust_ai.StructuredNoteSectionDefinition(
              id: section.id,
              title: section.title,
              aiInstruction: section.aiInstruction,
            ),
        ],
        industry: config.industry,
        language: resolveAppLanguage(config.language),
        apiLogEnabled: config.apiLogEnabled,
      ),
    );

    if (!response.ok) {
      return null;
    }

    final itemsById = {
      for (final section in response.sections) section.id: section.items,
    };
    return StructuredWorkNote(
      rawInput: input,
      sections: [
        for (final section in config.structuredNoteSections)
          StructuredWorkNoteSection(
            id: section.id,
            items: itemsById[section.id] ?? const [],
          ),
      ],
    );
  }

  Future<String?> mergeDailyMarkdown({
    required String appDataDir,
    required AppConfig config,
    required String existingMarkdown,
    required StructuredWorkNote note,
    required DateTime date,
  }) async {
    final selection = _selectModel(config, 'intelligentGenerationModel');
    if (selection == null) {
      return null;
    }

    final response = await rust_api.mergeDailyNote(
      request: rust_ai.DailyMergeRequest(
        appDataDir: appDataDir,
        provider: _toRustProvider(selection.provider),
        model: _toRustModel(selection.model),
        existingMarkdown: existingMarkdown,
        rawInput: note.rawInput,
        images: const [],
        date: _formatDate(date),
        industry: config.industry,
        mergePrompt: _renderDailyMergePrompt(
          config.dailyMergePrompt,
          language: resolveAppLanguage(config.language),
          date: _formatDate(date),
          existingMarkdown: existingMarkdown,
          note: note,
          industry: config.industry,
        ),
        jsonOutput: false,
        language: resolveAppLanguage(config.language),
        apiLogEnabled: config.apiLogEnabled,
      ),
    );

    if (!response.ok || response.content.trim().isEmpty) {
      return null;
    }

    return '${response.content.trimRight()}\n';
  }

  Future<List<GlobalSignDraftItem>?> generateGlobalSign({
    required String appDataDir,
    required AppConfig config,
    required DateTime date,
    required String dailyMarkdown,
    required String currentItemsJson,
    required String rawInput,
  }) async {
    final selection = _selectModel(config, 'intelligentGenerationModel');
    if (selection == null) {
      return null;
    }

    final response = await rust_api.mergeDailyNote(
      request: rust_ai.DailyMergeRequest(
        appDataDir: appDataDir,
        provider: _toRustProvider(selection.provider),
        model: _toRustModel(selection.model),
        existingMarkdown: dailyMarkdown,
        rawInput: rawInput,
        images: const [],
        date: _formatDate(date),
        industry: config.industry,
        mergePrompt: _renderGlobalSignPrompt(
          config.globalSignPrompt,
          language: resolveAppLanguage(config.language),
          date: _formatDate(date),
          dailyMarkdown: dailyMarkdown,
          currentItemsJson: currentItemsJson,
          rawInput: rawInput,
          industry: config.industry,
        ),
        jsonOutput: true,
        language: resolveAppLanguage(config.language),
        apiLogEnabled: config.apiLogEnabled,
      ),
    );

    if (!response.ok || response.content.trim().isEmpty) {
      return null;
    }

    return parseGlobalSignDrafts(response.content);
  }

  Future<String?> generateWeeklyReport({
    required String appDataDir,
    required AppConfig config,
    required String sourceMarkdown,
    required String periodLabel,
    List<AiImageInput> images = const [],
  }) {
    final language = resolveAppLanguage(config.language);
    return _generateReport(
      appDataDir: appDataDir,
      config: config,
      sourceMarkdown: sourceMarkdown,
      periodLabel: periodLabel,
      monthly: false,
      images: images,
      reportPrompt: _renderWeeklyReportPrompt(
        config.weeklyReportPrompt,
        language: language,
        periodLabel: periodLabel,
        sourceMarkdown: sourceMarkdown,
        industry: config.industry,
      ),
    );
  }

  Future<String?> generateMonthlyReport({
    required String appDataDir,
    required AppConfig config,
    required String sourceMarkdown,
    required String periodLabel,
    List<AiImageInput> images = const [],
  }) {
    return _generateReport(
      appDataDir: appDataDir,
      config: config,
      sourceMarkdown: sourceMarkdown,
      periodLabel: periodLabel,
      monthly: true,
      images: images,
      reportPrompt: '',
    );
  }

  Future<ReportRegenerationResult> regenerateReport({
    required String appDataDir,
    required AppConfig config,
    required NoteKind kind,
    required String targetPath,
    required String dailyNotesDirectory,
    required String weeklyNotesDirectory,
  }) async {
    final selection = _selectModel(config, 'intelligentGenerationModel');
    if (selection == null) {
      return ReportRegenerationResult(
        ok: false,
        path: '',
        errorMessage: resolveAppLanguage(config.language) == 'en'
            ? 'No intelligent-generation model configured.'
            : '未配置智能生成模型。',
      );
    }

    final response = await rust_report_api.regenerateReport(
      request: rust_report.RegenerateReportRequest(
        appDataDir: appDataDir,
        provider: _toRustProvider(selection.provider),
        model: _toRustModel(selection.model),
        kind: kind.directoryName,
        targetPath: targetPath,
        dailyNotesDirectory: dailyNotesDirectory,
        weeklyNotesDirectory: weeklyNotesDirectory,
        industry: config.industry,
        dailyMergePrompt: config.dailyMergePrompt.trim().isEmpty
            ? defaultDailyMergePromptFor(resolveAppLanguage(config.language))
            : config.dailyMergePrompt,
        weeklyReportPrompt: config.weeklyReportPrompt.trim().isEmpty
            ? defaultWeeklyReportPromptFor(resolveAppLanguage(config.language))
            : config.weeklyReportPrompt,
        language: resolveAppLanguage(config.language),
        apiLogEnabled: config.apiLogEnabled,
        includeImages: reportImageInputAllowed(config),
      ),
    );

    return ReportRegenerationResult(
      ok: response.ok,
      path: response.path,
      errorMessage: response.errorMessage,
    );
  }

  Future<String?> _generateReport({
    required String appDataDir,
    required AppConfig config,
    required String sourceMarkdown,
    required String periodLabel,
    required bool monthly,
    required String reportPrompt,
    List<AiImageInput> images = const [],
  }) async {
    final selection = _selectModel(config, 'intelligentGenerationModel');
    if (selection == null) {
      return null;
    }

    final safeImages = config.reportImageInputEnabled &&
            selection.provider.protocol == 'openaiCompatible' &&
            _imageCapableModel(selection.model)
        ? selectAiImagesWithinBudget(images)
        : const <AiImageInput>[];

    final request = rust_ai.ReportRequest(
      appDataDir: appDataDir,
      provider: _toRustProvider(selection.provider),
      model: _toRustModel(selection.model),
      sourceMarkdown: sourceMarkdown,
      images: safeImages.map(_toRustImageAttachment).toList(),
      periodLabel: periodLabel,
      industry: config.industry,
      reportPrompt: reportPrompt,
      language: resolveAppLanguage(config.language),
      apiLogEnabled: config.apiLogEnabled,
    );
    final response = monthly
        ? await rust_api.generateMonthlyReport(request: request)
        : await rust_api.generateWeeklyReport(request: request);
    if (!response.ok || response.content.trim().isEmpty) {
      return null;
    }

    return '${response.content.trimRight()}\n';
  }

  Future<rust_ai.ProviderTestResult> testProviderConnection({
    required String appDataDir,
    required bool apiLogEnabled,
    required ProviderConfig provider,
    required ModelConfig model,
    required String language,
  }) async {
    final result = await rust_api.testProviderConnection(
      appDataDir: appDataDir,
      apiLogEnabled: apiLogEnabled,
      provider: _toRustProvider(provider),
      model: _toRustModel(model),
    );
    // Rust 侧的错误消息未本地化，已知错误码在这里映射为界面语言文案。
    if (!result.ok && result.errorCode == 'missing_api_key') {
      return rust_ai.ProviderTestResult(
        ok: false,
        message: language == 'en'
            ? 'The provider API key is empty.'
            : '供应商 API Key 为空。',
        errorCode: result.errorCode,
      );
    }
    return result;
  }

  Future<rust_ai.ProviderTestResult> testProviderConnectionStream({
    required String appDataDir,
    required bool apiLogEnabled,
    required ProviderConfig provider,
    required ModelConfig model,
    required String language,
  }) async {
    final english = language == 'en';
    final isGemini = provider.protocol == 'gemini';
    if (provider.protocol != 'openaiCompatible' && !isGemini) {
      return rust_ai.ProviderTestResult(
        ok: false,
        message: english
            ? 'Streaming connection test currently only supports OpenAI-compatible or Gemini providers.'
            : '流式连接测试目前仅支持 OpenAI-compatible 或 Gemini 供应商。',
        errorCode: 'unsupported_stream_protocol',
      );
    }
    if (provider.apiKey.trim().isEmpty) {
      return rust_ai.ProviderTestResult(
        ok: false,
        message: english ? 'The provider API key is empty.' : '供应商 API Key 为空。',
        errorCode: 'missing_api_key',
      );
    }

    final client = HttpClient();
    try {
      final url = isGemini
          ? _geminiStreamGenerateContentUrl(provider, model.modelId)
          : _joinUrl(provider.baseUrl, provider.apiPath);
      final request = await client
          .postUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (isGemini) {
        request.headers.set('x-goog-api-key', provider.apiKey);
      } else {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${provider.apiKey}',
        );
      }
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        ContentType.json.mimeType,
      );
      final body = isGemini
          ? {
              'systemInstruction': {
                'parts': [
                  {
                    'text':
                        'You are a connection test endpoint. Reply with OK only.',
                  },
                ],
              },
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': 'Say OK.'},
                  ],
                },
              ],
              'generationConfig': {'temperature': 0.2},
            }
          : _isResponsesEndpoint(provider)
          ? {
              'model': model.modelId,
              'instructions':
                  'You are a connection test endpoint. Reply with OK only.',
              'input': 'Say OK.',
              'temperature': 0.2,
              'stream': true,
            }
          : {
              'model': model.modelId,
              'messages': const [
                {
                  'role': 'system',
                  'content':
                      'You are a connection test endpoint. Reply with OK only.',
                },
                {'role': 'user', 'content': 'Say OK.'},
              ],
              'temperature': 0.2,
              'stream': true,
            };
      request.write(jsonEncode(body));

      final response = await request.close().timeout(
        const Duration(seconds: 45),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decoder.bind(response).join();
        return rust_ai.ProviderTestResult(
          ok: false,
          message: 'HTTP ${response.statusCode}: $body',
          errorCode: 'stream_http_error',
        );
      }

      var buffer = '';
      var sawStreamEvent = false;
      await for (final chunk
          in utf8.decoder.bind(response).timeout(const Duration(seconds: 45))) {
        buffer += chunk;
        while (true) {
          final lineEnd = buffer.indexOf('\n');
          if (lineEnd < 0) {
            break;
          }
          final line = buffer.substring(0, lineEnd).trim();
          buffer = buffer.substring(lineEnd + 1);
          if (!line.startsWith('data:')) {
            continue;
          }
          final payload = line.substring(5).trim();
          if (payload.isEmpty) {
            continue;
          }
          if (payload == '[DONE]') {
            return rust_ai.ProviderTestResult(
              ok: true,
              message: english ? 'Streaming connection succeeded' : '流式连接成功',
              errorCode: '',
            );
          }
          sawStreamEvent = true;
          final errorMessage = _readStreamErrorMessage(payload);
          if (errorMessage != null) {
            return rust_ai.ProviderTestResult(
              ok: false,
              message: errorMessage,
              errorCode: 'stream_error',
            );
          }
        }
      }

      if (sawStreamEvent) {
        return rust_ai.ProviderTestResult(
          ok: true,
          message: english ? 'Streaming connection succeeded' : '流式连接成功',
          errorCode: '',
        );
      }

      final tail = buffer.trim();
      if (tail.isNotEmpty) {
        final errorMessage = _readStreamErrorMessage(tail);
        if (errorMessage != null) {
          return rust_ai.ProviderTestResult(
            ok: false,
            message: errorMessage,
            errorCode: 'stream_error',
          );
        }
      }

      return rust_ai.ProviderTestResult(
        ok: false,
        message: english
            ? 'No valid events received during the streaming test.'
            : '流式连接测试未收到有效事件。',
        errorCode: 'stream_no_event',
      );
    } on TimeoutException {
      return rust_ai.ProviderTestResult(
        ok: false,
        message: english ? 'Streaming connection test timed out.' : '流式连接测试超时。',
        errorCode: 'stream_timeout',
      );
    } catch (error) {
      return rust_ai.ProviderTestResult(
        ok: false,
        message: error.toString(),
        errorCode: 'stream_request_failed',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<rust_ai.ModelListResult> fetchProviderModels({
    required String appDataDir,
    required bool apiLogEnabled,
    required ProviderConfig provider,
  }) {
    return rust_api.fetchProviderModels(
      appDataDir: appDataDir,
      apiLogEnabled: apiLogEnabled,
      provider: _toRustProvider(provider),
    );
  }

  String _renderDailyMergePrompt(
    String template, {
    required String language,
    required String date,
    required String existingMarkdown,
    required StructuredWorkNote note,
    required String industry,
  }) {
    final emptyText = language == 'en' ? '(empty)' : '（空）';
    final replacements = <String, String>{
      '{date}': date,
      '{existing_markdown}': existingMarkdown.trim().isEmpty
          ? emptyText
          : existingMarkdown.trim(),
      '{raw_input}': note.rawInput.trim(),
      '{completed}': _formatPromptItems(
        note.itemsFor(StructuredNoteSectionIds.a),
        emptyText,
      ),
      '{issues}': _formatPromptItems(
        note.itemsFor(StructuredNoteSectionIds.b),
        emptyText,
      ),
      '{plans}': _formatPromptItems(
        note.itemsFor(StructuredNoteSectionIds.c),
        emptyText,
      ),
      '{industry}': industry.trim().isEmpty
          ? (language == 'en' ? 'Not set' : '未设置')
          : industry.trim(),
    };
    var rendered = template.trim().isEmpty
        ? defaultDailyMergePromptFor(language)
        : template;
    for (final entry in replacements.entries) {
      rendered = rendered.replaceAll(entry.key, entry.value);
    }
    return rendered;
  }

  String _renderGlobalSignPrompt(
    String template, {
    required String language,
    required String date,
    required String dailyMarkdown,
    required String currentItemsJson,
    required String rawInput,
    required String industry,
  }) {
    final replacements = <String, String>{
      '{date}': date,
      '{daily_markdown}': dailyMarkdown.trim().isEmpty
          ? (language == 'en' ? '(empty)' : '（空）')
          : dailyMarkdown.trim(),
      '{global_sign}': currentItemsJson.trim().isEmpty
          ? '{"items": []}'
          : currentItemsJson.trim(),
      '{raw_input}': rawInput.trim(),
      '{industry}': industry.trim().isEmpty
          ? (language == 'en' ? 'Not set' : '未设置')
          : industry.trim(),
    };
    var rendered = template.trim().isEmpty
        ? defaultGlobalSignPromptFor(language)
        : template;
    for (final entry in replacements.entries) {
      rendered = rendered.replaceAll(entry.key, entry.value);
    }
    return rendered;
  }

  String _renderWeeklyReportPrompt(
    String template, {
    required String language,
    required String periodLabel,
    required String sourceMarkdown,
    required String industry,
  }) {
    final emptyText = language == 'en' ? '(empty)' : '（空）';
    final replacements = <String, String>{
      '{period_label}': periodLabel.trim(),
      '{source_markdown}': sourceMarkdown.trim().isEmpty
          ? emptyText
          : sourceMarkdown.trim(),
      '{industry}': industry.trim().isEmpty
          ? (language == 'en' ? 'Not set' : '未设置')
          : industry.trim(),
    };
    var rendered = template.trim().isEmpty
        ? defaultWeeklyReportPromptFor(language)
        : template;
    for (final entry in replacements.entries) {
      rendered = rendered.replaceAll(entry.key, entry.value);
    }
    return rendered;
  }

  String _formatPromptItems(List<String> items, String emptyText) {
    if (items.isEmpty) {
      return emptyText;
    }
    return items.map((item) => '- $item').join('\n');
  }

  Future<({String? content, String? error})> fimCompleteMarkdown({
    required String appDataDir,
    required AppConfig config,
    required String prompt,
    required String suffix,
  }) async {
    final modelRef = ModelReference.parse(
      config.defaultModels['editCompletionModel'],
    );
    if (modelRef == null) {
      return (content: null, error: null);
    }

    final selection = _findFimModel(config, modelRef);
    if (selection == null) {
      return (content: null, error: null);
    }

    final response = await rust_api.fimComplete(
      request: rust_ai.FimCompleteRequest(
        appDataDir: appDataDir,
        provider: _toRustProvider(selection.provider),
        model: _toRustModel(selection.model),
        prompt: prompt,
        suffix: suffix,
        completionProtocol: selection.model.completionProtocol,
        apiLogEnabled: config.apiLogEnabled,
      ),
    );

    if (!response.ok) {
      return (content: null, error: response.errorMessage);
    }
    if (response.content.isEmpty) {
      return (content: null, error: null);
    }

    return (content: response.content, error: null);
  }

  Future<rust_ai.MemoryToolChatResult?> memoryToolChat({
    required String appDataDir,
    required AppConfig config,
    required List<MemoryMessage> messages,
    bool thinkingEnabled = true,
    String reasoningEffort = 'high',
  }) async {
    final selection = _selectModel(config, 'memoryBookModel');
    if (selection == null) {
      return null;
    }

    final response = await rust_api.memoryToolChat(
      request: rust_ai.MemoryToolChatRequest(
        appDataDir: appDataDir,
        provider: _toRustProvider(selection.provider),
        model: _toRustModel(selection.model),
        messages: await _toRustChatMessages(
          appDataDir,
          sanitizeMemoryMessagesForModel(
            messages,
            language: resolveAppLanguage(config.language),
          ),
        ),
        thinkingEnabled: thinkingEnabled,
        reasoningEffort: reasoningEffort,
        language: resolveAppLanguage(config.language),
        apiLogEnabled: config.apiLogEnabled,
      ),
    );

    return response.ok ? response : null;
  }

  Future<Stream<rust_ai.MemoryToolChatStreamEvent>?> memoryToolChatStream({
    required String appDataDir,
    required AppConfig config,
    required List<MemoryMessage> messages,
    required bool thinkingEnabled,
    required String reasoningEffort,
  }) async {
    final selection = _selectModel(config, 'memoryBookModel');
    if (selection == null) {
      return null;
    }

    return rust_api.memoryToolChatStream(
      request: rust_ai.MemoryToolChatRequest(
        appDataDir: appDataDir,
        provider: _toRustProvider(selection.provider),
        model: _toRustModel(selection.model),
        messages: await _toRustChatMessages(
          appDataDir,
          sanitizeMemoryMessagesForModel(
            messages,
            language: resolveAppLanguage(config.language),
          ),
        ),
        thinkingEnabled: thinkingEnabled,
        reasoningEffort: reasoningEffort,
        language: resolveAppLanguage(config.language),
        apiLogEnabled: config.apiLogEnabled,
      ),
    );
  }

  String memoryModelLabel(AppConfig config) {
    final modelRef = ModelReference.parse(
      config.defaultModels['memoryBookModel'],
    );
    if (modelRef == null) {
      return resolveAppLanguage(config.language) == 'en'
          ? 'Memory model not selected'
          : '记忆模型未选择';
    }
    final selection = _findModel(config, modelRef);
    if (selection != null) {
      return '${selection.model.displayName} · ${selection.provider.name}';
    }
    return modelRef.modelId;
  }

  String? fimUnavailableReason(AppConfig config) {
    final english = resolveAppLanguage(config.language) == 'en';
    final modelRef = ModelReference.parse(
      config.defaultModels['editCompletionModel'],
    );
    if (modelRef == null) {
      return english ? 'No edit-completion model selected' : '未选择编辑补全模型';
    }

    final fimSelection = _findFimModel(config, modelRef);
    if (fimSelection != null) {
      return null;
    }

    final selection = _findModel(config, modelRef);
    if (selection == null) {
      return english
          ? 'The edit-completion model does not exist or was deleted'
          : '编辑补全模型不存在或已被删除';
    }
    if (!selection.provider.enabled) {
      return english
          ? 'The provider of the edit-completion model is disabled'
          : '编辑补全模型所在供应商未启用';
    }
    if (selection.provider.apiKey.trim().isEmpty) {
      return english
          ? 'The provider of the edit-completion model has an empty API key'
          : '编辑补全模型所在供应商 API Key 为空';
    }
    if (selection.provider.protocol != 'openaiCompatible') {
      return english
          ? 'FIM only supports OpenAI-compatible providers'
          : 'FIM 仅支持 OpenAI-compatible 供应商';
    }
    if (!selection.model.modelTypes.contains('completion')) {
      return english
          ? 'The edit-completion model is not marked as a completion model'
          : '编辑补全模型的模型类型没有勾选“补全”';
    }
    return null;
  }

  bool supportsMultimodalImageInput(AppConfig config) {
    final selection = _selectModel(config, 'intelligentGenerationModel');
    return selection != null && _imageCapableModel(selection.model);
  }

  /// Whether the memory-book chat may attach pasted images: the selected
  /// memory model must accept image input and its provider must speak the
  /// OpenAI-compatible protocol (the only protocol that carries images in
  /// memory requests for now).
  bool memoryModelSupportsImageInput(AppConfig config) {
    final selection = _selectModel(config, 'memoryBookModel');
    return selection != null &&
        selection.provider.protocol == 'openaiCompatible' &&
        _imageCapableModel(selection.model);
  }

  /// Whether the selected intelligent-generation model may receive note
  /// images in report requests: same protocol/input-mode rule as the memory
  /// book, but resolved against the report model.
  bool reportModelSupportsImageInput(AppConfig config) {
    final selection = _selectModel(config, 'intelligentGenerationModel');
    return selection != null &&
        selection.provider.protocol == 'openaiCompatible' &&
        _imageCapableModel(selection.model);
  }

  /// 报告生成是否真正把笔记图片发送给 AI：开关开启且智能生成模型链路
  /// 支持图片输入；任一不满足时静默按纯文本处理。
  bool reportImageInputAllowed(AppConfig config) {
    return config.reportImageInputEnabled &&
        reportModelSupportsImageInput(config);
  }

  _ModelSelection? _findFimModel(AppConfig config, ModelReference modelRef) {
    for (final provider in config.providers) {
      if (modelRef.providerId != null && provider.id != modelRef.providerId) {
        continue;
      }
      if (!provider.enabled ||
          provider.apiKey.trim().isEmpty ||
          provider.protocol != 'openaiCompatible') {
        continue;
      }
      for (final model in provider.models) {
        if (model.modelId == modelRef.modelId &&
            model.modelTypes.contains('completion')) {
          return _ModelSelection(provider: provider, model: model);
        }
      }
    }
    return null;
  }

  _ModelSelection? _selectModel(
    AppConfig config,
    String key, {
    bool requireCompletion = false,
  }) {
    final modelRef = ModelReference.parse(config.defaultModels[key]);
    if (modelRef == null) {
      return null;
    }

    final selection = _findAvailableModel(
      config,
      modelRef,
      requireCompletion: requireCompletion,
    );
    return selection;
  }

  _ModelSelection? _findAvailableModel(
    AppConfig config,
    ModelReference modelRef, {
    bool requireCompletion = false,
  }) {
    return _findModel(
      config,
      modelRef,
      requireEnabledProvider: true,
      requireApiKey: true,
      requireCompletion: requireCompletion,
    );
  }

  _ModelSelection? _findModel(
    AppConfig config,
    ModelReference modelRef, {
    bool requireEnabledProvider = false,
    bool requireApiKey = false,
    bool requireCompletion = false,
  }) {
    for (final provider in config.providers) {
      if (modelRef.providerId != null && provider.id != modelRef.providerId) {
        continue;
      }
      if (requireEnabledProvider && !provider.enabled) {
        continue;
      }
      if (requireApiKey && provider.apiKey.trim().isEmpty) {
        continue;
      }
      for (final model in provider.models) {
        if (model.modelId == modelRef.modelId) {
          if (requireCompletion && !model.modelTypes.contains('completion')) {
            continue;
          }
          return _ModelSelection(provider: provider, model: model);
        }
      }
    }

    return null;
  }

  rust_ai.AiProvider _toRustProvider(ProviderConfig provider) {
    return rust_ai.AiProvider(
      id: provider.id,
      name: provider.name,
      protocol: provider.protocol,
      apiKey: provider.apiKey,
      baseUrl: provider.baseUrl,
      apiPath: provider.apiPath,
    );
  }

  rust_ai.AiModel _toRustModel(ModelConfig model) {
    return rust_ai.AiModel(
      modelId: model.modelId,
      displayName: model.displayName,
    );
  }

  rust_ai.AiImageAttachment _toRustImageAttachment(AiImageInput image) {
    return rust_ai.AiImageAttachment(
      name: image.name,
      mimeType: image.mimeType,
      dataBase64: base64Encode(image.bytes),
    );
  }

  bool _imageCapableModel(ModelConfig model) {
    return model.inputModes.contains('image');
  }

  Future<List<rust_ai.AiChatMessage>> _toRustChatMessages(
    String appDataDir,
    List<MemoryMessage> messages,
  ) async {
    final result = <rust_ai.AiChatMessage>[];
    for (final message in messages) {
      result.add(await _toRustChatMessage(appDataDir, message));
    }
    return result;
  }

  Future<rust_ai.AiChatMessage> _toRustChatMessage(
    String appDataDir,
    MemoryMessage message,
  ) async {
    return rust_ai.AiChatMessage(
      role: message.role == 'ai' ? 'assistant' : message.role,
      content: message.content,
      reasoningContent: message.reasoningContent,
      toolCallId: message.toolCallId ?? '',
      toolCalls: message.toolCalls
          .map(
            (toolCall) => rust_ai.AiToolCall(
              id: toolCall.id,
              name: toolCall.name,
              arguments: toolCall.arguments,
            ),
          )
          .toList(),
      images: await _toRustMemoryImages(appDataDir, message),
    );
  }

  /// Loads the image bytes saved for a user message. Only user messages
  /// carry images; missing files are skipped so a moved data directory
  /// degrades to text-only history instead of failing the request.
  Future<List<rust_ai.AiImageAttachment>> _toRustMemoryImages(
    String appDataDir,
    MemoryMessage message,
  ) async {
    if (message.role != 'user' || message.imageNames.isEmpty) {
      return const [];
    }
    final images = <rust_ai.AiImageAttachment>[];
    for (final name in message.imageNames) {
      final bytes = await memoryConversationService.readImageBytes(
        appDataDir: appDataDir,
        name: name,
      );
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      images.add(
        rust_ai.AiImageAttachment(
          name: name,
          mimeType: imageMimeTypeForExtension(name.split('.').last),
          dataBase64: base64Encode(bytes),
        ),
      );
    }
    return images;
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _joinUrl(String baseUrl, String apiPath) {
    final normalizedBase = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final normalizedPath = apiPath.trim().replaceAll(RegExp(r'^/+'), '');
    if (normalizedPath.isEmpty) {
      return normalizedBase;
    }
    return '$normalizedBase/$normalizedPath';
  }

  bool _isResponsesEndpoint(ProviderConfig provider) {
    return _joinUrl(
      provider.baseUrl,
      provider.apiPath,
    ).replaceAll(RegExp(r'/+$'), '').endsWith('/responses');
  }

  String _geminiStreamGenerateContentUrl(
    ProviderConfig provider,
    String modelId,
  ) {
    final base = provider.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base/v1beta/models/$modelId:streamGenerateContent?alt=sse';
  }

  String? _readStreamErrorMessage(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] != null) {
          return error['message'].toString();
        }
        if (error is String && error.isNotEmpty) {
          return error;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

class AiImageInput {
  const AiImageInput({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  factory AiImageInput.fromBytes({
    required String name,
    required Uint8List bytes,
    required String extension,
  }) {
    final mimeType = isSupportedAiImageExtension(extension)
        ? imageMimeTypeForExtension(extension)
        : 'application/octet-stream';
    return AiImageInput(name: name, bytes: bytes, mimeType: mimeType);
  }

  final String name;
  final Uint8List bytes;
  final String mimeType;
}

bool isSupportedAiImageInput(AiImageInput image) {
  return image.bytes.isNotEmpty &&
      image.bytes.length <= maxAiImageInputBytes &&
      supportedAiImageMimeTypes.contains(image.mimeType.trim().toLowerCase());
}

bool isSupportedAiImageExtension(String extension) {
  final normalized = extension.trim().toLowerCase().replaceFirst('.', '');
  return supportedAiImageExtensions.contains(normalized);
}

/// 按调用方给出的顺序（最新在前）挑选可发送给 AI 的图片：先用
/// [isSupportedAiImageInput] 过滤单张限制（非空、≤5MB、格式白名单），
/// 再累计字节总量，张数达 [maxAiImageInputs] 或累计超出
/// [maxAiImageTotalBytes] 时停止，超出预算的那张及其后全部丢弃。
///
/// Rust 侧存在同口径副本：report_regeneration.rs 的报表收集限制与
/// ai_openai.rs 的 MAX_MEMORY_IMAGE_TOTAL_BYTES。调整上述常量时需双侧同步。
List<AiImageInput> selectAiImagesWithinBudget(Iterable<AiImageInput> images) {
  final selected = <AiImageInput>[];
  var totalBytes = 0;
  for (final image in images) {
    if (selected.length >= maxAiImageInputs) {
      break;
    }
    if (!isSupportedAiImageInput(image)) {
      continue;
    }
    final nextTotal = totalBytes + image.bytes.length;
    if (nextTotal > maxAiImageTotalBytes) {
      break;
    }
    selected.add(image);
    totalBytes = nextTotal;
  }
  return selected;
}

class ReportRegenerationResult {
  const ReportRegenerationResult({
    required this.ok,
    required this.path,
    required this.errorMessage,
  });

  final bool ok;
  final String path;
  final String errorMessage;
}

class _ModelSelection {
  const _ModelSelection({required this.provider, required this.model});

  final ProviderConfig provider;
  final ModelConfig model;
}
