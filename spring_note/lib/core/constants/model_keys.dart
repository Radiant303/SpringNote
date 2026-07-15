/// 模型配置键常量
///
/// 统一管理所有模型配置的键名，避免字符串散落在代码中
class ModelKeys {
  ModelKeys._();

  /// 智能生成模型（用于日报生成、结构化笔记等）
  static const String intelligentGeneration = 'intelligentGenerationModel';

  /// 回忆书模型（用于历史记录检索和对话）
  static const String memoryBook = 'memoryBookModel';

  /// 编辑补全模型（用于 Markdown 编辑时的 AI 补全）
  static const String editCompletion = 'editCompletionModel';

  /// 所有支持的模型键列表
  static const List<String> allKeys = [
    intelligentGeneration,
    memoryBook,
    editCompletion,
  ];
}
