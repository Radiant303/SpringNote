import 'desktop_widget_position.dart';
import 'provider_config.dart';

class AppConfig {
  const AppConfig({
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
    required this.showTrayIcon,
    required this.closeToTray,
    required this.memorySearchLimit,
    required this.apiLogEnabled,
    required this.providers,
    required this.defaultModels,
    required this.hotkeys,
  });

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
  final bool showTrayIcon;
  final bool closeToTray;
  final double memorySearchLimit;
  final bool apiLogEnabled;
  final List<ProviderConfig> providers;
  final Map<String, String?> defaultModels;
  final Map<String, String?> hotkeys;

  factory AppConfig.defaults() {
    return const AppConfig(
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
      showTrayIcon: true,
      closeToTray: true,
      memorySearchLimit: 3,
      apiLogEnabled: false,
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
      showTrayIcon: json['showTrayIcon'] as bool? ?? true,
      closeToTray:
          (json['showTrayIcon'] as bool? ?? true) &&
          (json['closeToTray'] as bool? ?? true),
      memorySearchLimit: _readDouble(json['memorySearchLimit'], 3),
      apiLogEnabled: json['apiLogEnabled'] as bool? ?? false,
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
      'showTrayIcon': showTrayIcon,
      'closeToTray': closeToTray,
      'memorySearchLimit': memorySearchLimit,
      'apiLogEnabled': apiLogEnabled,
      'providers': providers.map((provider) => provider.toJson()).toList(),
      'defaultModels': defaultModels,
      'hotkeys': hotkeys,
    };
  }

  AppConfig copyWith({
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
    bool? showTrayIcon,
    bool? closeToTray,
    double? memorySearchLimit,
    bool? apiLogEnabled,
    List<ProviderConfig>? providers,
    Map<String, String?>? defaultModels,
    Map<String, String?>? hotkeys,
  }) {
    final nextShowTrayIcon = showTrayIcon ?? this.showTrayIcon;
    final nextCloseToTray =
        nextShowTrayIcon && (closeToTray ?? this.closeToTray);
    return AppConfig(
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
      showTrayIcon: nextShowTrayIcon,
      closeToTray: nextCloseToTray,
      memorySearchLimit: memorySearchLimit ?? this.memorySearchLimit,
      apiLogEnabled: apiLogEnabled ?? this.apiLogEnabled,
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
}

const Object _sentinel = Object();
