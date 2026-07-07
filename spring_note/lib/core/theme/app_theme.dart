import 'package:flutter/material.dart';

import '../services/system_font_service.dart';

class AppTheme {
  const AppTheme._();

  static const Color background = Color(0xFFFCFCFC);
  static const Color sidebar = Color(0xFFFCFCFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEDEDED);
  static const Color border = Color(0xFFE5E5E5);
  static const Color text = Color(0xFF171717);
  static const Color textMuted = Color(0xFF4F4F4F);
  static const Color textSubtle = Color(0xFF666666);

  // 暗色主题色板 —— 与亮色对称，采用低饱和度中性灰
  static const Color darkBackground = Color(0xFF121316);
  static const Color darkSidebar = Color(0xFF15171B);
  static const Color darkSurface = Color(0xFF1A1B1F);
  static const Color darkSurfaceMuted = Color(0xFF202126);
  static const Color darkBorder = Color(0xFF2A2C32);
  static const Color darkText = Color(0xFFE6E6E8);
  static const Color darkTextMuted = Color(0xFFA0A2A8);
  static const Color darkTextSubtle = Color(0xFF6B6D74);
  static const Color darkInputFill = Color(0xFF202126);

  /// 计算主题使用的 fontFamily / fontFamilyFallback。
  ///
  /// - [appFont] 为 `system` / 空字符串时，返回 null 作为 fontFamily，
  ///   由 fallback 链承担渲染。
  /// - [appFont] 为具体字体名且支持中文时，fontFamily = appFont，
  ///   仍附加平台 fallback 链以兼容缺失字符。
  /// - [appFont] 为具体字体名但不支持中文时，fontFamily = appFont，
  ///   fontFamilyFallback 强制使用中文回退链，保证中文不出现乱码或粗细不一。
  static _FontFamilyConfig _resolveFontFamily(String appFont) {
    final trimmed = appFont.trim();
    if (trimmed.isEmpty || trimmed == 'system') {
      // 系统默认：完全交给 fallback 链
      return _FontFamilyConfig(
        fontFamily: null,
        fontFamilyFallback: SystemFontService.chineseFallbackFonts(),
      );
    }
    if (SystemFontService.isChineseSupported(trimmed)) {
      return _FontFamilyConfig(
        fontFamily: trimmed,
        fontFamilyFallback: SystemFontService.chineseFallbackFonts(),
      );
    }
    // 不支持中文的字体：仍使用用户字体，但强制附加中文回退链
    return _FontFamilyConfig(
      fontFamily: trimmed,
      fontFamilyFallback: SystemFontService.chineseFallbackFonts(),
    );
  }

  static ThemeData light({String appFont = 'system'}) {
    final fontConfig = _resolveFontFamily(appFont);
    final fontFamily = fontConfig.fontFamily;
    final fontFamilyFallback = fontConfig.fontFamilyFallback;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: text,
      brightness: Brightness.light,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        primary: text,
        secondary: textMuted,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      focusColor: Colors.transparent,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: text,
          fontSize: 32,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        headlineMedium: TextStyle(
          color: text,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          color: text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          height: 1.35,
        ),
        titleMedium: TextStyle(
          color: text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        bodyLarge: TextStyle(
          color: text,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.7,
        ),
        bodyMedium: TextStyle(
          color: textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.55,
        ),
        labelLarge: TextStyle(
          color: text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ).apply(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback),
      iconTheme: const IconThemeData(color: textMuted, size: 20),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        hintStyle: const TextStyle(color: textSubtle),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCFCFCF)),
        ),
      ),
    );
  }

  static double fontScaleFactor(double fontScale) {
    final safeScale = fontScale.isFinite ? fontScale : 100;
    return safeScale.clamp(80, 140).toDouble() / 100;
  }

  static ThemeData dark({String appFont = 'system'}) {
    final fontConfig = _resolveFontFamily(appFont);
    final fontFamily = fontConfig.fontFamily;
    final fontFamilyFallback = fontConfig.fontFamilyFallback;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: darkText,
      brightness: Brightness.dark,
      surface: darkSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme.copyWith(
        primary: darkText,
        secondary: darkTextMuted,
        surface: darkSurface,
      ),
      scaffoldBackgroundColor: darkBackground,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      focusColor: Colors.transparent,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: darkText,
          fontSize: 32,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        headlineMedium: TextStyle(
          color: darkText,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          color: darkText,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          height: 1.35,
        ),
        titleMedium: TextStyle(
          color: darkText,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        bodyLarge: TextStyle(
          color: darkText,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.7,
        ),
        bodyMedium: TextStyle(
          color: darkTextMuted,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.55,
        ),
        labelLarge: TextStyle(
          color: darkText,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ).apply(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback),
      iconTheme: const IconThemeData(color: darkTextMuted, size: 20),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkInputFill,
        hintStyle: const TextStyle(color: darkTextSubtle),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF45464C)),
        ),
      ),
    );
  }
}

class _FontFamilyConfig {
  const _FontFamilyConfig({
    required this.fontFamily,
    required this.fontFamilyFallback,
  });

  final String? fontFamily;
  final List<String> fontFamilyFallback;
}
