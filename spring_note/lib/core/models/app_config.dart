import 'package:flutter/foundation.dart';

import 'app_language.dart';
import 'cloud_sync_config.dart';
import 'desktop_widget_position.dart';
import 'desktop_widget_wallpaper_settings.dart';
import 'provider_config.dart';
import 'structured_note_section_config.dart';
import 'wallpaper_settings.dart';

enum AppThemePreference { system, light, dark }

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
3. 严格保留事实，不得编造任何不存在的任务、时间、人员、原因、进展、结果、计划、评价或情绪。
4. 在不改变事实的前提下，可以自由整理语言，包括补充完整句子、调整语序、合并重复内容、优化表达，使内容更加自然流畅。
5. 当新增记录只是关键词、短语或简短描述时，应主动整理成符合正常书面表达的完整内容，而不是直接照抄原文。允许适度扩展描述，使表达更加自然，但扩展内容只能服务于表达已有事实，不得引入新的事实信息。
6. 将零散记录整理成连贯的工作记录，使全文具有连续阅读体验，读起来像用户亲自整理后的日报，而不是 AI 自动汇总的结果。
7. 内容较少时保持简洁，避免为了丰富内容而重复表达；内容较多时可自然分段或按主题组织，但不要为了分组而分组。
8. 表达应符合真实开发者或职场人士日常记录工作的习惯，语言自然、克制、顺畅，避免机械、模板化或过于正式的总结语气。
9. 可以结合所在行业调整专业术语和表达习惯，但不得补充任何事实。
10. 如果已有日报与新增记录存在重复，应保留表达更完整、更自然的一份，避免重复描述。
11. 保留已有日报的整体结构和可继续编辑性，不随意改变已有内容的组织方式。
12. 不输出变量名称，不解释整理过程，不添加任何说明，仅输出最终日报内容。''';

const defaultDailyMergePromptEn = '''You are SpringNote's daily-note editor.
Your job is to merge the existing daily note and the new quick capture into a natural, truthful daily note that stays easy to keep editing.

Known information:
- Date: {date}
- Existing daily note: {existing_markdown}
- New quick capture: {raw_input}
- User's industry: {industry}

Rules:
1. Use all provided information; ignore empty variables.
2. If an existing daily note is present, prefer keeping its still-valid content and blend the new capture in naturally; if it is empty, write the daily note from the new capture.
3. Strictly preserve facts; never invent tasks, times, people, causes, progress, results, plans, evaluations, or moods.
4. Without changing facts, you may polish the language: complete sentences, reorder, merge duplicates, and refine wording for a natural read.
5. When the new capture is only keywords, phrases, or fragments, rewrite them into complete written sentences instead of copying verbatim. Modest elaboration is allowed only to express existing facts more naturally; never introduce new facts.
6. Turn scattered notes into a coherent work log that reads like the user wrote it, not like an AI summary.
7. Keep it brief when there is little content; when there is more, use natural paragraphs or topics, but do not group for grouping's sake.
8. Write like a real developer or professional recording their day: natural, restrained, fluent; avoid mechanical, templated, or overly formal summary language.
9. You may adapt terminology and phrasing to the user's industry, but do not add facts.
10. If the existing note and the new capture overlap, keep the more complete, more natural version; avoid duplication.
11. Preserve the existing note's overall structure and editability; do not reorganize arbitrarily.
12. Do not output variable names, explanations, or any commentary; output only the final daily note content.''';

/// 按生效语言返回日报整理默认提示词（[language] 为 'zh' 或 'en'）。
String defaultDailyMergePromptFor(String language) {
  return language == 'en' ? defaultDailyMergePromptEn : defaultDailyMergePrompt;
}

const defaultGlobalSignPrompt = '''你是 SpringNote 的全局签整理助手。全局签是一份跨天的待办清单（ToDoList），记录需要持续跟进、尚未完成的事项。

已知信息：
- 日期：{date}
- 当日日报：{daily_markdown}
- 当前全局签 JSON：{global_sign}
- 新增随手记录：{raw_input}
- 用户所在行业：{industry}

整理要求：
1. 结合当日日报与新增随手记录，判断是否需要向全局签新增、更新或移除待办事项；没有需要变更的内容时，原样返回当前全局签列表。
2. 新增事项只能来源于新增随手记录中明确表达的内容；当日日报仅作为判断完成、更新或移除的上下文，不得仅依据日报内容新增事项。
3. 保留当前全局签中仍未完成的事项及其 id，不得丢失；仅在内容确实需要修订时保留 id 并更新 content。
4. 当新增随手记录或当日日报对当前全局签中的某个事项表达了完成、取消或结束的含义时，以记录为准，将该事项从列表中移除，即使事项原文的范围更大或措辞不同也不得保留；记录仅描述进展而没有结束含义时，不得移除。
5. 当输入中带有【已完成】或【已取消】标记的事项时，将它们从全局签中移除，不再返回。
6. 新增事项的 id 使用空字符串，由系统统一分配。
7. 严格保留事实，不得编造任务、时间、人员或进展；事项描述简洁明确，一句话说清要做什么。
8. 不得随意扩展、引申或替换输入中提到的内容；事项涉及的对象、动作和范围必须来自输入中明确表达的信息，与输入保持一致。
9. 只输出 JSON，格式固定为 {"items": [{"id": "...", "content": "..."}]}，不要输出任何解释或说明。''';

const defaultGlobalSignPromptEn = '''You are SpringNote's global-sign editor. The global sign is a cross-day todo list of things that still need follow-up.

Known information:
- Date: {date}
- Today's daily note: {daily_markdown}
- Current global sign JSON: {global_sign}
- New quick capture: {raw_input}
- User's industry: {industry}

Rules:
1. Based on today's daily note and the new capture, decide whether to add, update, or remove todo items; when nothing needs to change, return the current list unchanged.
2. New items may only come from content explicitly stated in the new quick capture; the daily note only provides context for judging completion, updates, or removal — never add items based on the daily note alone.
3. Keep unfinished current items and their ids; update content only when it truly needs revising, keeping the id.
4. When the new capture or today's daily note expresses that a current item is finished, cancelled, or done with, trust the record and remove the item — even if the item's original wording is broader; when the record only describes progress without any finishing meaning, do not remove it.
5. Items tagged with the【Completed】or【Cancelled】markers in the input must be removed from the list.
6. New items use an empty string as id; the system assigns ids.
7. Strictly preserve facts; never invent tasks, times, people, or progress; keep each item concise — one clear sentence saying what to do.
8. Do not expand, extrapolate, or replace what the input states; an item's object, action, and scope must match the input exactly.
9. Output only JSON in the form {"items": [{"id": "...", "content": "..."}]}, with no explanation or commentary.''';

/// 按生效语言返回全局签默认提示词（[language] 为 'zh' 或 'en'）。
String defaultGlobalSignPromptFor(String language) {
  return language == 'en' ? defaultGlobalSignPromptEn : defaultGlobalSignPrompt;
}

const defaultWeeklyReportPrompt = '''你是 SpringNote 的周报整理助手。请基于一周日报 Markdown 生成一篇自然、有重点、可直接编辑的周报。

已知信息：
- 周期：{period_label}
- 用户所在行业：{industry}
- 本周日报内容：
{source_markdown}

写作原则：
1. 综合利用所有已提供的信息进行整理，空变量自动忽略。
2. 保留来源中的事实，不编造没有依据的成果、风险或计划。
3. 不需要固定套用“主要工作 / 关键进展 / 问题 / 下周计划”等模板，可以根据材料自由组织结构。
4. Markdown 要层次清楚、阅读舒服；可以使用标题、段落、列表、重点小结，但避免机械堆栏目。
5. 优先呈现这一周真正发生了什么、推进到了哪里、遇到什么卡点、接下来怎么走。
6. 语气自然，像一个认真复盘工作的人的周报，不要像 AI 模板。
7. 可以结合所在行业调整专业术语和表达习惯，但不得补充任何事实。
8. 全文第一行必须是一级标题，格式固定为 `# XXXX-WXX 周报`（ISO 周，取自上述周期信息，例如 `# 2026-W30 周报`），不得自拟、追加或省略。
9. 只输出最终 Markdown，不要解释。''';

const defaultWeeklyReportPromptEn = '''You are SpringNote's weekly-report editor. Write a natural, focused, editable weekly report from a week of daily Markdown notes.

Known information:
- Period: {period_label}
- User's industry: {industry}
- Daily notes of the week:
{source_markdown}

Principles:
1. Use all provided information; ignore empty variables.
2. Preserve the facts from the source; do not invent outcomes, risks, or plans.
3. Do not force a fixed template such as "Main work / Key progress / Issues / Next week"; organize freely around the material.
4. Use clear, comfortable Markdown: headings, paragraphs, lists, and brief highlights are welcome; avoid mechanical section stacking.
5. Focus on what actually happened this week, how far things moved, what is blocked, and what comes next.
6. Sound natural, like someone carefully reviewing their own week — not an AI template.
7. You may adapt terminology and phrasing to the user's industry, but do not add facts.
8. The first line must be a level-1 heading in the exact form `# XXXX-WXX Weekly Report` (ISO week, taken from the period above, e.g. `# 2026-W30 Weekly Report`); do not invent, append, or omit anything.
9. Output only the final Markdown, no explanations.''';

/// 按生效语言返回周报整理默认提示词（[language] 为 'zh' 或 'en'）。
String defaultWeeklyReportPromptFor(String language) {
  return language == 'en'
      ? defaultWeeklyReportPromptEn
      : defaultWeeklyReportPrompt;
}

class AppConfig {
  const AppConfig({
    required this.wallpaperSettings,
    required this.dailyWorkHours,
    required this.dailySalary,
    required this.industry,
    required this.appFont,
    required this.fontScale,
    required this.language,
    required this.markdownSyntaxHighlightEnabled,
    required this.notesEditorWorkspaceMode,
    required this.themeMode,
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
    required this.structuredNoteSections,
    required this.dailyMergePrompt,
    required this.globalSignPrompt,
    required this.weeklyReportPrompt,
    required this.apiLogEnabled,
    required this.reportImageInputEnabled,
    required this.cloudSync,
    required this.providers,
    required this.defaultModels,
    required this.hotkeys,
    required this.submitShortcut,
  });

  final WallpaperSettings wallpaperSettings;

  final double dailyWorkHours;
  final double dailySalary;
  final String industry;
  final String appFont;
  final double fontScale;

  /// UI 语言：'system'（跟随系统）、'zh'（简体中文）、'en'（English）。
  final String language;
  final bool markdownSyntaxHighlightEnabled;
  final String notesEditorWorkspaceMode;
  final AppThemePreference themeMode;
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
  final List<StructuredNoteSectionConfig> structuredNoteSections;
  final String dailyMergePrompt;
  final String globalSignPrompt;
  final String weeklyReportPrompt;
  final bool apiLogEnabled;
  final bool reportImageInputEnabled;
  final CloudSyncConfig cloudSync;
  final List<ProviderConfig> providers;
  final Map<String, String?> defaultModels;
  final Map<String, String?> hotkeys;

  /// Send-shortcut mode for the quick-capture and memory chat inputs:
  /// 'ctrlEnter' (default) sends with Ctrl+Enter (Cmd+Enter on macOS) and
  /// lets plain Enter insert a newline; 'enter' swaps the two.
  final String submitShortcut;

  /// True when plain Enter sends and Ctrl/Cmd+Enter inserts the newline.
  bool get submitWithEnter => submitShortcut == 'enter';

  static const String defaultSubmitShortcut = 'ctrlEnter';

  static String get defaultToggleWindowHotkey =>
      defaultTargetPlatform == TargetPlatform.macOS
      ? 'Cmd+Shift+S'
      : 'Ctrl+Shift+S';

  factory AppConfig.defaults() {
    final language = resolveAppLanguage('system');
    return AppConfig(
      wallpaperSettings: WallpaperSettings.defaults,
      dailyWorkHours: 8,
      dailySalary: 200,
      industry: '互联网',
      appFont: 'system',
      fontScale: 100,
      language: 'system',
      markdownSyntaxHighlightEnabled: true,
      notesEditorWorkspaceMode: 'split',
      themeMode: AppThemePreference.system,
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
      structuredNoteSections: StructuredNoteSectionConfig.defaultsFor(language),
      dailyMergePrompt: defaultDailyMergePromptFor(language),
      globalSignPrompt: defaultGlobalSignPromptFor(language),
      weeklyReportPrompt: defaultWeeklyReportPromptFor(language),
      apiLogEnabled: false,
      reportImageInputEnabled: true,
      cloudSync: CloudSyncConfig.defaultsValue,
      providers: [],
      defaultModels: {
        'intelligentGenerationModel': null,
        'editCompletionModel': null,
        'memoryBookModel': null,
      },
      hotkeys: {'toggleWindow': defaultToggleWindowHotkey},
      submitShortcut: defaultSubmitShortcut,
    );
  }

  factory AppConfig.fromJson(Map<String, Object?> json) {
    final language = resolveAppLanguage(_readLanguage(json['language']));
    return AppConfig(
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
      language: _readLanguage(json['language']),
      markdownSyntaxHighlightEnabled:
          json['markdownSyntaxHighlightEnabled'] as bool? ?? true,
      notesEditorWorkspaceMode: _readNotesEditorWorkspaceMode(
        json['notesEditorWorkspaceMode'],
      ),
      themeMode: _readThemePreference(json['themeMode']),
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
      closeToTray:
          (json['showTrayIcon'] as bool? ?? true) &&
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
      structuredNoteSections: StructuredNoteSectionConfig.fromJson(
        json['structuredNoteSections'],
        language: language,
      ),
      dailyMergePrompt: _readString(
        json['dailyMergePrompt'],
        defaultDailyMergePromptFor(language),
      ),
      globalSignPrompt: _readString(
        json['globalSignPrompt'],
        defaultGlobalSignPromptFor(language),
      ),
      weeklyReportPrompt: _readString(
        json['weeklyReportPrompt'],
        defaultWeeklyReportPromptFor(language),
      ),
      apiLogEnabled: json['apiLogEnabled'] as bool? ?? false,
      reportImageInputEnabled: json['reportImageInputEnabled'] as bool? ?? true,
      cloudSync: CloudSyncConfig.fromJson(json['cloudSync']),
      providers: _readProviders(json['providers']),
      defaultModels: _readStringMap(
        json['defaultModels'],
        AppConfig.defaults().defaultModels,
      ),
      hotkeys: _readStringMap(json['hotkeys'], AppConfig.defaults().hotkeys),
      submitShortcut: _readSubmitShortcut(json['submitShortcut']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'wallpaperSettings': wallpaperSettings.toJson(),
      'dailyWorkHours': dailyWorkHours,
      'dailySalary': dailySalary,
      'industry': industry,
      'appFont': appFont,
      'fontScale': fontScale,
      'language': language,
      'markdownSyntaxHighlightEnabled': markdownSyntaxHighlightEnabled,
      'notesEditorWorkspaceMode': notesEditorWorkspaceMode,
      'themeMode': themeMode.name,
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
      'structuredNoteSections': structuredNoteSections
          .map((section) => section.toJson())
          .toList(),
      'dailyMergePrompt': dailyMergePrompt,
      'globalSignPrompt': globalSignPrompt,
      'weeklyReportPrompt': weeklyReportPrompt,
      'apiLogEnabled': apiLogEnabled,
      'reportImageInputEnabled': reportImageInputEnabled,
      'cloudSync': cloudSync.toJson(),
      'providers': providers.map((provider) => provider.toJson()).toList(),
      'defaultModels': defaultModels,
      'hotkeys': hotkeys,
      'submitShortcut': submitShortcut,
    };
  }

  AppConfig copyWith({
    WallpaperSettings? wallpaperSettings,
    double? dailyWorkHours,
    double? dailySalary,
    String? industry,
    String? appFont,
    double? fontScale,
    String? language,
    bool? markdownSyntaxHighlightEnabled,
    String? notesEditorWorkspaceMode,
    AppThemePreference? themeMode,
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
    List<StructuredNoteSectionConfig>? structuredNoteSections,
    String? dailyMergePrompt,
    String? globalSignPrompt,
    String? weeklyReportPrompt,
    bool? apiLogEnabled,
    bool? reportImageInputEnabled,
    CloudSyncConfig? cloudSync,
    List<ProviderConfig>? providers,
    Map<String, String?>? defaultModels,
    Map<String, String?>? hotkeys,
    String? submitShortcut,
  }) {
    final nextShowTrayIcon = showTrayIcon ?? this.showTrayIcon;
    final nextCloseToTray =
        nextShowTrayIcon && (closeToTray ?? this.closeToTray);
    return AppConfig(
      wallpaperSettings: wallpaperSettings ?? this.wallpaperSettings,
      dailyWorkHours: dailyWorkHours ?? this.dailyWorkHours,
      dailySalary: dailySalary ?? this.dailySalary,
      industry: industry ?? this.industry,
      appFont: appFont ?? this.appFont,
      fontScale: fontScale ?? this.fontScale,
      language: language ?? this.language,
      markdownSyntaxHighlightEnabled:
          markdownSyntaxHighlightEnabled ?? this.markdownSyntaxHighlightEnabled,
      notesEditorWorkspaceMode:
          notesEditorWorkspaceMode ?? this.notesEditorWorkspaceMode,
      themeMode: themeMode ?? this.themeMode,
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
      structuredNoteSections: structuredNoteSections == null
          ? this.structuredNoteSections
          : StructuredNoteSectionConfig.normalize(structuredNoteSections),
      dailyMergePrompt: dailyMergePrompt ?? this.dailyMergePrompt,
      globalSignPrompt: globalSignPrompt ?? this.globalSignPrompt,
      weeklyReportPrompt: weeklyReportPrompt ?? this.weeklyReportPrompt,
      apiLogEnabled: apiLogEnabled ?? this.apiLogEnabled,
      reportImageInputEnabled:
          reportImageInputEnabled ?? this.reportImageInputEnabled,
      cloudSync: cloudSync ?? this.cloudSync,
      providers: providers ?? this.providers,
      defaultModels: defaultModels ?? this.defaultModels,
      hotkeys: hotkeys ?? this.hotkeys,
      submitShortcut: submitShortcut ?? this.submitShortcut,
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

  static AppThemePreference _readThemePreference(Object? value) {
    if (value is! String) {
      return AppThemePreference.system;
    }
    final normalized = value.trim().toLowerCase();
    for (final mode in AppThemePreference.values) {
      if (mode.name.toLowerCase() == normalized) {
        return mode;
      }
    }
    return AppThemePreference.system;
  }

  static String _readLanguage(Object? value) {
    if (value is! String) {
      return 'system';
    }
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'zh' || 'en' || 'system' => normalized,
      _ => 'system',
    };
  }

  static String _readNotesEditorWorkspaceMode(Object? value) {
    if (value is! String) {
      return 'split';
    }
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'edit' || 'split' || 'preview' => normalized,
      _ => 'split',
    };
  }

  static String _readSubmitShortcut(Object? value) {
    return value == 'enter' ? 'enter' : defaultSubmitShortcut;
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
}

const Object _sentinel = Object();
