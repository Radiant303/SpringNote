import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../src/rust/ai.dart' as rust_ai;
import '../../src/rust/api/ai_api.dart' as rust_api;
import '../models/app_config.dart';
import '../models/memory_message.dart';
import '../models/model_config.dart';
import '../models/model_reference.dart';
import '../models/provider_config.dart';
import '../models/structured_work_note.dart';

class AiClientService {
  const AiClientService();

  Future<StructuredWorkNote?> generateStructuredNote({
    required String appDataDir,
    required AppConfig config,
    required String input,
  }) async {
    final selection = _selectModel(config, 'intelligentGenerationModel');
    if (selection == null) {
      return null;
    }

    final response = await rust_api.generateStructuredNote(
      request: rust_ai.StructuredNoteRequest(
        appDataDir: appDataDir,
        provider: _toRustProvider(selection.provider),
        model: _toRustModel(selection.model),
        input: input,
        industry: config.industry,
        apiLogEnabled: config.apiLogEnabled,
      ),
    );

    if (!response.ok) {
      return null;
    }

    return StructuredWorkNote(
      rawInput: input,
      completed: response.completed,
      issues: response.issues,
      plans: response.plans,
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
        completed: note.completed,
        issues: note.issues,
        plans: note.plans,
        date: _formatDate(date),
        industry: config.industry,
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

  Future<String?> fimCompleteMarkdown({
    required String appDataDir,
    required AppConfig config,
    required String prompt,
    required String suffix,
  }) async {
    if (fimUnavailableReason(config) != null) {
      return null;
    }

    final selection = _selectModel(
      config,
      'editCompletionModel',
      requireCompletion: true,
    );
    if (selection == null ||
        selection.provider.protocol != 'openaiCompatible') {
      return null;
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

    if (!response.ok || response.content.isEmpty) {
      return null;
    }

    return response.content;
  }

  Future<String?> memoryChat({
    required String appDataDir,
    required AppConfig config,
    required String question,
    required String contextMarkdown,
  }) async {
    final selection = _selectModel(config, 'memoryBookModel');
    if (selection == null) {
      return null;
    }

    final response = await rust_api.memoryChat(
      request: rust_ai.MemoryChatRequest(
        appDataDir: appDataDir,
        provider: _toRustProvider(selection.provider),
        model: _toRustModel(selection.model),
        question: question,
        contextMarkdown: contextMarkdown,
        apiLogEnabled: config.apiLogEnabled,
      ),
    );

    if (!response.ok || response.content.trim().isEmpty) {
      return null;
    }

    return response.content.trim();
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
        messages: messages.map(_toRustChatMessage).toList(),
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
        messages: messages.map(_toRustChatMessage).toList(),
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

  _ModelSelection? _selectModel(
    AppConfig config,
    String key, {
    bool requireCompletion = false,
  }) {
    final modelRef = ModelReference.parse(config.defaultModels[key]);
    if (modelRef == null) {
      return null;
    }

    final selection = _findModel(config, modelRef);
    if (selection == null ||
        !selection.provider.enabled ||
        selection.provider.apiKey.trim().isEmpty) {
      return null;
    }
    if (requireCompletion &&
        !selection.model.modelTypes.contains('completion')) {
      return null;
    }
    return selection;
  }

  _ModelSelection? _findModel(AppConfig config, ModelReference modelRef) {
    for (final provider in config.providers) {
      if (modelRef.providerId != null && provider.id != modelRef.providerId) {
        continue;
      }
      for (final model in provider.models) {
        if (model.modelId == modelRef.modelId) {
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

class _ModelSelection {
  const _ModelSelection({required this.provider, required this.model});

  final ProviderConfig provider;
  final ModelConfig model;
}
