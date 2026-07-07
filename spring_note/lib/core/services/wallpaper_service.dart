import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/wallpaper_settings.dart';
import 'image_file_types.dart';

/// 壁纸相关静态工具方法。
///
/// 与 Blue_Star_Host_Computer 的 `WallpaperProvider`（继承 ChangeNotifier、
/// 通过 SharedPreferences 持久化）不同，SpringNote 已经统一用
/// `LocalDataService` + `config.json` 做持久化，这里只用静态方法完成
/// 文件 IO + 路径解析等与平台交互的部分；业务变更通过
/// `config.copyWith(wallpaperSettings: ...)` + `LocalDataService.saveConfig`
/// 这条链路驱动。
class WallpaperService {
  WallpaperService._();

  static const String _wallpaperSubdir = 'wallpapers';

  /// Windows / macOS 默认不区分路径大小写，保留时按小写比较。
  static bool get _isCaseInsensitiveFs =>
      Platform.isWindows || Platform.isMacOS;

  // ---------------- 路径解析 ----------------

  /// 用户自定义图片所在子目录（绝对路径）。
  ///
  /// 约定位置：`{dataDirectory}/wallpapers/`。
  /// 返回路径**不保证**目录已存在，需要时调用方自行 `create(recursive: true)`。
  static String wallpaperDirectory(String dataDirectory) {
    return p.join(dataDirectory, _wallpaperSubdir);
  }

  /// 把 [WallpaperSettings.imagePath]（相对路径）解析为绝对路径。
  /// - imagePath 为 null / 空 → 返回 null
  /// - imagePath 已经是绝对路径 → 原样返回（兼容老数据）
  static String? resolveAbsolutePath({
    required WallpaperSettings settings,
    required String dataDirectory,
  }) {
    final rel = settings.imagePath;
    if (rel == null || rel.isEmpty) return null;
    if (p.isAbsolute(rel)) return rel;
    return p.join(dataDirectory, rel);
  }

  // ---------------- 启动校验 ----------------

  /// 校验 [WallpaperSettings.imagePath] 是否仍指向有效文件。
  /// - mode != image 或 imagePath 为空 → 原样返回
  /// - 文件不存在 → 回退到 [WallpaperSettings.defaults]
  /// - 存在但模式不对 → 不主动改 mode，避免误操作
  static Future<WallpaperSettings> validateOnLoad({
    required WallpaperSettings settings,
    required String dataDirectory,
  }) async {
    if (settings.mode != WallpaperMode.image) return settings;
    final rel = settings.imagePath;
    if (rel == null || rel.isEmpty) {
      return WallpaperSettings.defaults;
    }
    final abs = resolveAbsolutePath(
      settings: settings,
      dataDirectory: dataDirectory,
    );
    if (abs == null) return WallpaperSettings.defaults;
    final exists = await File(abs).exists();
    if (!exists) {
      debugPrint('[WallpaperService] 自定义图片不存在，回退默认背景: $abs');
      return WallpaperSettings.defaults;
    }
    return settings;
  }

  // ---------------- 选图 → 复制到应用数据目录 ----------------

  /// 把用户从文件选择器选中的 [sourceFile] 复制到
  /// `{dataDirectory}/wallpapers/wallpaper_<ts>.<ext>`，并返回更新后的
  /// [WallpaperSettings]。
  ///
  /// 行为：
  /// 1. 自动创建 wallpapers 子目录
  /// 2. 仅复制允许的图片格式（见 [allowedImageExtensions]），
  ///    其他格式直接抛 [ArgumentError]
  /// 3. 清理旧 wallpaper_* 文件，仅保留最新一张及 [alsoKeepPath] 指定的文件
  /// 4. 设置 mode = image，imagePath 存**相对** dataDirectory 的路径
  static Future<WallpaperSettings> adoptImage({
    required File sourceFile,
    required WallpaperSettings current,
    required String dataDirectory,
    String? alsoKeepPath,
  }) async {
    final extRaw = p.extension(sourceFile.path);
    // 先检查原始扩展名是否允许，再规范化（避免 fallback 绕过检查）
    if (!hasAllowedImageExtension(sourceFile.path)) {
      throw ArgumentError('不支持的图片格式: $extRaw');
    }
    final ext = normalizedImageExtension(extRaw, fallback: 'jpg');
    if (!await sourceFile.exists()) {
      throw FileSystemException('源图片不存在', sourceFile.path);
    }

    final dir = Directory(wallpaperDirectory(dataDirectory));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final filename = 'wallpaper_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final destPath = p.join(dir.path, filename);
    await sourceFile.copy(destPath);

    final keepPaths = <String>{destPath};
    if (alsoKeepPath != null && alsoKeepPath.isNotEmpty) {
      keepPaths.add(alsoKeepPath);
    }
    await _pruneOldWallpapers(dir, keepPaths: keepPaths);

    final relativePath = p.relative(destPath, from: dataDirectory);
    return current.copyWith(mode: WallpaperMode.image, imagePath: relativePath);
  }

  /// 清理 wallpapers 目录中除 [keepPaths] 之外的所有 `wallpaper_*` 文件。
  static Future<void> _pruneOldWallpapers(
    Directory dir, {
    required Set<String> keepPaths,
  }) async {
    try {
      // Windows / macOS 文件系统默认大小写不敏感，归一为小写避免
      // “c:\...\Wallpaper_X.JPG” 和“c:\...\wallpaper_x.jpg”被误判
      // 为两个不同文件导致合法文件被误删。
      final keepSet = _isCaseInsensitiveFs
          ? keepPaths.map((path) => path.toLowerCase()).toSet()
          : keepPaths;
      await for (final entity in dir.list()) {
        if (entity is File) {
          final cmp = _isCaseInsensitiveFs
              ? entity.path.toLowerCase()
              : entity.path;
          if (!keepSet.contains(cmp)) {
            final name = p.basename(entity.path);
            if (name.startsWith('wallpaper_')) {
              try {
                await entity.delete();
              } catch (e) {
                debugPrint('[WallpaperService] 删除旧壁纸失败: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[WallpaperService] 清理旧壁纸目录失败: $e');
    }
  }

  // ---------------- Color <-> ARGB 互转 ----------------

  /// 从 [Color] 取出 ARGB 整数值（兼容所有 Flutter SDK 版本）。
  static int colorToArgb(Color c) {
    return ((c.alpha & 0xff) << 24) |
        ((c.red & 0xff) << 16) |
        ((c.green & 0xff) << 8) |
        (c.blue & 0xff);
  }

  /// 从 ARGB 整数还原为 [Color]。
  static Color argbToColor(int argb) => Color(argb);

  // ---------------- 填充模式映射 ----------------

  /// [WallpaperFillMode] → Flutter [BoxFit]。
  static BoxFit toBoxFit(WallpaperFillMode mode) {
    switch (mode) {
      case WallpaperFillMode.stretch:
        return BoxFit.fill;
      case WallpaperFillMode.cover:
        return BoxFit.cover;
      case WallpaperFillMode.contain:
        return BoxFit.contain;
    }
  }

  // ---------------- 一键清除 ----------------

  /// 关闭图片模式回到默认背景，同时删除磁盘上的 wallpaper_*.jpg/png 等文件。
  /// 调用方需自行 saveConfig 后再触发 UI 刷新。
  static Future<void> clearImageFiles(String dataDirectory) async {
    final dir = Directory(wallpaperDirectory(dataDirectory));
    if (!await dir.exists()) return;
    try {
      await for (final entity in dir.list()) {
        if (entity is File &&
            p.basename(entity.path).startsWith('wallpaper_')) {
          try {
            await entity.delete();
          } catch (e) {
            debugPrint('[WallpaperService] 删除壁纸失败: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[WallpaperService] 清空壁纸目录失败: $e');
    }
  }
}
