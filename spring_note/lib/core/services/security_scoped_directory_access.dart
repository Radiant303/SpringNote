import 'dart:io';

import 'package:flutter/services.dart';

abstract class SecurityScopedDirectoryAccess {
  const SecurityScopedDirectoryAccess();

  Future<bool> saveBookmark(String path) async {
    return true;
  }

  Future<bool> startAccessing(String path) async {
    return true;
  }

  Future<void> removeBookmark(String path) async {}
}

class MethodChannelSecurityScopedDirectoryAccess
    extends SecurityScopedDirectoryAccess {
  const MethodChannelSecurityScopedDirectoryAccess([
    this._channel = const MethodChannel(
      'spring_note/security_scoped_directories',
    ),
  ]);

  final MethodChannel _channel;

  @override
  Future<bool> saveBookmark(String path) async {
    if (!Platform.isMacOS) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('saveBookmark', path) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> startAccessing(String path) async {
    if (!Platform.isMacOS) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('startAccessing', path) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> removeBookmark(String path) async {
    if (!Platform.isMacOS) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('removeBookmark', path);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
