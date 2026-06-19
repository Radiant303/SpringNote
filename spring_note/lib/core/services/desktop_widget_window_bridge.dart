import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DesktopWidgetWindowSnapshot {
  const DesktopWidgetWindowSnapshot({
    required this.running,
    required this.workSeconds,
    required this.coins,
    required this.coinRatePerSecond,
    required this.level,
    required this.experiencePercent,
    required this.progress,
  });

  final bool running;
  final int workSeconds;
  final double coins;
  final double coinRatePerSecond;
  final int level;
  final int experiencePercent;
  final double progress;

  Map<String, Object?> toJson() {
    return {
      'running': running,
      'workSeconds': workSeconds,
      'coins': coins,
      'coinRatePerSecond': coinRatePerSecond,
      'level': level,
      'experiencePercent': experiencePercent,
      'progress': progress,
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
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  }

  Future<void> initialize({
    required VoidCallback onToggle,
    required VoidCallback onOpenHome,
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
