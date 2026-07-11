import 'structured_work_note.dart';

class StructuredNoteSectionConfig {
  const StructuredNoteSectionConfig({
    required this.id,
    required this.title,
    required this.aiInstruction,
  });

  final String id;
  final String title;
  final String aiInstruction;

  Map<String, Object?> toJson() {
    return {'id': id, 'title': title, 'aiInstruction': aiInstruction};
  }

  StructuredNoteSectionConfig copyWith({String? title, String? aiInstruction}) {
    return StructuredNoteSectionConfig(
      id: id,
      title: title ?? this.title,
      aiInstruction: aiInstruction ?? this.aiInstruction,
    );
  }

  static List<StructuredNoteSectionConfig> fromJson(Object? value) {
    if (value is! List) {
      return defaults;
    }
    final byId = <String, Map>{};
    for (final item in value.whereType<Map>()) {
      final id = item['id'];
      if (id is String) {
        byId[id] = item;
      }
    }
    return [
      for (final fallback in defaults) _fromMap(byId[fallback.id], fallback),
    ];
  }

  static List<StructuredNoteSectionConfig> normalize(
    Iterable<StructuredNoteSectionConfig> sections,
  ) {
    final byId = {for (final section in sections) section.id: section};
    return [
      for (final fallback in defaults) _normalized(byId[fallback.id], fallback),
    ];
  }

  static StructuredNoteSectionConfig _fromMap(
    Map? value,
    StructuredNoteSectionConfig fallback,
  ) {
    return StructuredNoteSectionConfig(
      id: fallback.id,
      title: _nonEmptyString(value?['title'], fallback.title),
      aiInstruction: _nonEmptyString(
        value?['aiInstruction'],
        fallback.aiInstruction,
      ),
    );
  }

  static StructuredNoteSectionConfig _normalized(
    StructuredNoteSectionConfig? value,
    StructuredNoteSectionConfig fallback,
  ) {
    return StructuredNoteSectionConfig(
      id: fallback.id,
      title: _nonEmptyString(value?.title, fallback.title),
      aiInstruction: _nonEmptyString(
        value?.aiInstruction,
        fallback.aiInstruction,
      ),
    );
  }

  static String _nonEmptyString(Object? value, String fallback) {
    if (value is! String) {
      return fallback;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  static const defaults = [
    StructuredNoteSectionConfig(
      id: StructuredNoteSectionIds.a,
      title: '完成事项',
      aiInstruction: '提取已经完成或取得明确进展的工作。',
    ),
    StructuredNoteSectionConfig(
      id: StructuredNoteSectionIds.b,
      title: '问题记录',
      aiInstruction: '提取遇到的问题、报错、阻塞事项或风险。',
    ),
    StructuredNoteSectionConfig(
      id: StructuredNoteSectionIds.c,
      title: '明日计划',
      aiInstruction: '提取后续计划、下一步行动、待办或准备事项。',
    ),
  ];
}
