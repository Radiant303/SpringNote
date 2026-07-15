import '../models/note_file.dart';

/// 笔记服务接口
///
/// 定义笔记服务的抽象行为，便于测试和扩展
abstract interface class INoteService {
  /// 列出指定目录下的所有 Markdown 文件
  Future<List<NoteFile>> listMarkdownFiles({
    required String directoryPath,
    required NoteKind kind,
  });

  /// 确保当前日期/周期的 Markdown 文件存在
  Future<NoteFile> ensureCurrentMarkdownFile({
    required String directoryPath,
    required NoteKind kind,
    DateTime? now,
  });

  /// 读取 Markdown 文件内容
  Future<String> readMarkdown(String path);

  /// 写入 Markdown 文件内容
  Future<void> writeMarkdown(String path, String content);

  /// 刷新 Markdown 索引
  Future<bool> refreshMarkdownIndex({
    required String directoryPath,
    required NoteKind kind,
  });

  /// 索引单个 Markdown 文件
  Future<void> indexMarkdownFile({
    required String directoryPath,
    required NoteKind kind,
    required String notePath,
  });

  /// 根据内容描述 Markdown 文件元数据
  NoteFile describeMarkdown({
    required NoteFile note,
    required String content,
    DateTime? modifiedAt,
  });

  /// 搜索 Markdown 文件
  Future<List<NoteFile>> searchMarkdownFiles({
    required String directoryPath,
    required NoteKind kind,
    required String query,
  });

  /// 确保 Markdown 文件存在
  Future<void> ensureMarkdownFile(
    String path, {
    String defaultContent = '',
  });
}
