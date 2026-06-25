import 'model_config.dart';

class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.enabled,
    required this.name,
    required this.protocol,
    required this.apiKey,
    required this.baseUrl,
    required this.apiPath,
    required this.models,
  });

  final String id;
  final bool enabled;
  final String name;
  final String protocol;
  final String apiKey;
  final String baseUrl;
  final String apiPath;
  final List<ModelConfig> models;

  static const templateNames = [
    'OpenAI',
    'OpenAI Responses',
    'DeepSeek',
    'Qwen DashScope',
    'Kimi',
    'OpenRouter',
    'SiliconFlow',
    'Ollama',
    'Google',
    'Claude',
  ];

  factory ProviderConfig.fromJson(Map<String, Object?> json) {
    final protocol = json['protocol']?.toString() ?? 'openaiCompatible';
    final name = json['name']?.toString() ?? 'OpenAI';
    return ProviderConfig(
      id: json['id']?.toString() ?? _makeId(name),
      enabled: json['enabled'] as bool? ?? true,
      name: name,
      protocol: protocol,
      apiKey: json['apiKey']?.toString() ?? '',
      baseUrl: json['baseUrl']?.toString() ?? _defaultBaseUrl(protocol),
      apiPath: json['apiPath']?.toString() ?? _defaultApiPath(protocol),
      models: _readModels(json['models']),
    );
  }

  factory ProviderConfig.template(String template) {
    final normalized = template.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    if (normalized == 'google' || normalized == 'gemini') {
      return ProviderConfig(
        id: _makeId('Google'),
        enabled: true,
        name: 'Google',
        protocol: 'gemini',
        apiKey: '',
        baseUrl: 'https://generativelanguage.googleapis.com',
        apiPath: '',
        models: const [
          ModelConfig(
            modelId: 'gemini-2.5-flash',
            displayName: 'Gemini 2.5 Flash',
          ),
        ],
      );
    }
    if (normalized == 'claude') {
      return ProviderConfig(
        id: _makeId('Claude'),
        enabled: true,
        name: 'Claude',
        protocol: 'claude',
        apiKey: '',
        baseUrl: 'https://api.anthropic.com',
        apiPath: '/v1/messages',
        models: const [
          ModelConfig(
            modelId: 'claude-sonnet-4',
            displayName: 'Claude Sonnet 4',
          ),
        ],
      );
    }
    if (normalized == 'openairesponses' || normalized == 'responses') {
      return ProviderConfig(
        id: _makeId('OpenAI Responses'),
        enabled: true,
        name: 'OpenAI Responses',
        protocol: 'openaiCompatible',
        apiKey: '',
        baseUrl: 'https://api.openai.com/v1',
        apiPath: '/responses',
        models: const [
          ModelConfig(
            modelId: 'gpt-5-mini',
            displayName: 'GPT-5 Mini',
            capabilities: ['tools', 'reasoning'],
          ),
        ],
      );
    }
    if (normalized == 'deepseek') {
      return ProviderConfig(
        id: _makeId('DeepSeek'),
        enabled: true,
        name: 'DeepSeek',
        protocol: 'openaiCompatible',
        apiKey: '',
        baseUrl: 'https://api.deepseek.com/beta',
        apiPath: '/chat/completions',
        models: const [
          ModelConfig(
            modelId: 'deepseek-v4-flash',
            displayName: 'DeepSeek V4 Flash',
          ),
          ModelConfig(
            modelId: 'deepseek-v4-pro',
            displayName: 'DeepSeek V4 Pro',
            modelTypes: ['chat', 'completion'],
            capabilities: ['reasoning'],
          ),
        ],
      );
    }
    if (normalized == 'qwendashscope' ||
        normalized == 'dashscope' ||
        normalized == 'qwen') {
      return ProviderConfig(
        id: _makeId('Qwen DashScope'),
        enabled: true,
        name: 'Qwen DashScope',
        protocol: 'openaiCompatible',
        apiKey: '',
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        apiPath: '/chat/completions',
        models: const [
          ModelConfig(modelId: 'qwen-plus', displayName: 'Qwen Plus'),
          ModelConfig(
            modelId: 'qwen3-coder-plus',
            displayName: 'Qwen3 Coder Plus',
          ),
        ],
      );
    }
    if (normalized == 'kimi' || normalized == 'moonshot') {
      return ProviderConfig(
        id: _makeId('Kimi'),
        enabled: true,
        name: 'Kimi',
        protocol: 'openaiCompatible',
        apiKey: '',
        baseUrl: 'https://api.moonshot.cn/v1',
        apiPath: '/chat/completions',
        models: const [
          ModelConfig(modelId: 'kimi-k2-0711-preview', displayName: 'Kimi K2'),
          ModelConfig(modelId: 'moonshot-v1-8k', displayName: 'Moonshot v1 8K'),
        ],
      );
    }
    if (normalized == 'openrouter') {
      return ProviderConfig(
        id: _makeId('OpenRouter'),
        enabled: true,
        name: 'OpenRouter',
        protocol: 'openaiCompatible',
        apiKey: '',
        baseUrl: 'https://openrouter.ai/api/v1',
        apiPath: '/chat/completions',
        models: const [
          ModelConfig(
            modelId: 'openai/gpt-4.1-mini',
            displayName: 'GPT-4.1 Mini',
          ),
          ModelConfig(
            modelId: 'anthropic/claude-sonnet-4',
            displayName: 'Claude Sonnet 4',
          ),
        ],
      );
    }
    if (normalized == 'siliconflow') {
      return ProviderConfig(
        id: _makeId('SiliconFlow'),
        enabled: true,
        name: 'SiliconFlow',
        protocol: 'openaiCompatible',
        apiKey: '',
        baseUrl: 'https://api.siliconflow.cn/v1',
        apiPath: '/chat/completions',
        models: const [
          ModelConfig(
            modelId: 'Qwen/Qwen3-235B-A22B',
            displayName: 'Qwen3 235B A22B',
          ),
          ModelConfig(
            modelId: 'deepseek-ai/DeepSeek-V3',
            displayName: 'DeepSeek V3',
          ),
        ],
      );
    }
    if (normalized == 'ollama' || normalized == 'local') {
      return ProviderConfig(
        id: _makeId('Ollama'),
        enabled: true,
        name: 'Ollama',
        protocol: 'openaiCompatible',
        apiKey: 'ollama',
        baseUrl: 'http://127.0.0.1:11434/v1',
        apiPath: '/chat/completions',
        models: const [
          ModelConfig(modelId: 'qwen3:8b', displayName: 'Qwen3 8B'),
          ModelConfig(modelId: 'llama3.1:8b', displayName: 'Llama 3.1 8B'),
        ],
      );
    }
    return ProviderConfig(
      id: _makeId('OpenAI'),
      enabled: true,
      name: 'OpenAI',
      protocol: 'openaiCompatible',
      apiKey: '',
      baseUrl: 'https://api.openai.com/v1',
      apiPath: '/chat/completions',
      models: const [
        ModelConfig(modelId: 'gpt-4.1-mini', displayName: 'GPT-4.1 Mini'),
      ],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'enabled': enabled,
      'name': name,
      'protocol': protocol,
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'apiPath': apiPath,
      'models': models.map((model) => model.toJson()).toList(),
    };
  }

  ProviderConfig copyWith({
    String? id,
    bool? enabled,
    String? name,
    String? protocol,
    String? apiKey,
    String? baseUrl,
    String? apiPath,
    List<ModelConfig>? models,
  }) {
    return ProviderConfig(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      apiPath: apiPath ?? this.apiPath,
      models: models ?? this.models,
    );
  }

  static List<ModelConfig> _readModels(Object? value) {
    if (value is! List) {
      return [];
    }
    return value
        .whereType<Map>()
        .map(
          (entry) => entry.map((key, value) => MapEntry(key.toString(), value)),
        )
        .map(ModelConfig.fromJson)
        .where((model) => model.modelId.isNotEmpty)
        .toList();
  }

  static String _makeId(String name) {
    return '${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${DateTime.now().microsecondsSinceEpoch}';
  }

  static String _defaultBaseUrl(String protocol) {
    return switch (protocol) {
      'gemini' => 'https://generativelanguage.googleapis.com',
      'claude' => 'https://api.anthropic.com',
      _ => 'https://api.openai.com/v1',
    };
  }

  static String _defaultApiPath(String protocol) {
    return switch (protocol) {
      'claude' => '/v1/messages',
      'gemini' => '',
      _ => '/chat/completions',
    };
  }
}
