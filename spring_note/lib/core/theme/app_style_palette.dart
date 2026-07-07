import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 应用视觉风格调色板 — 通过 ThemeExtension 注入到 ThemeData，
/// 配合 WallpaperSettings 的 4 个透明控件参数动态换算颜色。
///
/// 与 Blue_Star_Host_Computer 的 StylePalette 不同，这里只保留 1 套基础色板，
/// 通过 brightness（亮/暗）切换两套常量，颜色迁移工作通过 BuildContext helper 完成。
@immutable
class AppStylePalette extends ThemeExtension<AppStylePalette> {
  const AppStylePalette({
    required this.brightness,
    required this.bg,
    required this.bgSecondary,
    required this.cardBg,
    required this.cardBgHover,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.transparentControls,
    required this.controlAlpha,
    required this.showBorders,
    required this.textContrast,
  });

  final Brightness brightness;

  // 背景层级
  final Color bg;
  final Color bgSecondary;

  // 卡片 / 容器
  final Color cardBg;
  final Color cardBgHover;

  // 边框
  final Color border;

  // 文字
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // 强调色
  final Color accent;

  // 透明控件模式参数（来自 WallpaperSettings）
  final bool transparentControls;
  final double controlAlpha;
  final bool showBorders;
  final double textContrast;

  // ---------- effective getters ----------
  // 把 transparentControls 4 参数换算成实际渲染颜色

  /// 控件实际背景色：启用透明控件时叠加 alpha
  Color get effectiveCardBg => transparentControls
      ? cardBg.withOpacity(controlAlpha.clamp(0.0, 1.0))
      : cardBg;

  /// 控件实际边框色：showBorders 关闭时直接透明
  Color get effectiveBorder => showBorders ? border : Colors.transparent;

  /// 控件实际 hover 背景色
  Color get effectiveCardBgHover => transparentControls
      ? cardBgHover.withOpacity(controlAlpha.clamp(0.0, 1.0))
      : cardBgHover;

  /// 文字颜色：透明控件模式下叠加对比度加深
  ///
  /// 暗色模式向白色方向加深的系数更激进（0.5），避免在深色壁纸上字
  /// 色仍偏黑；亮色模式保持 0.3 的温和加深。
  Color get effectiveTextPrimary {
    if (!transparentControls) return textPrimary;
    final contrast = textContrast.clamp(0.0, 1.0);
    if (contrast == 0) return textPrimary;
    final overlay = brightness == Brightness.dark ? Colors.white : Colors.black;
    final factor = brightness == Brightness.dark ? 0.5 : 0.3;
    return Color.lerp(textPrimary, overlay, contrast * factor) ?? textPrimary;
  }

  Color get effectiveTextSecondary => transparentControls
      ? Color.lerp(textSecondary, effectiveTextPrimary, 0.15) ?? textSecondary
      : textSecondary;

  Color get effectiveTextTertiary => transparentControls
      ? Color.lerp(textTertiary, effectiveTextPrimary, 0.1) ?? textTertiary
      : textTertiary;

  // ---------- factories ----------

  /// 亮色调色板
  factory AppStylePalette.light() => const AppStylePalette(
    brightness: Brightness.light,
    bg: AppTheme.background,
    bgSecondary: AppTheme.surfaceMuted,
    cardBg: AppTheme.surface,
    cardBgHover: Color(0xFFEEEEEE),
    border: AppTheme.border,
    textPrimary: AppTheme.text,
    textSecondary: AppTheme.textMuted,
    textTertiary: AppTheme.textSubtle,
    accent: Color(0xFF27A270),
    transparentControls: false,
    controlAlpha: 1.0,
    showBorders: true,
    textContrast: 0.0,
  );

  /// 暗色调色板
  factory AppStylePalette.dark() => const AppStylePalette(
    brightness: Brightness.dark,
    bg: AppTheme.darkBackground,
    bgSecondary: AppTheme.darkSurfaceMuted,
    cardBg: AppTheme.darkSurface,
    cardBgHover: Color(0xFF25262B),
    border: AppTheme.darkBorder,
    textPrimary: AppTheme.darkText,
    textSecondary: AppTheme.darkTextMuted,
    textTertiary: AppTheme.darkTextSubtle,
    accent: Color(0xFF27A270),
    transparentControls: false,
    controlAlpha: 1.0,
    showBorders: true,
    textContrast: 0.0,
  );

  @override
  AppStylePalette copyWith({
    Brightness? brightness,
    Color? bg,
    Color? bgSecondary,
    Color? cardBg,
    Color? cardBgHover,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    bool? transparentControls,
    double? controlAlpha,
    bool? showBorders,
    double? textContrast,
  }) {
    return AppStylePalette(
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      bgSecondary: bgSecondary ?? this.bgSecondary,
      cardBg: cardBg ?? this.cardBg,
      cardBgHover: cardBgHover ?? this.cardBgHover,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      transparentControls: transparentControls ?? this.transparentControls,
      controlAlpha: controlAlpha ?? this.controlAlpha,
      showBorders: showBorders ?? this.showBorders,
      textContrast: textContrast ?? this.textContrast,
    );
  }

  @override
  AppStylePalette lerp(ThemeExtension<AppStylePalette>? other, double t) {
    if (other is! AppStylePalette) return this;
    return AppStylePalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: Color.lerp(bg, other.bg, t) ?? bg,
      bgSecondary: Color.lerp(bgSecondary, other.bgSecondary, t) ?? bgSecondary,
      cardBg: Color.lerp(cardBg, other.cardBg, t) ?? cardBg,
      cardBgHover: Color.lerp(cardBgHover, other.cardBgHover, t) ?? cardBgHover,
      border: Color.lerp(border, other.border, t) ?? border,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textTertiary:
          Color.lerp(textTertiary, other.textTertiary, t) ?? textTertiary,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      transparentControls: t < 0.5
          ? transparentControls
          : other.transparentControls,
      controlAlpha: _lerpDouble(controlAlpha, other.controlAlpha, t),
      showBorders: t < 0.5 ? showBorders : other.showBorders,
      textContrast: _lerpDouble(textContrast, other.textContrast, t),
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
