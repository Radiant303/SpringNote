import 'package:flutter/material.dart';

class SpringThemeColors extends ThemeExtension<SpringThemeColors> {
  const SpringThemeColors({
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceHover,
    required this.surfacePressed,
    required this.border,
    required this.divider,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.onAccent,
    required this.inputFill,
    required this.inputFocusedFill,
    required this.shadow,
  });

  final Color background;
  final Color sidebar;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceHover;
  final Color surfacePressed;
  final Color border;
  final Color divider;
  final Color text;
  final Color textMuted;
  final Color textSubtle;
  final Color onAccent;
  final Color inputFill;
  final Color inputFocusedFill;
  final Color shadow;

  static const light = SpringThemeColors(
    background: AppTheme.background,
    sidebar: AppTheme.sidebar,
    surface: AppTheme.surface,
    surfaceMuted: AppTheme.surfaceMuted,
    surfaceHover: Color(0xFFF5F5F5),
    surfacePressed: Color(0xFFE2E2E2),
    border: AppTheme.border,
    divider: Color(0xFFEEEEEE),
    text: AppTheme.text,
    textMuted: AppTheme.textMuted,
    textSubtle: AppTheme.textSubtle,
    onAccent: Colors.white,
    inputFill: Color(0xFFF5F5F5),
    inputFocusedFill: Color(0xFFEDEDED),
    shadow: Color(0x17171717),
  );

  static const dark = SpringThemeColors(
    background: Color(0xFF111111),
    sidebar: Color(0xFF141414),
    surface: Color(0xFF1B1B1B),
    surfaceMuted: Color(0xFF2A2A2A),
    surfaceHover: Color(0xFF242424),
    surfacePressed: Color(0xFF303030),
    border: Color(0xFF333333),
    divider: Color(0xFF2C2C2C),
    text: Color(0xFFF2F2F2),
    textMuted: Color(0xFFC7C7C7),
    textSubtle: Color(0xFF9A9A9A),
    onAccent: Color(0xFF111111),
    inputFill: Color(0xFF252525),
    inputFocusedFill: Color(0xFF303030),
    shadow: Color(0x99000000),
  );

  @override
  SpringThemeColors copyWith({
    Color? background,
    Color? sidebar,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceHover,
    Color? surfacePressed,
    Color? border,
    Color? divider,
    Color? text,
    Color? textMuted,
    Color? textSubtle,
    Color? onAccent,
    Color? inputFill,
    Color? inputFocusedFill,
    Color? shadow,
  }) {
    return SpringThemeColors(
      background: background ?? this.background,
      sidebar: sidebar ?? this.sidebar,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfacePressed: surfacePressed ?? this.surfacePressed,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textSubtle: textSubtle ?? this.textSubtle,
      onAccent: onAccent ?? this.onAccent,
      inputFill: inputFill ?? this.inputFill,
      inputFocusedFill: inputFocusedFill ?? this.inputFocusedFill,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  SpringThemeColors lerp(ThemeExtension<SpringThemeColors>? other, double t) {
    if (other is! SpringThemeColors) {
      return this;
    }
    return SpringThemeColors(
      background: Color.lerp(background, other.background, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      surfacePressed: Color.lerp(surfacePressed, other.surfacePressed, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textSubtle: Color.lerp(textSubtle, other.textSubtle, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      inputFocusedFill: Color.lerp(
        inputFocusedFill,
        other.inputFocusedFill,
        t,
      )!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

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
  static const List<Color> lightActivityHeatmapColors = [
    Color(0xFFEDEDED),
    Color(0xFFDCFCE7),
    Color(0xFFBBF7D0),
    Color(0xFF86EFAC),
    Color(0xFF4ADE80),
  ];
  static const List<Color> darkActivityHeatmapColors = [
    Color(0xFF2A2A2A),
    Color(0xFF0F2F1B),
    Color(0xFF14532D),
    Color(0xFF16A34A),
    Color(0xFF4ADE80),
  ];

  static SpringThemeColors colors(BuildContext context) {
    return Theme.of(context).extension<SpringThemeColors>() ??
        SpringThemeColors.light;
  }

  static List<Color> activityHeatmapColors(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkActivityHeatmapColors
        : lightActivityHeatmapColors;
  }

  static ThemeData light({String appFont = 'system'}) {
    return _theme(
      appFont: appFont,
      brightness: Brightness.light,
      colors: SpringThemeColors.light,
    );
  }

  static ThemeData dark({String appFont = 'system'}) {
    return _theme(
      appFont: appFont,
      brightness: Brightness.dark,
      colors: SpringThemeColors.dark,
    );
  }

  static ThemeData _theme({
    required String appFont,
    required Brightness brightness,
    required SpringThemeColors colors,
  }) {
    final fontFamily = appFont.trim().isEmpty || appFont == 'system'
        ? 'Segoe UI'
        : appFont.trim();
    final colorScheme = ColorScheme.fromSeed(
      seedColor: colors.text,
      brightness: brightness,
      surface: colors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        primary: colors.text,
        secondary: colors.textMuted,
        surface: colors.surface,
        onSurface: colors.text,
      ),
      extensions: <ThemeExtension<dynamic>>[colors],
      scaffoldBackgroundColor: colors.background,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      focusColor: Colors.transparent,
      fontFamily: fontFamily,
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: colors.text,
          fontSize: 32,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        headlineMedium: TextStyle(
          color: colors.text,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          color: colors.text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        titleMedium: TextStyle(
          color: colors.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        bodyLarge: TextStyle(
          color: colors.text,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.7,
        ),
        bodyMedium: TextStyle(
          color: colors.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.55,
        ),
        labelLarge: TextStyle(
          color: colors.text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ).apply(fontFamily: fontFamily),
      iconTheme: IconThemeData(color: colors.textMuted, size: 20),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.textSubtle.withValues(alpha: 0.38);
          }
          return colors.surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.text;
          }
          if (states.contains(WidgetState.disabled)) {
            return colors.surfaceMuted.withValues(alpha: 0.56);
          }
          return colors.surfaceMuted;
        }),
        trackOutlineColor: WidgetStatePropertyAll(colors.border),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashRadius: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.inputFill,
        hintStyle: TextStyle(color: colors.textSubtle),
        labelStyle: TextStyle(color: colors.textSubtle),
        floatingLabelStyle: TextStyle(color: colors.textMuted),
        helperStyle: TextStyle(color: colors.textSubtle),
        prefixIconColor: colors.textSubtle,
        suffixIconColor: colors.textSubtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.textSubtle),
        ),
      ),
    );
  }

  static double fontScaleFactor(double fontScale) {
    final safeScale = fontScale.isFinite ? fontScale : 100;
    return safeScale.clamp(80, 140).toDouble() / 100;
  }
}
