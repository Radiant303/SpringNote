import 'package:path/path.dart' as p;

/// 路径安全验证工具
///
/// 防止路径遍历攻击和非法路径操作
class PathValidator {
  PathValidator._();

  /// 验证路径是否在允许的目录内
  ///
  /// [path] 要验证的路径
  /// [allowedDirectory] 允许的根目录
  /// 返回 true 表示路径安全
  static bool isPathSafe(String path, String allowedDirectory) {
    try {
      // 规范化路径
      final normalizedPath = p.normalize(p.absolute(path));
      final normalizedAllowed = p.normalize(p.absolute(allowedDirectory));

      // 检查路径是否在允许的目录内
      return p.isWithin(normalizedAllowed, normalizedPath) ||
          p.equals(normalizedAllowed, normalizedPath);
    } catch (e) {
      return false;
    }
  }

  /// 验证文件扩展名是否允许
  ///
  /// [path] 文件路径
  /// [allowedExtensions] 允许的扩展名列表（不带点）
  static bool hasAllowedExtension(
    String path,
    Set<String> allowedExtensions,
  ) {
    final extension = p.extension(path).toLowerCase().replaceFirst('.', '');
    return allowedExtensions.contains(extension);
  }

  /// 清理文件名，移除危险字符
  ///
  /// [filename] 原始文件名
  /// 返回安全的文件名
  static String sanitizeFilename(String filename) {
    // 移除路径分隔符和其他危险字符
    return filename
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll('..', '_');
  }

  /// 验证路径不包含路径遍历尝试
  static bool containsPathTraversal(String path) {
    final normalized = p.normalize(path);
    return normalized.contains('..') ||
        path.contains('../') ||
        path.contains('..\\');
  }
}
