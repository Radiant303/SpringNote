import 'package:flutter/material.dart';

import 'app_style_palette.dart';

/// BuildContext 上的样式快速访问扩展。
///
/// 业务页面统一通过 `context.appCardBg` / `context.appTextPrimary` 等
/// 取得经过亮度 + 透明控件 + 描边参数换算后的颜色，避免散落调用
/// `Theme.of(context).colorScheme.xxx`。
///
/// 旧的 `AppTheme.background` 等静态常量**保留**作为 ThemeData 默认值来源；
/// UI 渲染处全部走这里。
extension AppStyleContext on BuildContext {
  /// 当前主题注入的调色板（必非空，MaterialApp builder 阶段会注入）。
  AppStylePalette get appPalette =>
      Theme.of(this).extension<AppStylePalette>()!;

  /// 渲染层主背景（默认跟随 scaffold，实际是被 wallpaperLayer 覆盖之前的占位）
  Color get appBg => appPalette.bg;

  /// 二级背景（侧边栏、卡片背后）
  Color get appBgSecondary => appPalette.bgSecondary;

  /// 卡片 / 容器实际背景色（受 transparentControls + controlAlpha 影响）
  Color get appCardBg => appPalette.effectiveCardBg;

  /// 卡片 hover 实际背景色
  Color get appCardBgHover => appPalette.effectiveCardBgHover;

  /// 边框实际颜色（受 showBorders 影响）
  Color get appBorder => appPalette.effectiveBorder;

  /// 主文字颜色（受 textContrast 影响）
  Color get appTextPrimary => appPalette.effectiveTextPrimary;

  /// 次文字颜色
  Color get appTextSecondary => appPalette.effectiveTextSecondary;

  /// 三级 / 提示文字颜色
  Color get appTextTertiary => appPalette.effectiveTextTertiary;

  /// 强调色（按钮、链接、激活态）
  Color get appAccent => appPalette.accent;

  /// 当前亮度（亮 / 暗），用于需要分支判断的场景
  Brightness get appBrightness => appPalette.brightness;

  /// 当前是否处于深色主题
  bool get appIsDark => appPalette.brightness == Brightness.dark;
}
