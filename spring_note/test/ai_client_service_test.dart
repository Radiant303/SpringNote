import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/model_config.dart';
import 'package:spring_note/core/models/model_reference.dart';
import 'package:spring_note/core/models/provider_config.dart';
import 'package:spring_note/core/services/ai_client_service.dart';

void main() {
  const service = AiClientService();

  test('model reference round trips provider-qualified values', () {
    final encoded = ModelReference.encode(
      providerId: 'openrouter/provider',
      modelId: 'openai/gpt-4.1-mini',
    );
    final parsed = ModelReference.parse(encoded);

    expect(parsed?.providerId, 'openrouter/provider');
    expect(parsed?.modelId, 'openai/gpt-4.1-mini');
    expect(parsed?.serialize(), encoded);
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

  test('DeepSeek template uses beta base URL for FIM-capable v4 model', () {
    final provider = ProviderConfig.template('DeepSeek');

    expect(provider.baseUrl, 'https://api.deepseek.com/beta');
    expect(provider.apiPath, '/chat/completions');
    expect(
      provider.models.map((model) => model.modelId),
      containsAll(['deepseek-v4-flash', 'deepseek-v4-pro']),
    );

    final fimModel = provider.models.firstWhere(
      (model) => model.modelId == 'deepseek-v4-pro',
    );
    expect(fimModel.modelTypes, contains('completion'));
    expect(fimModel.capabilities, contains('reasoning'));
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
