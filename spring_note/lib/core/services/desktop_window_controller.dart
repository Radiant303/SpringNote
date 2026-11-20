import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowController {
  const DesktopWindowController._();

  static const Size defaultSize = Size(1280, 832);
  static const Size minimumSize = Size(960, 640);

  static bool get supportsWindowManager {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
  }

  static bool get supportsCustomTitleBar {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  }

  static Future<void> initializeAndShow({String title = 'SpringNote'}) async {
    if (!supportsWindowManager) {
      return;
    }

    await windowManager.ensureInitialized();
    final options = WindowOptions(
      size: defaultSize,
      minimumSize: minimumSize,
      center: true,
      title: title,
      titleBarStyle: supportsCustomTitleBar
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: supportsCustomTitleBar ? false : null,
      backgroundColor: const Color(0xFFFCFCFC),
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}
