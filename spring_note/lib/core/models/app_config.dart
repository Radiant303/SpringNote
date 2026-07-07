import 'package:flutter/material.dart';

import 'cloud_sync_config.dart';
import 'desktop_widget_position.dart';
import 'desktop_widget_wallpaper_settings.dart';
import 'provider_config.dart';
import 'wallpaper_settings.dart';

const defaultDailyMergePrompt = '''你是 SpringNote 的日报整理助手。
你的任务是根据已有日报和新增随手记录，整理生成一篇自然、真实、便于继续编辑的日报。

已知信息：
- 日期：{date}
- 已有日报：{existing_markdown}
- 新增随手记录：{raw_input}
- 用户所在行业：{industry}

整理要求：
1. 综合利用所有已提供的信息进行整理，空变量自动忽略。
2. 如果已有日报存在，优先保留其中仍然有效的内容，并将新增记录自然融合进去；如果已有日报为空，则根据新增记录整理生成日报。
3. 严格保留事实，不得编造任何不存在的任务、时间、人员、原因、进展、结果、计划或情绪。
4. 在不改变事实的前提下，可以自由整理语言，包括补充完整句子、调整语序、合并重复内容、优化表达，使内容更加自然流畅。
5. 当新增记录只是关键词、短语或简短描述时，应主动整理成符合正常书面表达的完整内容，而不是直接照抄原文。允许适度扩展描述，使表达更加自然，但扩展内容只能服务于表达已有事实，不得引入新的事实信息。
6. 将零散记录整理成连贯的工作记录，使全文具有连续阅读体验，读起来像用户亲自整理后的日报，而不是 AI 自动汇总的结果。
7. 内容较少时保持简洁，避免为了丰富内容而重复表达；内容较多时可自然分段或按主题组织，但不要为了分组而分组。
8. 表达应符合真实开发者或职场人士日常记录工作的习惯，语言自然、克制、顺畅，避免机械、模板化或过于正式的总结语气。
9. 可以结合所在行业调整专业术语和表达习惯，但不得补充任何事实。
10. 如果已有日报与新增记录存在重复，应保留表达更完整、更自然的一份，避免重复描述。
11. 保留已有日报的整体结构和可继续编辑性，不随意改变已有内容的组织方式。
12. 不输出变量名称，不解释整理过程，不添加任何说明，仅输出最终日报内容。''';

class AppConfig {
  const AppConfig({
    required this.appThemeMode,
    required this.wallpaperSettings,
    required this.dailyWorkHours,
    required this.dailySalary,
    required this.industry,
    required this.appFont,
    required this.fontScale,
    required this.customDataDirectory,
    required this.autoStart,
    required this.showUpdates,
    required this.showDesktopWidget,
    required this.desktopWidgetPosition,
    required this.desktopWidgetOrbMode,
    required this.desktopWidgetWallpaperSettings,
    required this.showTrayIcon,
    required this.closeToTray,
    required this.memorySearchLimit,
    required this.memoryResultMaxCharacters,
    required this.memoryWeekDailyNoteLimit,
    required this.memoryKeywordSearchResultLimit,
    required this.memoryKeywordContextBefore,
    required this.memoryKeywordContextAfter,
    required this.dailyMergePrompt,
    required this.apiLogEnabled,
    required this.cloudSync,
    required this.providers,
    required this.defaultModels,
    required this.hotkeys,
  });

  final ThemeMode appThemeMode;
  final WallpaperSettings wallpaperSettings;

  final double dailyWorkHours;
  final double dailySalary;
  final String industry;
  final String appFont;
  final double fontScale;
  final String? customDataDirectory;
  final bool autoStart;
  final bool showUpdates;
  final bool showDesktopWidget;
  final DesktopWidgetPosition? desktopWidgetPosition;
  final bool desktopWidgetOrbMode;
  final DesktopWidgetWallpaperSettings desktopWidgetWallpaperSettings;
  final bool showTrayIcon;
  final bool closeToTray;
  final double memorySearchLimit;
  final double memoryResultMaxCharacters;
  final double memoryWeekDailyNoteLimit;
  final double memoryKeywordSearchResultLimit;
  final double memoryKeywordContextBefore;
  final double memoryKeywordContextAfter;
  final String dailyMergePrompt;
  final bool apiLogEnabled;
  final CloudSyncConfig cloudSync;
  final List<ProviderConfig> providers;
  final Map<String, String?> defaultModels;
  final Map<String, String?> hotkeys;

  factory AppConfig.defaults() {
    return const AppConfig(
      appThemeMode: ThemeMode.system,
      wallpaperSettings: WallpaperSettings.defaults,
      dailyWorkHours: 8,
      dailySalary: 200,
      industry: '互联网',
      appFont: 'system',
      fontScale: 100,
      customDataDirectory: null,
      autoStart: false,
      showUpdates: true,
      showDesktopWidget: true,
      desktopWidgetPosition: null,
      desktopWidgetOrbMode: false,
      desktopWidgetWallpaperSettings: DesktopWidgetWallpaperSettings.defaults,
      showTrayIcon: true,
      closeToTray: true,
      memorySearchLimit: 12,
      memoryResultMaxCharacters: 3600,
      memoryWeekDailyNoteLimit: 31,
      memoryKeywordSearchResultLimit: 12,
      memoryKeywordContextBefore: 1400,
      memoryKeywordContextAfter: 2600,
      dailyMergePrompt: defaultDailyMergePrompt,
      apiLogEnabled: false,
      cloudSync: CloudSyncConfig.defaultsValue,
      providers: [],
      defaultModels: {
        'intelligentGenerationModel': null,
        'editCompletionModel': null,
        'memoryBookModel': null,
      },
      hotkeys: {'toggleWindow': 'Ctrl+Shift+S'},
    );
  }

  factory AppConfig.fromJson(Map<String, Object?> json) {
    return AppConfig(
      appThemeMode: _readThemeMode(json['appThemeMode']),
      wallpaperSettings: json['wallpaperSettings'] != null
          ? WallpaperSettings.fromJson(
              (json['wallpaperSettings'] as Map).cast<String, dynamic>(),
            )
          : WallpaperSettings.defaults,
      dailyWorkHours: _readDouble(json['dailyWorkHours'], 8),
      dailySalary: _readDouble(json['dailySalary'], 200),
      industry: json['industry'] as String? ?? '互联网',
      appFont: json['appFont'] as String? ?? 'system',
      fontScale: _readDouble(json['fontScale'], 100),
      customDataDirectory: _readOptionalString(json['customDataDirectory']),
      autoStart: json['autoStart'] as bool? ?? false,
      showUpdates: json['showUpdates'] as bool? ?? true,
      showDesktopWidget: json['showDesktopWidget'] as bool? ?? true,
      desktopWidgetPosition: DesktopWidgetPosition.fromJson(
        json['desktopWidgetPosition'],
      ),
      desktopWidgetOrbMode: json['desktopWidgetOrbMode'] as bool? ?? false,
      desktopWidgetWallpaperSettings:
          json['desktopWidgetWallpaperSettings'] != null
              ? DesktopWidgetWallpaperSettings.fromJson(
                  (json['desktopWidgetWallpaperSettings'] as Map)
                      .cast<String, dynamic>(),
                )
              : DesktopWidgetWallpaperSettings.defaults,
      showTrayIcon: json['showTrayIcon'] as bool? ?? true,
      closeToTray: (json['showTrayIcon'] as bool? ?? true) &&
          (json['closeToTray'] as bool? ?? true),
      memorySearchLimit: _readDouble(json['memorySearchLimit'], 12),
      memoryResultMaxCharacters: _readDouble(
        json['memoryResultMaxCharacters'],
        3600,
      ),
      memoryWeekDailyNoteLimit: _readDouble(
        json['memoryWeekDailyNoteLimit'],
        31,
      ),
      memoryKeywordSearchResultLimit: _readDouble(
        json['memoryKeywordSearchResultLimit'],
        12,
      ),
      memoryKeywordContextBefore: _readDouble(
        json['memoryKeywordContextBefore'],
        1400,
      ),
      memoryKeywordContextAfter: _readDouble(
        json['memoryKeywordContextAfter'],
        2600,
      ),
      dailyMergePrompt: _readString(
        json['dailyMergePrompt'],
        defaultDailyMergePrompt,
      ),
      apiLogEnabled: json['apiLogEnabled'] as bool? ?? false,
      cloudSync: CloudSyncConfig.fromJson(json['cloudSync']),
      providers: _readProviders(json['providers']),
      defaultModels: _readStringMap(
        json['defaultModels'],
        AppConfig.defaults().defaultModels,
      ),
      hotkeys: _readStringMap(json['hotkeys'], AppConfig.defaults().hotkeys),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'appThemeMode': _themeModeToString(appThemeMode),
      'wallpaperSettings': wallpaperSettings.toJson(),
      'dailyWorkHours': dailyWorkHours,
      'dailySalary': dailySalary,
      'industry': industry,
      'appFont': appFont,
      'fontScale': fontScale,
      'customDataDirectory': customDataDirectory,
      'autoStart': autoStart,
      'showUpdates': showUpdates,
      'showDesktopWidget': showDesktopWidget,
      'desktopWidgetPosition': desktopWidgetPosition?.toJson(),
      'desktopWidgetOrbMode': desktopWidgetOrbMode,
      'desktopWidgetWallpaperSettings': desktopWidgetWallpaperSettings.toJson(),
      'showTrayIcon': showTrayIcon,
      'closeToTray': closeToTray,
      'memorySearchLimit': memorySearchLimit,
      'memoryResultMaxCharacters': memoryResultMaxCharacters,
      'memoryWeekDailyNoteLimit': memoryWeekDailyNoteLimit,
      'memoryKeywordSearchResultLimit': memoryKeywordSearchResultLimit,
      'memoryKeywordContextBefore': memoryKeywordContextBefore,
      'memoryKeywordContextAfter': memoryKeywordContextAfter,
      'dailyMergePrompt': dailyMergePrompt,
      'apiLogEnabled': apiLogEnabled,
      'cloudSync': cloudSync.toJson(),
      'providers': providers.map((provider) => provider.toJson()).toList(),
      'defaultModels': defaultModels,
      'hotkeys': hotkeys,
    };
  }

  AppConfig copyWith({
    ThemeMode? appThemeMode,
    WallpaperSettings? wallpaperSettings,
    double? dailyWorkHours,
    double? dailySalary,
    String? industry,
    String? appFont,
    double? fontScale,
    Object? customDataDirectory = _sentinel,
    bool? autoStart,
    bool? showUpdates,
    bool? showDesktopWidget,
    Object? desktopWidgetPosition = _sentinel,
    bool? desktopWidgetOrbMode,
    DesktopWidgetWallpaperSettings? desktopWidgetWallpaperSettings,
    bool? showTrayIcon,
    bool? closeToTray,
    double? memorySearchLimit,
    double? memoryResultMaxCharacters,
    double? memoryWeekDailyNoteLimit,
    double? memoryKeywordSearchResultLimit,
    double? memoryKeywordContextBefore,
    double? memoryKeywordContextAfter,
    String? dailyMergePrompt,
    bool? apiLogEnabled,
    CloudSyncConfig? cloudSync,
    List<ProviderConfig>? providers,
    Map<String, String?>? defaultModels,
    Map<String, String?>? hotkeys,
  }) {
    final nextShowTrayIcon = showTrayIcon ?? this.showTrayIcon;
    final nextCloseToTray =
        nextShowTrayIcon && (closeToTray ?? this.closeToTray);
    return AppConfig(
      appThemeMode: appThemeMode ?? this.appThemeMode,
      wallpaperSettings: wallpaperSettings ?? this.wallpaperSettings,
      dailyWorkHours: dailyWorkHours ?? this.dailyWorkHours,
      dailySalary: dailySalary ?? this.dailySalary,
      industry: industry ?? this.industry,
      appFont: appFont ?? this.appFont,
      fontScale: fontScale ?? this.fontScale,
      customDataDirectory: customDataDirectory == _sentinel
          ? this.customDataDirectory
          : customDataDirectory as String?,
      autoStart: autoStart ?? this.autoStart,
      showUpdates: showUpdates ?? this.showUpdates,
      showDesktopWidget: showDesktopWidget ?? this.showDesktopWidget,
      desktopWidgetPosition: desktopWidgetPosition == _sentinel
          ? this.desktopWidgetPosition
          : desktopWidgetPosition as DesktopWidgetPosition?,
      desktopWidgetOrbMode: desktopWidgetOrbMode ?? this.desktopWidgetOrbMode,
      desktopWidgetWallpaperSettings:
          desktopWidgetWallpaperSettings ?? this.desktopWidgetWallpaperSettings,
      showTrayIcon: nextShowTrayIcon,
      closeToTray: nextCloseToTray,
      memorySearchLimit: memorySearchLimit ?? this.memorySearchLimit,
      memoryResultMaxCharacters:
          memoryResultMaxCharacters ?? this.memoryResultMaxCharacters,
      memoryWeekDailyNoteLimit:
          memoryWeekDailyNoteLimit ?? this.memoryWeekDailyNoteLimit,
      memoryKeywordSearchResultLimit:
          memoryKeywordSearchResultLimit ?? this.memoryKeywordSearchResultLimit,
      memoryKeywordContextBefore:
          memoryKeywordContextBefore ?? this.memoryKeywordContextBefore,
      memoryKeywordContextAfter:
          memoryKeywordContextAfter ?? this.memoryKeywordContextAfter,
      dailyMergePrompt: dailyMergePrompt ?? this.dailyMergePrompt,
      apiLogEnabled: apiLogEnabled ?? this.apiLogEnabled,
      cloudSync: cloudSync ?? this.cloudSync,
      providers: providers ?? this.providers,
      defaultModels: defaultModels ?? this.defaultModels,
      hotkeys: hotkeys ?? this.hotkeys,
    );
  }

  static double _readDouble(Object? value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }

  static String _readString(Object? value, String fallback) {
    if (value is! String) {
      return fallback;
    }
    return value.trim().isEmpty ? fallback : value;
  }

  static String? _readOptionalString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<ProviderConfig> _readProviders(Object? value) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map(
          (entry) => entry.map((key, value) => MapEntry(key.toString(), value)),
        )
        .map(ProviderConfig.fromJson)
        .toList();
  }

  static Map<String, String?> _readStringMap(
    Object? value,
    Map<String, String?> fallback,
  ) {
    final result = Map<String, String?>.from(fallback);
    if (value is Map) {
      for (final entry in value.entries) {
        result[entry.key.toString()] = entry.value?.toString();
      }
    }
    return result;
  }

  static ThemeMode _readThemeMode(Object? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.system;
    }
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

const Object _sentinel = Object();
