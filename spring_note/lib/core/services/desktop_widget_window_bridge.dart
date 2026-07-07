import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/desktop_widget_position.dart';
import 'platform_feature_support.dart';

class DesktopWidgetWindowSnapshot {
  const DesktopWidgetWindowSnapshot({
    required this.running,
    required this.workSeconds,
    required this.coins,
    required this.coinRatePerSecond,
    required this.level,
    required this.experiencePercent,
    required this.progress,
    required this.appFont,
    required this.fontScaleFactor,
    required this.position,
    required this.orbMode,
    required this.darkMode,
    this.widgetWallpaperMode = 0,
    this.widgetWallpaperColor = 0xFFFFFFFF,
    this.widgetWallpaperImagePath,
    this.widgetWallpaperOpacity = 1.0,
  });

  final bool running;
  final int workSeconds;
  final double coins;
  final double coinRatePerSecond;
  final int level;
  final int experiencePercent;
  final double progress;
  final String appFont;
  final double fontScaleFactor;
  final DesktopWidgetPosition? position;
  final bool orbMode;
  final bool darkMode;
  final int widgetWallpaperMode;
  final int widgetWallpaperColor;
  final String? widgetWallpaperImagePath;
  final double widgetWallpaperOpacity;

  Map<String, Object?> toJson() {
    return {
      'running': running,
      'workSeconds': workSeconds,
      'coins': coins,
      'coinRatePerSecond': coinRatePerSecond,
      'level': level,
      'experiencePercent': experiencePercent,
      'progress': progress,
      'appFont': appFont,
      'fontScaleFactor': fontScaleFactor,
      'position': position?.toJson(),
      'orbMode': orbMode,
      'darkMode': darkMode,
      'widgetWallpaperMode': widgetWallpaperMode,
      'widgetWallpaperColor': widgetWallpaperColor,
      'widgetWallpaperImagePath': widgetWallpaperImagePath,
      'widgetWallpaperOpacity': widgetWallpaperOpacity,
    };
  }
}

class DesktopWidgetWindowBridge {
  DesktopWidgetWindowBridge([
    this._channel = const MethodChannel('spring_note/desktop_widget_window'),
  ]);

  final MethodChannel _channel;
  bool _initialized = false;

  bool get isSupported {
    return !kIsWeb && PlatformFeatureSupport.supportsDesktopWidget;
  }

  Future<void> initialize({
    required VoidCallback onToggle,
    required VoidCallback onOpenHome,
    required ValueChanged<DesktopWidgetPosition> onPositionChanged,
  }) async {
    if (!isSupported || _initialized) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'toggle':
          onToggle();
          return;
        case 'openHome':
          onOpenHome();
          return;
        case 'positionChanged':
          final position = DesktopWidgetPosition.fromJson(call.arguments);
          if (position != null) {
            onPositionChanged(position);
          }
          return;
      }
    });
  }

  Future<void> showOrUpdate(DesktopWidgetWindowSnapshot snapshot) async {
    if (!isSupported) {
      return;
    }
    await _safeInvoke('showOrUpdate', snapshot.toJson());
  }

  Future<void> hide() async {
    if (!isSupported) {
      return;
    }
    await _safeInvoke('hide');
  }

  Future<void> dispose() async {
    await hide();
    if (_initialized) {
      _channel.setMethodCallHandler(null);
      _initialized = false;
    }
  }

  Future<void> _safeInvoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Unit tests and non-Windows builds do not register the native runner.
    }
  }
}
