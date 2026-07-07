import 'package:flutter/material.dart';

/// 桌面组件壁纸模式
enum DesktopWidgetWallpaperMode {
  /// 默认白色背景（兼容现有行为）
  defaultWhite,

  /// 用户自选纯色
  solid,

  /// 用户自选本地图片
  image,
}

/// 桌面组件独立壁纸配置 —— 与主窗口 WallpaperSettings 互不影响。
///
/// 持久化到 config.json 的 `desktopWidgetWallpaperSettings` 字段。
@immutable
class DesktopWidgetWallpaperSettings {
  const DesktopWidgetWallpaperSettings({
    required this.mode,
    required this.solidColorArgb,
    this.imagePath,
    required this.opacity,
  });

  /// 默认配置：白色背景，不透明
  static const DesktopWidgetWallpaperSettings defaults =
      DesktopWidgetWallpaperSettings(
        mode: DesktopWidgetWallpaperMode.defaultWhite,
        solidColorArgb: 0xFFFFFFFF,
        imagePath: null,
        opacity: 1.0,
      );

  final DesktopWidgetWallpaperMode mode;

  /// 纯色模式的 ARGB 整数值
  final int solidColorArgb;

  /// 图片模式的相对路径（位于 app 数据目录/wallpapers/ 下）
  final String? imagePath;

  /// 壁纸不透明度 0.0 ~ 1.0
  final double opacity;

  /// 拷贝当前配置并按需覆盖字段。
  ///
  /// 调用规则：
  /// - 不要传 [imagePath]（使用默认）→ 保留原值
  /// - 传 [imagePath] 任意非空值 → 覆盖为该值
  /// - 需要把 [imagePath] 重置为 null（例如切回非 image 模式）→
  ///   传 [clearImagePath]: true
  ///
  /// 注意：Dart 默认参数不能严格区分“不传”与“传 null”，所以清空
  /// 必须使用专门的 [clearImagePath] 开关，不要传 `imagePath: null`。
  DesktopWidgetWallpaperSettings copyWith({
    DesktopWidgetWallpaperMode? mode,
    int? solidColorArgb,
    String? imagePath,
    bool clearImagePath = false,
    double? opacity,
  }) {
    return DesktopWidgetWallpaperSettings(
      mode: mode ?? this.mode,
      solidColorArgb: solidColorArgb ?? this.solidColorArgb,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      opacity: opacity ?? this.opacity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'solidColorArgb': solidColorArgb,
      'imagePath': imagePath,
      'opacity': opacity,
    };
  }

  factory DesktopWidgetWallpaperSettings.fromJson(Map<String, dynamic> json) {
    final modeStr = json['mode'] as String?;
    return DesktopWidgetWallpaperSettings(
      mode: DesktopWidgetWallpaperMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => DesktopWidgetWallpaperMode.defaultWhite,
      ),
      solidColorArgb: (json['solidColorArgb'] as int?) ?? 0xFFFFFFFF,
      imagePath: json['imagePath'] as String?,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DesktopWidgetWallpaperSettings &&
        other.mode == mode &&
        other.solidColorArgb == solidColorArgb &&
        other.imagePath == imagePath &&
        other.opacity == opacity;
  }

  @override
  int get hashCode => Object.hash(mode, solidColorArgb, imagePath, opacity);
}
