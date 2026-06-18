class AppConfig {
  const AppConfig({
    required this.dailyWorkHours,
    required this.dailySalary,
    required this.industry,
    required this.appFont,
    required this.fontScale,
    required this.autoStart,
    required this.showUpdates,
    required this.showDesktopWidget,
    required this.providers,
    required this.defaultModels,
    required this.hotkeys,
  });

  final double dailyWorkHours;
  final double dailySalary;
  final String industry;
  final String appFont;
  final double fontScale;
  final bool autoStart;
  final bool showUpdates;
  final bool showDesktopWidget;
  final List<Map<String, Object?>> providers;
  final Map<String, String?> defaultModels;
  final Map<String, String?> hotkeys;

  factory AppConfig.defaults() {
    return const AppConfig(
      dailyWorkHours: 8,
      dailySalary: 200,
      industry: '互联网',
      appFont: 'system',
      fontScale: 100,
      autoStart: false,
      showUpdates: true,
      showDesktopWidget: true,
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
      autoStart: json['autoStart'] as bool? ?? false,
      showUpdates: json['showUpdates'] as bool? ?? true,
      showDesktopWidget: json['showDesktopWidget'] as bool? ?? true,
      providers: _readMapList(json['providers']),
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
      'autoStart': autoStart,
      'showUpdates': showUpdates,
      'showDesktopWidget': showDesktopWidget,
      'providers': providers,
      'defaultModels': defaultModels,
      'hotkeys': hotkeys,
    };
  }

  static double _readDouble(Object? value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }

  static List<Map<String, Object?>> _readMapList(Object? value) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map(
          (entry) => entry.map((key, value) => MapEntry(key.toString(), value)),
        )
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
