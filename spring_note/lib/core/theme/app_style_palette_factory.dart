import 'package:flutter/material.dart';

import '../models/app_config.dart';
import '../models/wallpaper_settings.dart';
import 'app_style_palette.dart';

/// 从 [AppConfig] + 当前实际亮度构建 [AppStylePalette]。
///
/// MaterialApp.builder 里调用，每次 config 变更或系统主题变更时重建。
class AppStylePaletteFactory {
  AppStylePaletteFactory._();

  /// 根据 [AppConfig.appThemeMode] 解析实际要使用的亮度。
  /// - ThemeMode.light / dark 直接返回对应亮度
  /// - ThemeMode.system 跟随 [MediaQuery.platformBrightness]
  static Brightness resolveBrightness(
    ThemeMode mode, {
    Brightness? platformBrightness,
  }) {
    switch (mode) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.system:
        return platformBrightness ?? Brightness.light;
    }
  }

  /// 给定 [AppConfig] + 当前 [Brightness]，组合出最终调色板：
  /// 1. 基础色板（亮 / 暗）来自 [AppStylePalette.light]/[dark]
  /// 2. 4 个透明控件参数（transparentControls / controlAlpha /
  ///    showBorders / textContrast）从 [WallpaperSettings] 复制
  static AppStylePalette fromConfig(
    AppConfig config, {
    Brightness? platformBrightness,
  }) {
    final brightness = resolveBrightness(
      config.appThemeMode,
      platformBrightness: platformBrightness,
    );
    final base = brightness == Brightness.dark
        ? AppStylePalette.dark()
        : AppStylePalette.light();

    final wallpaper = config.wallpaperSettings;
    return base.copyWith(
      brightness: brightness,
      transparentControls: wallpaper.transparentControls,
      controlAlpha: wallpaper.controlAlpha,
      showBorders: wallpaper.showBorders,
      textContrast: wallpaper.textContrast,
    );
  }
}
