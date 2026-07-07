import 'package:flutter/material.dart';

/// 壁纸模式
enum WallpaperMode {
  /// 跟随应用主题的默认纯色背景。
  defaultBg,

  /// 用户自定义本地图片
  image,

  /// 纯色背景（极简模式）
  solid,
}

/// 图片填充模式 — 控制图片如何适配窗口尺寸
enum WallpaperFillMode {
  /// 铺满拉伸：图片填满窗口，不保持比例（可变形）
  stretch,

  /// 等比覆盖：等比缩放铺满窗口，裁剪超出部分（推荐）
  cover,

  /// 居中原图：保持原图尺寸居中显示，空白处填底色
  contain,
}

/// 壁纸配置数据模型 — 持久化到 config.json
@immutable
class WallpaperSettings {
  const WallpaperSettings({
    required this.mode,
    this.imagePath,
    required this.fillMode,
    required this.opacity,
    required this.blur,
    required this.maskOpacity,
    required this.solidColorArgb,
    this.transparentControls = false,
    this.controlAlpha = 1.0,
    this.showBorders = true,
    this.textContrast = 0.0,
  });

  /// 默认配置：使用应用默认背景，不透明控件，不模糊，无蒙版
  static const WallpaperSettings defaults = WallpaperSettings(
    mode: WallpaperMode.defaultBg,
    imagePath: null,
    fillMode: WallpaperFillMode.cover,
    opacity: 1.0,
    blur: 0.0,
    maskOpacity: 0.0,
    solidColorArgb: 0xFFFFFFFF,
  );

  final WallpaperMode mode;

  /// 用户图片的相对路径（位于 app 数据目录/wallpapers/ 下）
  final String? imagePath;

  final WallpaperFillMode fillMode;

  /// 0.0 ~ 1.0；越高背景越淡
  final double opacity;

  /// 0.0 ~ 25.0；高斯模糊 sigma 值
  final double blur;

  /// 0.0 ~ 1.0；半透淡绿色蒙版的浓度
  final double maskOpacity;

  /// 纯色模式的 ARGB 整数值
  final int solidColorArgb;

  /// 是否启用透明控件模式（配合壁纸使用，让卡片/侧边栏通透展示底层壁纸）
  final bool transparentControls;

  /// 控件透明度 0.0~1.0；越高控件越透明，壁纸显露越完整
  final double controlAlpha;

  /// 卡片/容器细描边开关（关闭后极致通透，仅留文字悬浮在壁纸上）
  final bool showBorders;

  /// 文字颜色加深 0.0~1.0；在花哨壁纸场景下提升文字可读性
  final double textContrast;

  WallpaperSettings copyWith({
    WallpaperMode? mode,
    String? imagePath,
    bool clearImagePath = false,
    WallpaperFillMode? fillMode,
    double? opacity,
    double? blur,
    double? maskOpacity,
    int? solidColorArgb,
    bool? transparentControls,
    double? controlAlpha,
    bool? showBorders,
    double? textContrast,
  }) {
    return WallpaperSettings(
      mode: mode ?? this.mode,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      fillMode: fillMode ?? this.fillMode,
      opacity: opacity ?? this.opacity,
      blur: blur ?? this.blur,
      maskOpacity: maskOpacity ?? this.maskOpacity,
      solidColorArgb: solidColorArgb ?? this.solidColorArgb,
      transparentControls: transparentControls ?? this.transparentControls,
      controlAlpha: controlAlpha ?? this.controlAlpha,
      showBorders: showBorders ?? this.showBorders,
      textContrast: textContrast ?? this.textContrast,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'imagePath': imagePath,
      'fillMode': fillMode.name,
      'opacity': opacity,
      'blur': blur,
      'maskOpacity': maskOpacity,
      'solidColorArgb': solidColorArgb,
      'transparentControls': transparentControls,
      'controlAlpha': controlAlpha,
      'showBorders': showBorders,
      'textContrast': textContrast,
    };
  }

  factory WallpaperSettings.fromJson(Map<String, dynamic> json) {
    final modeStr = json['mode'] as String?;
    final fillStr = json['fillMode'] as String?;
    return WallpaperSettings(
      mode: WallpaperMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => WallpaperMode.defaultBg,
      ),
      imagePath: json['imagePath'] as String?,
      fillMode: WallpaperFillMode.values.firstWhere(
        (f) => f.name == fillStr,
        orElse: () => WallpaperFillMode.cover,
      ),
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      blur: (json['blur'] as num?)?.toDouble() ?? 0.0,
      maskOpacity: (json['maskOpacity'] as num?)?.toDouble() ?? 0.0,
      solidColorArgb: (json['solidColorArgb'] as int?) ?? 0xFFFFFFFF,
      transparentControls: json['transparentControls'] as bool? ?? false,
      controlAlpha: (json['controlAlpha'] as num?)?.toDouble() ?? 1.0,
      showBorders: json['showBorders'] as bool? ?? true,
      textContrast: (json['textContrast'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WallpaperSettings &&
        other.mode == mode &&
        other.imagePath == imagePath &&
        other.fillMode == fillMode &&
        other.opacity == opacity &&
        other.blur == blur &&
        other.maskOpacity == maskOpacity &&
        other.solidColorArgb == solidColorArgb &&
        other.transparentControls == transparentControls &&
        other.controlAlpha == controlAlpha &&
        other.showBorders == showBorders &&
        other.textContrast == textContrast;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    imagePath,
    fillMode,
    opacity,
    blur,
    maskOpacity,
    solidColorArgb,
    transparentControls,
    controlAlpha,
    showBorders,
    textContrast,
  );
}
