import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/wallpaper_settings.dart';
import '../services/wallpaper_service.dart';
import '../theme/app_theme.dart';

/// 全局壁纸渲染层 —— 固定在所有页面控件的最底层。
///
/// 渲染顺序（自底向上）：
///   1. 内容源（默认主题背景 / 用户图片 / 纯色）
///   2. 内容透明度
///   3. 高斯模糊（可选）
///   4. 蒙版（可选，淡色遮罩，颜色跟随当前主题背景）
///
/// 与 Blue_Star_Host_Computer 的 WallpaperLayer 不同：
/// - 不依赖 `provider` 包，直接通过构造函数注入 `settings` + `dataDirectory`
/// - 颜色沿用项目现有的 [SpringThemeColors]，不单独维护另一套色板
class WallpaperLayer extends StatelessWidget {
  const WallpaperLayer({
    super.key,
    required this.settings,
    required this.dataDirectory,
  });

  final WallpaperSettings settings;
  final String dataDirectory;

  @override
  Widget build(BuildContext context) {
    final source = _buildSource(context);

    // 内容层：透明度 + 模糊统一作用于源
    Widget content = Opacity(opacity: settings.opacity, child: source);
    if (settings.blur > 0) {
      content = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: settings.blur,
          sigmaY: settings.blur,
        ),
        child: content,
      );
    }

    final children = <Widget>[content];

    // 蒙版层：当前主题背景色遮罩，平衡氛围感与可读性
    if (settings.maskOpacity > 0) {
      final colors = AppTheme.colors(context);
      children.add(
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: colors.background.withValues(
                alpha: settings.maskOpacity.clamp(0.0, 1.0).toDouble(),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(fit: StackFit.expand, children: children);
  }

  Widget _buildSource(BuildContext context) {
    switch (settings.mode) {
      case WallpaperMode.defaultBg:
        return const DefaultWallpaper();
      case WallpaperMode.image:
        final abs = WallpaperService.resolveAbsolutePath(
          settings: settings,
          dataDirectory: dataDirectory,
        );
        if (abs == null) {
          // 图片路径缺失（如首次启动且未触发复制） → 回退默认
          return const DefaultWallpaper();
        }
        return Image.file(
          File(abs),
          fit: WallpaperService.toBoxFit(settings.fillMode),
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const DefaultWallpaper(),
        );
      case WallpaperMode.solid:
        return Container(color: Color(settings.solidColorArgb));
    }
  }
}

/// 应用默认背景：浅色下为纯白，深色下沿用既有深色调色。
class DefaultWallpaper extends StatelessWidget {
  const DefaultWallpaper({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(color: isDark ? colors.background : Colors.white);
  }
}
