class MemoryMessage {
  const MemoryMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.reasoningContent = '',
    this.reasoningDurationMs,
    this.toolName,
    this.toolCallId,
    this.toolCalls = const [],
    this.sources = const [],
    this.modeIds = const [],
    this.imageNames = const [],
  });

  final String role;
  final String content;
  final DateTime createdAt;
  final String reasoningContent;
  final int? reasoningDurationMs;
  final String? toolName;
  final String? toolCallId;
  final List<MemoryToolCallMessage> toolCalls;
  final List<MemorySource> sources;

  /// Ids of the composer input modes (see `memory_input_modes.dart`) that
  /// were active when this user message was sent; empty when no mode tag
  /// was used. Recorded so later requests can explain the resulting
  /// reply's format without guessing from its content.
  final List<String> modeIds;

  /// File names of images attached to this user message, relative to the
  /// `memory_images` directory under the app data directory (see
  /// `MemoryConversationService`). Kept as names instead of bytes so
  /// `remember.json` stays small.
  final List<String> imageNames;

  factory MemoryMessage.fromJson(Map<String, Object?> json) {
    return MemoryMessage(
      role: json['role']?.toString() ?? 'user',
      content: json['content']?.toString() ?? '',
      reasoningContent: json['reasoningContent']?.toString() ?? '',
      reasoningDurationMs: json['reasoningDurationMs'] is num
          ? (json['reasoningDurationMs'] as num).toInt()
          : null,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      toolName: json['toolName']?.toString(),
      toolCallId: json['toolCallId']?.toString(),
      toolCalls: _readToolCalls(json['toolCalls']),
      sources: _readSources(json['sources']),
      modeIds: json['modeIds'] is List
          ? (json['modeIds'] as List).map((id) => id.toString()).toList()
          : const [],
      imageNames: json['imageNames'] is List
          ? (json['imageNames'] as List)
                .map((name) => name.toString())
                .toList()
          : const [],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'role': role,
      'content': content,
      if (reasoningContent.isNotEmpty) 'reasoningContent': reasoningContent,
      if (reasoningDurationMs != null)
        'reasoningDurationMs': reasoningDurationMs,
      'createdAt': createdAt.toIso8601String(),
      if (toolName != null) 'toolName': toolName,
      if (toolCallId != null) 'toolCallId': toolCallId,
      if (toolCalls.isNotEmpty)
        'toolCalls': toolCalls.map((toolCall) => toolCall.toJson()).toList(),
      if (sources.isNotEmpty)
        'sources': sources.map((source) => source.toJson()).toList(),
      if (modeIds.isNotEmpty) 'modeIds': modeIds,
      if (imageNames.isNotEmpty) 'imageNames': imageNames,
    };
  }

  static List<MemoryToolCallMessage> _readToolCalls(Object? value) {
    if (value is! List) {
      return [];
    }
    return value
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .map(MemoryToolCallMessage.fromJson)
        .toList();
  }

  static List<MemorySource> _readSources(Object? value) {
    if (value is! List) {
      return [];
    }
    return value
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .map(MemorySource.fromJson)
        .toList();
  }
}

class MemoryToolCallMessage {
  const MemoryToolCallMessage({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final String arguments;

  factory MemoryToolCallMessage.fromJson(Map<String, Object?> json) {
    return MemoryToolCallMessage(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      arguments: json['arguments']?.toString() ?? '{}',
    );
  }

  Map<String, Object?> toJson() {
    return {'id': id, 'name': name, 'arguments': arguments};
  }
}

class MemorySource {
  const MemorySource({
    required this.title,
    required this.path,
    required this.snippet,
    required this.score,
    this.truncated = false,
    this.totalCharacters = 0,
  });

  final String title;
  final String path;
  final String snippet;
  final int score;
  final bool truncated;
  final int totalCharacters;

  factory MemorySource.fromJson(Map<String, Object?> json) {
    final snippet = json['snippet']?.toString() ?? '';
    return MemorySource(
      title: json['title']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      snippet: snippet,
      score: json['score'] is num ? (json['score'] as num).toInt() : 0,
      truncated: json['truncated'] as bool? ?? false,
      totalCharacters: json['totalCharacters'] is num
          ? (json['totalCharacters'] as num).toInt()
          : snippet.length,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'path': path,
      'snippet': snippet,
      'score': score,
      'truncated': truncated,
      'totalCharacters': totalCharacters,
    };
  }
}
