import 'dart:async';
import 'dart:io';

class SystemFontService {
  const SystemFontService();

  /// 已知中文字体白名单（同时包含英文名与中文名）
  static const Set<String> _chineseFontWhitelist = {
    // 微软字体
    'Microsoft YaHei', 'Microsoft YaHei UI', '微软雅黑',
    'SimSun', '宋体',
    'SimHei', '黑体',
    'KaiTi', '楷体',
    'FangSong', '仿宋',
    'STSong', '华文宋体',
    'STHeiti', '华文黑体',
    'STKaiti', '华文楷体',
    'STFangsong', '华文仿宋',
    'NSimSun', '新宋体',
    // 方正字体
    'FZShuTi', '方正舒体',
    'FZYaoti', '方正姚体',
    // 其他常见中文字体
    'DengXian', '等线',
    'YouYuan', '幼圆',
    'LiSu', '隶书',
    'STXihei', '华文细黑',
    'STLiti', '华文隶书',
    'STXingkai', '华文行楷',
    'STXinwei', '华文新魏',
    // 思源字体
    'Source Han Sans',
    'Source Han Serif',
    'Noto Sans CJK',
    'Noto Serif CJK',
  };

  /// 平台对应的中文回退字体链。
  /// 选择不支持中文的字体时，主题会使用该链保证中文字符正常显示。
  static List<String> chineseFallbackFonts() {
    if (Platform.isMacOS) {
      return const ['PingFang SC', 'Hiragino Sans GB', 'sans-serif'];
    }
    if (Platform.isLinux) {
      return const ['Noto Sans CJK SC', 'WenQuanYi Micro Hei', 'sans-serif'];
    }
    // Windows 与其他平台默认链
    return const ['Microsoft YaHei', 'SimHei', 'sans-serif'];
  }

  /// 判断指定字体是否支持中文字符。
  /// 使用白名单匹配（不区分大小写）。
  static bool isChineseSupported(String fontFamily) {
    if (fontFamily == 'system' || fontFamily == 'custom') {
      return true;
    }
    final normalized = fontFamily.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    for (final entry in _chineseFontWhitelist) {
      if (entry.toLowerCase() == normalized) {
        return true;
      }
    }
    return false;
  }

  /// 预计算一组字体中支持中文的字体集合，供排序与 UI 渲染共用。
  static Set<String> computeChineseSupportedSet(Iterable<String> fonts) {
    final result = <String>{};
    for (final font in fonts) {
      if (isChineseSupported(font)) {
        result.add(font);
      }
    }
    return result;
  }

  /// 智能排序：支持中文的字体（含 system / custom 默认项）排前，
  /// 其余按字母序排列（不区分大小写）。
  static List<String> sortFonts(
    List<String> fonts,
    Set<String> chineseSupportedSet,
  ) {
    final result = List<String>.from(fonts);
    result.sort((a, b) {
      final aSupported =
          a == 'system' || a == 'custom' || chineseSupportedSet.contains(a);
      final bSupported =
          b == 'system' || b == 'custom' || chineseSupportedSet.contains(b);

      if (aSupported != bSupported) {
        return aSupported ? -1 : 1;
      }
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return result;
  }

  Future<List<String>> loadFonts() async {
    if (!Platform.isWindows) {
      return _normalizeFonts(_fallbackFonts());
    }

    final powershellFonts = await _loadWindowsFontsFromPowerShell();
    if (powershellFonts.isNotEmpty) {
      return _normalizeFonts(powershellFonts);
    }

    final registryFonts = await _loadWindowsFontsFromRegistry();
    if (registryFonts.isNotEmpty) {
      return _normalizeFonts(registryFonts);
    }

    return _normalizeFonts(_fallbackFonts());
  }

  Future<List<String>> _loadWindowsFontsFromPowerShell() async {
    const command = '''
Add-Type -AssemblyName System.Drawing
\$collection = New-Object System.Drawing.Text.InstalledFontCollection
\$collection.Families | ForEach-Object { \$_.Name }
''';

    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        command,
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) {
        return const [];
      }
      return _splitLines(result.stdout.toString());
    } on Object {
      return const [];
    }
  }

  Future<List<String>> _loadWindowsFontsFromRegistry() async {
    final fonts = <String>[];
    const keys = [
      r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
      r'HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
    ];

    for (final key in keys) {
      try {
        final result = await Process.run('reg', [
          'query',
          key,
        ]).timeout(const Duration(seconds: 3));
        if (result.exitCode != 0) {
          continue;
        }
        fonts.addAll(_parseRegistryFonts(result.stdout.toString()));
      } on Object {
        continue;
      }
    }

    return fonts;
  }

  List<String> _parseRegistryFonts(String output) {
    final fonts = <String>[];
    final linePattern = RegExp(r'^\s*(.+?)\s+REG_\w+\s+.+$');
    for (final line in _splitLines(output)) {
      final match = linePattern.firstMatch(line);
      if (match == null) {
        continue;
      }
      var name = match.group(1) ?? '';
      name = name.replaceAll(
        RegExp(
          r'\s*\((?:TrueType|OpenType|Type 1)\)\s*$',
          caseSensitive: false,
        ),
        '',
      );
      name = name.replaceAll(
        RegExp(
          r'\s+(?:Regular|Bold|Italic|Bold Italic|Oblique|Light|Medium|SemiBold|Semibold|Black|Thin|Condensed|Narrow)$',
          caseSensitive: false,
        ),
        '',
      );
      fonts.add(name);
    }
    return fonts;
  }

  List<String> _normalizeFonts(Iterable<String> fonts) {
    final blocked = RegExp(
      r'^(?:@|Marlett$|Symbol$|Webdings$|Wingdings|Segoe Fluent Icons$|Segoe MDL2 Assets$)',
      caseSensitive: false,
    );
    final result = <String>{};
    for (final font in fonts) {
      final value = font.trim();
      if (value.isEmpty || blocked.hasMatch(value)) {
        continue;
      }
      result.add(value);
    }
    final sorted = result.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  List<String> _splitLines(String value) {
    return value
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  List<String> _fallbackFonts() {
    if (Platform.isMacOS) {
      return const ['Helvetica Neue', 'PingFang SC', 'Arial'];
    }
    if (Platform.isLinux) {
      return const ['Noto Sans CJK SC', 'Noto Sans', 'DejaVu Sans'];
    }
    return const [
      'Segoe UI',
      'Segoe UI Variable',
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'Arial',
    ];
  }
}
