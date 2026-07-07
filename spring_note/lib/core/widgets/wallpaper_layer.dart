import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/wallpaper_settings.dart';
import '../services/wallpaper_service.dart';
import '../theme/context_extensions.dart';

/// 全局壁纸渲染层 —— 固定在所有页面控件的最底层。
///
/// 渲染顺序（自底向上）：
///   1. 内容源（程序化默认背景 / 用户图片 / 纯色）
///   2. 内容透明度
///   3. 高斯模糊（可选）
///   4. 蒙版（可选，淡色遮罩，颜色跟随当前主题背景）
///
/// 与 Blue_Star_Host_Computer 的 WallpaperLayer 不同：
/// - 不依赖 `provider` 包，直接通过构造函数注入 `settings` + `dataDirectory`
/// - 颜色通过 `context.appPalette` 获取（避免硬编码）
/// - 暗色主题下隐藏绿叶装饰，仅保留基础渐变
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
      children.add(
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: context.appBg.withOpacity(
                settings.maskOpacity.clamp(0.0, 1.0),
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
        return DefaultGreenWallpaper(showLeaves: !context.appIsDark);
      case WallpaperMode.image:
        final abs = WallpaperService.resolveAbsolutePath(
          settings: settings,
          dataDirectory: dataDirectory,
        );
        if (abs == null) {
          // 图片路径缺失（如首次启动且未触发复制） → 回退默认
          return DefaultGreenWallpaper(showLeaves: !context.appIsDark);
        }
        return Image.file(
          File(abs),
          fit: WallpaperService.toBoxFit(settings.fillMode),
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              DefaultGreenWallpaper(showLeaves: !context.appIsDark),
        );
      case WallpaperMode.solid:
        return Container(color: Color(settings.solidColorArgb));
    }
  }
}

/// 程序内置默认绿叶清新背景。
///
/// 使用 CustomPainter 绘制：
///   1. 主题背景色径向渐变（中心偏上，提亮整体氛围）
///   2. 暗色模式下隐藏叶形（避免突兀）
///   3. 顶部 / 底部柔和光晕
///
/// 完全无外部资源依赖，启动即可显示。
class DefaultGreenWallpaper extends StatelessWidget {
  const DefaultGreenWallpaper({super.key, this.showLeaves = true});

  /// 是否绘制绿叶装饰；暗色主题下传 false 仅保留基础渐变 + 光晕。
  final bool showLeaves;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _DefaultGreenWallpaperPainter(
          bg: palette.bg,
          bgSecondary: palette.bgSecondary,
          accent: palette.accent,
          isDark: palette.brightness == Brightness.dark,
          showLeaves: showLeaves,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DefaultGreenWallpaperPainter extends CustomPainter {
  _DefaultGreenWallpaperPainter({
    required this.bg,
    required this.bgSecondary,
    required this.accent,
    required this.isDark,
    required this.showLeaves,
  });

  final Color bg;
  final Color bgSecondary;
  final Color accent;
  final bool isDark;
  final bool showLeaves;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. 基础渐变：中心亮，四周柔和
    final baseGradient = RadialGradient(
      center: const Alignment(0, -0.3),
      radius: 1.4,
      colors: [
        bg,
        bgSecondary,
        Color.lerp(bgSecondary, accent, 0.10) ?? bgSecondary,
      ],
      stops: const [0.0, 0.55, 1.0],
    );
    final basePaint = Paint()..shader = baseGradient.createShader(rect);
    canvas.drawRect(rect, basePaint);

    // 2. 左上角柔和光晕（暗色下强度降低）
    final topLeftGlow = RadialGradient(
      center: const Alignment(-0.4, -0.5),
      radius: 0.9,
      colors: [
        accent.withOpacity(isDark ? 0.10 : 0.18),
        accent.withOpacity(0.0),
      ],
    );
    final glowPaint = Paint()
      ..shader = topLeftGlow.createShader(rect)
      ..blendMode = isDark ? BlendMode.srcOver : BlendMode.plus;
    canvas.drawRect(rect, glowPaint);

    // 3. 右下角柔和光晕
    final bottomRightGlow = RadialGradient(
      center: const Alignment(0.7, 0.8),
      radius: 0.8,
      colors: [
        accent.withOpacity(isDark ? 0.08 : 0.18),
        accent.withOpacity(0.0),
      ],
    );
    final glow2Paint = Paint()..shader = bottomRightGlow.createShader(rect);
    canvas.drawRect(rect, glow2Paint);

    if (!showLeaves) return;

    // 4. 半透白色叶形点缀（仅亮色模式）
    final leafPaint = Paint()
      ..color = Colors.white.withOpacity(0.22)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final leafStroke = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    final leaves = <_LeafSpec>[
      _LeafSpec(size.width * 0.15, size.height * 0.18, 60, 0.4),
      _LeafSpec(size.width * 0.78, size.height * 0.10, 80, -0.5),
      _LeafSpec(size.width * 0.30, size.height * 0.72, 50, 0.2),
      _LeafSpec(size.width * 0.85, size.height * 0.65, 70, -0.3),
      _LeafSpec(size.width * 0.55, size.height * 0.45, 90, 0.6),
      _LeafSpec(size.width * 0.10, size.height * 0.50, 45, -0.7),
    ];

    for (final leaf in leaves) {
      canvas.save();
      canvas.translate(leaf.cx, leaf.cy);
      canvas.rotate(leaf.rotation);
      _drawLeafShape(
        canvas,
        Size(leaf.size, leaf.size * 1.6),
        leafPaint,
        leafStroke,
      );
      canvas.restore();
    }
  }

  void _drawLeafShape(Canvas canvas, Size size, Paint fill, Paint stroke) {
    final path = Path();
    final w = size.width;
    final h = size.height;
    path.moveTo(0, -h / 2);
    path.cubicTo(w / 2, -h / 2, w / 2, h / 4, 0, h / 2);
    path.cubicTo(-w / 2, h / 4, -w / 2, -h / 2, 0, -h / 2);
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    // 叶脉
    final veinPaint = Paint()
      ..color = Colors.white.withOpacity(0.30)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, -h / 2.2), Offset(0, h / 2.2), veinPaint);
  }

  @override
  bool shouldRepaint(covariant _DefaultGreenWallpaperPainter old) {
    return old.bg != bg ||
        old.bgSecondary != bgSecondary ||
        old.accent != accent ||
        old.isDark != isDark ||
        old.showLeaves != showLeaves;
  }
}

class _LeafSpec {
  const _LeafSpec(this.cx, this.cy, this.size, this.rotation);
  final double cx;
  final double cy;
  final double size;
  final double rotation;
}
