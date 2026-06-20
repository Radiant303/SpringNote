import 'dart:io';

import 'package:flutter/services.dart';

class AutoStartService {
  const AutoStartService([
    this._channel = const MethodChannel('spring_note/auto_start'),
  ]);

  final MethodChannel _channel;

  Future<bool> setEnabled(bool enabled) async {
    if (!Platform.isWindows) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('setEnabled', enabled) ?? false;
    } on PlatformException {
      return false;
    }
  }
}
