import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/memory_message.dart';
import 'package:spring_note/core/models/model_config.dart';
import 'package:spring_note/core/models/model_reference.dart';
import 'package:spring_note/core/models/provider_config.dart';
import 'package:spring_note/core/services/ai_client_service.dart';

void main() {
  const service = AiClientService();

  test('model reference round trips provider-qualified values', () {
    final encoded = ModelReference.encode(
      providerId: 'openrouter/provider',
      modelId: 'openai/gpt-4.1-mini::preview',
    );
    final parsed = ModelReference.parse(encoded);

    expect(parsed?.providerId, 'openrouter/provider');
    expect(parsed?.modelId, 'openai/gpt-4.1-mini::preview');
    expect(parsed?.serialize(), encoded);
  });

  test('model reference parses legacy provider-qualified values', () {
    final parsed = ModelReference.parse('openrouter::openai/gpt-4.1-mini');

    expect(parsed?.providerId, 'openrouter');
    expect(parsed?.modelId, 'openai/gpt-4.1-mini');
  });

  test('AI image input guard allows only safe multimodal images', () {
    expect(isSupportedAiImageExtension('png'), isTrue);
    expect(isSupportedAiImageExtension('.jpeg'), isTrue);
    expect(isSupportedAiImageExtension('svg'), isFalse);
    expect(isSupportedAiImageExtension('unknown'), isFalse);

    expect(
      isSupportedAiImageInput(
        AiImageInput(
          name: 'screen.png',
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/png',
        ),
      ),
      isTrue,
    );
    expect(
      isSupportedAiImageInput(
        AiImageInput(
          name: 'diagram.svg',
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/svg+xml',
        ),
      ),
      isFalse,
    );
    expect(
      isSupportedAiImageInput(
        AiImageInput(
          name: 'huge.png',
          bytes: Uint8List(maxAiImageInputBytes + 1),
          mimeType: 'image/png',
        ),
      ),
      isFalse,
    );
    expect(
      AiImageInput.fromBytes(
        name: 'capture.raw',
        bytes: Uint8List.fromList([1, 2, 3]),
        extension: 'raw',
      ).mimeType,
      'application/octet-stream',
    );
  });

  test('default templates mark known image-capable models', () {
    final openAi = ProviderConfig.template('OpenAI');
    expect(openAi.models.single.inputModes, contains('image'));

    final gemini = ProviderConfig.template('Google');
    expect(gemini.models.single.inputModes, contains('image'));

    final claude = ProviderConfig.template('Claude');
    expect(claude.models.single.inputModes, contains('image'));

    final deepSeek = ProviderConfig.template('DeepSeek');
    expect(deepSeek.models.first.inputModes, isNot(contains('image')));
  });

  test('memory sanitizer preserves complete tool call chains', () {
    final messages = [
      MemoryMessage(
        role: 'user',
        content: '查找日报',
        createdAt: DateTime(2026, 7, 10),
      ),
      MemoryMessage(
        role: 'assistant',
        content: '',
        createdAt: DateTime(2026, 7, 10, 0, 1),
        toolCalls: const [
          MemoryToolCallMessage(
            id: 'call-1',
            name: 'keyword_search',
            arguments: '{"keywords":["日报"]}',
          ),
        ],
      ),
      MemoryMessage(
        role: 'tool',
        content: '{"results":[]}',
        createdAt: DateTime(2026, 7, 10, 0, 2),
        toolName: 'keyword_search',
        toolCallId: 'call-1',
      ),
    ];

    final sanitized = sanitizeMemoryMessagesForModel(messages);

    expect(sanitized.map((message) => message.role), [
      'user',
      'assistant',
      'tool',
    ]);
    expect(sanitized[1].toolCalls.single.id, 'call-1');
    expect(sanitized[2].toolCallId, 'call-1');
  });

  test('memory sanitizer converts local and orphan tools to context', () {
    final messages = [
      MemoryMessage(
        role: 'user',
        content: '昨天做了什么？',
        createdAt: DateTime(2026, 7, 10),
      ),
      MemoryMessage(
        role: 'local_tool',
        content: 'Observation：找到日报',
        createdAt: DateTime(2026, 7, 10, 0, 1),
        toolName: 'keyword_search',
      ),
      MemoryMessage(
        role: 'tool',
        content: '{"legacy":true}',
        createdAt: DateTime(2026, 7, 10, 0, 2),
      ),
      MemoryMessage(
        role: 'ai',
        content: '你完成了日报整理。',
        createdAt: DateTime(2026, 7, 10, 0, 3),
      ),
    ];

    final sanitized = sanitizeMemoryMessagesForModel(messages);

    expect(sanitized, hasLength(2));
    expect(sanitized.first.role, 'user');
    expect(sanitized.first.content, contains('[应用提供的本地检索上下文'));
    expect(sanitized.first.content, contains('keyword_search'));
    expect(sanitized.first.content, contains('历史孤立工具结果'));
    expect(
      sanitized.any(
        (message) => message.role == 'tool' || message.role == 'local_tool',
      ),
      isFalse,
    );
  });

  test('memory sanitizer converts incomplete tool exchanges to context', () {
    final messages = [
      MemoryMessage(
        role: 'assistant',
        content: '准备查询',
        createdAt: DateTime(2026, 7, 10),
        toolCalls: const [
          MemoryToolCallMessage(
            id: 'call-1',
            name: 'keyword_search',
            arguments: '{}',
          ),
          MemoryToolCallMessage(
            id: 'call-2',
            name: 'read_daily_note',
            arguments: '{}',
          ),
        ],
      ),
      MemoryMessage(
        role: 'tool',
        content: '{"results":[]}',
        createdAt: DateTime(2026, 7, 10, 0, 1),
        toolCallId: 'call-1',
      ),
      MemoryMessage(
        role: 'user',
        content: '继续',
        createdAt: DateTime(2026, 7, 10, 0, 2),
      ),
    ];

    final sanitized = sanitizeMemoryMessagesForModel(messages);

    expect(
      sanitized.any(
        (message) => message.role == 'tool' || message.toolCalls.isNotEmpty,
      ),
      isFalse,
    );
    expect(sanitized.first.content, contains('历史工具调用链不完整，已转换为普通上下文'));
    expect(sanitized.first.content, contains('call-2'));
  });

  test('multimodal image support follows selected model input modes', () {
    final config = _duplicateModelConfig().copyWith(
      providers: [
        _duplicateModelConfig().providers[0].copyWith(
          models: const [
            ModelConfig(
              modelId: 'shared-chat',
              displayName: 'DeepSeek Shared',
              inputModes: ['text', 'image'],
            ),
          ],
        ),
      ],
      defaultModels: {
        ...AppConfig.defaults().defaultModels,
        'intelligentGenerationModel': 'shared-chat',
      },
    );

    expect(service.supportsMultimodalImageInput(config), isTrue);

    final textOnlyConfig = _duplicateModelConfig().copyWith(
      defaultModels: {
        ...AppConfig.defaults().defaultModels,
        'intelligentGenerationModel': ModelReference.encode(
          providerId: 'openrouter',
          modelId: 'shared-chat',
        ),
      },
    );
    expect(service.supportsMultimodalImageInput(textOnlyConfig), isFalse);
  });

  test(
    'memory model label resolves provider-qualified duplicate model ids',
    () {
      final config = _duplicateModelConfig().copyWith(
        defaultModels: {
          ...AppConfig.defaults().defaultModels,
          'memoryBookModel': ModelReference.encode(
            providerId: 'openrouter',
            modelId: 'shared-chat',
          ),
        },
      );

      expect(
        service.memoryModelLabel(config),
        'OpenRouter Shared · OpenRouter',
      );
    },
  );

  test('legacy model ids remain supported for default model lookup', () {
    final config = _duplicateModelConfig().copyWith(
      defaultModels: {
        ...AppConfig.defaults().defaultModels,
        'memoryBookModel': 'shared-chat',
      },
    );

    expect(service.memoryModelLabel(config), 'DeepSeek Shared · DeepSeek');
  });

  test(
    'legacy model ids skip disabled or unconfigured providers at request time',
    () {
      final baseConfig = _duplicateModelConfig();
      final config = baseConfig.copyWith(
        providers: [
          baseConfig.providers[0].copyWith(enabled: false),
          baseConfig.providers[1].copyWith(
            models: const [
              ModelConfig(
                modelId: 'shared-chat',
                displayName: 'OpenRouter Shared',
                modelTypes: ['chat', 'completion'],
              ),
            ],
          ),
        ],
        defaultModels: {
          ...AppConfig.defaults().defaultModels,
          'editCompletionModel': 'shared-chat',
        },
      );

      expect(service.fimUnavailableReason(config), isNull);
    },
  );

  test(
    'fim validation checks the selected provider instead of first model id',
    () {
      final config = _duplicateModelConfig().copyWith(
        defaultModels: {
          ...AppConfig.defaults().defaultModels,
          'editCompletionModel': ModelReference.encode(
            providerId: 'gemini-provider',
            modelId: 'shared-chat',
          ),
        },
      );

      expect(
        service.fimUnavailableReason(config),
        'FIM 仅支持 OpenAI-compatible 供应商',
      );
    },
  );

  test('fim validation accepts responses providers with completion type', () {
    final config = AppConfig.defaults().copyWith(
      providers: const [
        ProviderConfig(
          id: 'openai-responses',
          enabled: true,
          name: 'OpenAI Responses',
          protocol: 'openaiCompatible',
          apiKey: 'key',
          baseUrl: 'https://api.openai.com/v1',
          apiPath: '/responses',
          models: [
            ModelConfig(
              modelId: 'gpt-5-mini',
              displayName: 'GPT-5 Mini',
              modelTypes: ['chat', 'completion'],
            ),
          ],
        ),
      ],
      defaultModels: {
        ...AppConfig.defaults().defaultModels,
        'editCompletionModel': ModelReference.encode(
          providerId: 'openai-responses',
          modelId: 'gpt-5-mini',
        ),
      },
    );

    expect(service.fimUnavailableReason(config), isNull);
  });
}

AppConfig _duplicateModelConfig() {
  return AppConfig.defaults().copyWith(
    providers: const [
      ProviderConfig(
        id: 'deepseek',
        enabled: true,
        name: 'DeepSeek',
        protocol: 'openaiCompatible',
        apiKey: 'key-1',
        baseUrl: 'https://api.deepseek.com',
        apiPath: '/chat/completions',
        models: [
          ModelConfig(
            modelId: 'shared-chat',
            displayName: 'DeepSeek Shared',
            modelTypes: ['chat', 'completion'],
          ),
        ],
      ),
      ProviderConfig(
        id: 'openrouter',
        enabled: true,
        name: 'OpenRouter',
        protocol: 'openaiCompatible',
        apiKey: 'key-2',
        baseUrl: 'https://openrouter.ai/api/v1',
        apiPath: '/chat/completions',
        models: [
          ModelConfig(
            modelId: 'shared-chat',
            displayName: 'OpenRouter Shared',
            modelTypes: ['chat'],
          ),
        ],
      ),
      ProviderConfig(
        id: 'gemini-provider',
        enabled: true,
        name: 'Gemini',
        protocol: 'gemini',
        apiKey: 'key-3',
        baseUrl: 'https://generativelanguage.googleapis.com',
        apiPath: '',
        models: [
          ModelConfig(
            modelId: 'shared-chat',
            displayName: 'Gemini Shared',
            modelTypes: ['chat', 'completion'],
          ),
        ],
      ),
    ],
  );
}
