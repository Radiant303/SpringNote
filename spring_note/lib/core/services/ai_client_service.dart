import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../src/rust/ai.dart' as rust_ai;
import '../../src/rust/api/ai_api.dart' as rust_api;
import '../models/app_config.dart';
import '../models/memory_message.dart';
import '../models/model_config.dart';
import '../models/model_reference.dart';
import '../models/provider_config.dart';
import '../models/structured_work_note.dart';
import 'image_file_types.dart';

const int maxAiImageInputs = 4;
const int maxAiImageInputBytes = 5 * 1024 * 1024;
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

List<MemoryMessage> sanitizeMemoryMessagesForModel(
  Iterable<MemoryMessage> messages,
) {
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
    final context = '$_localMemoryContextHeader\n${contextParts.join('\n\n')}';
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
          _brokenToolExchangeContext(message, toolResults),
        );
      }
      index = resultEnd;
      continue;
    }

    if (message.role == 'local_tool' || message.role == 'tool') {
      appendContext(message, _standaloneToolContext(message));
      index += 1;
      continue;
    }

    flushContext();
    if (message.role == 'user' ||
        message.role == 'assistant' ||
        message.role == 'ai') {
      output.add(message);
    } else {
      appendContext(message, '历史消息（原角色 ${message.role}）：\n${message.content}');
    }
    index += 1;
  }
  flushContext();
  return output;
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
) {
  final buffer = StringBuffer('历史工具调用链不完整，已转换为普通上下文。');
  if (assistant.content.trim().isNotEmpty) {
    buffer
      ..write('\n模型内容：\n')
      ..write(assistant.content.trim());
  }
  if (assistant.toolCalls.isNotEmpty) {
    buffer.write('\n工具请求：');
    for (final toolCall in assistant.toolCalls) {
      buffer
        ..write('\n- ${toolCall.name}')
        ..write('，调用 ID：${toolCall.id}')
        ..write('，参数：${toolCall.arguments}');
    }
  }
  if (toolResults.isNotEmpty) {
    buffer.write('\n已有工具结果：');
    for (final result in toolResults) {
      buffer
        ..write('\n- ${result.toolName ?? '未知工具'}')
        ..write('，调用 ID：${result.toolCallId ?? '缺失'}')
        ..write('\n  ${result.content}');
    }
  }
  return buffer.toString();
}

String _standaloneToolContext(MemoryMessage message) {
  final local = message.role == 'local_tool';
  final buffer = StringBuffer(local ? '本地检索步骤' : '历史孤立工具结果');
  if (message.toolName?.trim().isNotEmpty ?? false) {
    buffer.write('\n工具：${message.toolName!.trim()}');
  }
  if (!local && (message.toolCallId?.trim().isNotEmpty ?? false)) {
    buffer.write('\n调用 ID：${message.toolCallId!.trim()}');
  }
  if (message.content.trim().isNotEmpty) {
    buffer
      ..write('\n结果：\n')
      ..write(message.content.trim());
  }
  return buffer.toString();
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
  );
}

class AiClientService {
  const AiClientService();

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
        ? images.where(isSupportedAiImageInput).take(maxAiImageInputs).toList()
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
        date: _formatDate(date),
        industry: config.industry,
        mergePrompt: _renderDailyMergePrompt(
          config.dailyMergePrompt,
          date: _formatDate(date),
          existingMarkdown: existingMarkdown,
          note: note,
          industry: config.industry,
        ),
        apiLogEnabled: config.apiLogEnabled,
      ),
    );

    if (!response.ok || response.content.trim().isEmpty) {
      return null;
    }

    return '${response.content.trimRight()}\n';
  }

  Future<String?> generateWeeklyReport({
    required String appDataDir,
    required AppConfig config,
    required String sourceMarkdown,
    required String periodLabel,
  }) {
    return _generateReport(
      appDataDir: appDataDir,
      config: config,
      sourceMarkdown: sourceMarkdown,
      periodLabel: periodLabel,
      monthly: false,
    );
  }

  Future<String?> generateMonthlyReport({
    required String appDataDir,
    required AppConfig config,
    required String sourceMarkdown,
    required String periodLabel,
  }) {
    return _generateReport(
      appDataDir: appDataDir,
      config: config,
      sourceMarkdown: sourceMarkdown,
      periodLabel: periodLabel,
      monthly: true,
    );
  }

  Future<String?> _generateReport({
    required String appDataDir,
    required AppConfig config,
    required String sourceMarkdown,
    required String periodLabel,
    required bool monthly,
  }) async {
    final selection = _selectModel(config, 'intelligentGenerationModel');
    if (selection == null) {
      return null;
    }

    final request = rust_ai.ReportRequest(
      appDataDir: appDataDir,
      provider: _toRustProvider(selection.provider),
      model: _toRustModel(selection.model),
      sourceMarkdown: sourceMarkdown,
      periodLabel: periodLabel,
      industry: config.industry,
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
  }) {
    return rust_api.testProviderConnection(
      appDataDir: appDataDir,
      apiLogEnabled: apiLogEnabled,
      provider: _toRustProvider(provider),
      model: _toRustModel(model),
    );
  }

  Future<rust_ai.ProviderTestResult> testProviderConnectionStream({
    required String appDataDir,
    required bool apiLogEnabled,
    required ProviderConfig provider,
    required ModelConfig model,
  }) async {
    if (provider.protocol != 'openaiCompatible') {
      return const rust_ai.ProviderTestResult(
        ok: false,
        message: '流式连接测试目前仅支持 OpenAI-compatible 供应商。',
        errorCode: 'unsupported_stream_protocol',
      );
    }
    if (provider.apiKey.trim().isEmpty) {
      return const rust_ai.ProviderTestResult(
        ok: false,
        message: '供应商 API Key 为空。',
        errorCode: 'missing_api_key',
      );
    }

    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse(_joinUrl(provider.baseUrl, provider.apiPath)))
          .timeout(const Duration(seconds: 15));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${provider.apiKey}')
        ..set(HttpHeaders.contentTypeHeader, ContentType.json.mimeType);
      final body = _isResponsesEndpoint(provider)
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
            return const rust_ai.ProviderTestResult(
              ok: true,
              message: '流式连接成功',
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
        return const rust_ai.ProviderTestResult(
          ok: true,
          message: '流式连接成功',
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

      return const rust_ai.ProviderTestResult(
        ok: false,
        message: '流式连接测试未收到有效事件。',
        errorCode: 'stream_no_event',
      );
    } on TimeoutException {
      return const rust_ai.ProviderTestResult(
        ok: false,
        message: '流式连接测试超时。',
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
    required String date,
    required String existingMarkdown,
    required StructuredWorkNote note,
    required String industry,
  }) {
    final replacements = <String, String>{
      '{date}': date,
      '{existing_markdown}': existingMarkdown.trim().isEmpty
          ? '（空）'
          : existingMarkdown.trim(),
      '{raw_input}': note.rawInput.trim(),
      '{completed}': _formatPromptItems(
        note.itemsFor(StructuredNoteSectionIds.a),
      ),
      '{issues}': _formatPromptItems(note.itemsFor(StructuredNoteSectionIds.b)),
      '{plans}': _formatPromptItems(note.itemsFor(StructuredNoteSectionIds.c)),
      '{industry}': industry.trim().isEmpty ? '未设置' : industry.trim(),
    };
    var rendered = template.trim().isEmpty ? defaultDailyMergePrompt : template;
    for (final entry in replacements.entries) {
      rendered = rendered.replaceAll(entry.key, entry.value);
    }
    return rendered;
  }

  String _formatPromptItems(List<String> items) {
    if (items.isEmpty) {
      return '（空）';
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
        messages: sanitizeMemoryMessagesForModel(
          messages,
        ).map(_toRustChatMessage).toList(),
        thinkingEnabled: thinkingEnabled,
        reasoningEffort: reasoningEffort,
        apiLogEnabled: config.apiLogEnabled,
      ),
    );

    return response.ok ? response : null;
  }

  Stream<rust_ai.MemoryToolChatStreamEvent>? memoryToolChatStream({
    required String appDataDir,
    required AppConfig config,
    required List<MemoryMessage> messages,
    required bool thinkingEnabled,
    required String reasoningEffort,
  }) {
    final selection = _selectModel(config, 'memoryBookModel');
    if (selection == null) {
      return null;
    }

    return rust_api.memoryToolChatStream(
      request: rust_ai.MemoryToolChatRequest(
        appDataDir: appDataDir,
        provider: _toRustProvider(selection.provider),
        model: _toRustModel(selection.model),
        messages: sanitizeMemoryMessagesForModel(
          messages,
        ).map(_toRustChatMessage).toList(),
        thinkingEnabled: thinkingEnabled,
        reasoningEffort: reasoningEffort,
        apiLogEnabled: config.apiLogEnabled,
      ),
    );
  }

  String memoryModelLabel(AppConfig config) {
    final modelRef = ModelReference.parse(
      config.defaultModels['memoryBookModel'],
    );
    if (modelRef == null) {
      return '记忆模型未选择';
    }
    final selection = _findModel(config, modelRef);
    if (selection != null) {
      return '${selection.model.displayName} · ${selection.provider.name}';
    }
    return modelRef.modelId;
  }

  String? fimUnavailableReason(AppConfig config) {
    final modelRef = ModelReference.parse(
      config.defaultModels['editCompletionModel'],
    );
    if (modelRef == null) {
      return '未选择编辑补全模型';
    }

    final fimSelection = _findFimModel(config, modelRef);
    if (fimSelection != null) {
      return null;
    }

    final selection = _findModel(config, modelRef);
    if (selection == null) {
      return '编辑补全模型不存在或已被删除';
    }
    if (!selection.provider.enabled) {
      return '编辑补全模型所在供应商未启用';
    }
    if (selection.provider.apiKey.trim().isEmpty) {
      return '编辑补全模型所在供应商 API Key 为空';
    }
    if (selection.provider.protocol != 'openaiCompatible') {
      return 'FIM 仅支持 OpenAI-compatible 供应商';
    }
    if (!selection.model.modelTypes.contains('completion')) {
      return '编辑补全模型的模型类型没有勾选“补全”';
    }
    return null;
  }

  bool supportsMultimodalImageInput(AppConfig config) {
    final selection = _selectModel(config, 'intelligentGenerationModel');
    return selection != null && _imageCapableModel(selection.model);
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

  rust_ai.AiChatMessage _toRustChatMessage(MemoryMessage message) {
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
    );
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

class _ModelSelection {
  const _ModelSelection({required this.provider, required this.model});

  final ProviderConfig provider;
  final ModelConfig model;
}
