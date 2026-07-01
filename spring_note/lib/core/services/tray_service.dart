import 'package:flutter/services.dart';

import '../models/app_config.dart';
import 'platform_feature_support.dart';

class TrayService {
  const TrayService([this._channel = const MethodChannel('spring_note/tray')]);

  final MethodChannel _channel;

  Future<void> sync(AppConfig config) async {
    if (!PlatformFeatureSupport.supportsTray) {
      return;
    }

    final showTrayIcon = config.showTrayIcon;
    final closeToTray = showTrayIcon && config.closeToTray;
    try {
      await _channel.invokeMethod<void>('configure', {
        'showTrayIcon': showTrayIcon,
        'closeToTray': closeToTray,
      });
    } on PlatformException {
      // Tray integration is optional and platform-dependent.
    }
  }

  Future<void> dispose() async {
    if (!PlatformFeatureSupport.supportsTray) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('dispose');
    } on PlatformException {
      // Tray integration is optional and platform-dependent.
    }
  }

  Future<void> prepareForApplicationExit() async {
    if (!PlatformFeatureSupport.supportsTray) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('prepareForApplicationExit');
    } on PlatformException {
      // Tray integration is optional and platform-dependent.
    }
  }

  Future<void> quitForUpdate() async {
    if (!PlatformFeatureSupport.supportsTray) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('quitForUpdate');
    } on PlatformException {
      // Tray integration is optional and platform-dependent.
    }
  }
}
