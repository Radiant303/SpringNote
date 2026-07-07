import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../services/desktop_window_controller.dart';
import '../theme/app_theme.dart';
import '../theme/context_extensions.dart';

class AppWindowFrame extends StatelessWidget {
  const AppWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DesktopWindowController.supportsCustomTitleBar) {
      return child;
    }

    return Column(
      children: [
        const AppWindowTitleBar(),
        Expanded(child: child),
      ],
    );
  }
}

class AppWindowTitleBar extends StatefulWidget {
  const AppWindowTitleBar({super.key});

  static const double height = 40;

  @override
  State<AppWindowTitleBar> createState() => _AppWindowTitleBarState();
}

class _AppWindowTitleBarState extends State<AppWindowTitleBar>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadWindowState();
  }

  Future<void> _loadWindowState() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() => _maximized = maximized);
      }
    } catch (_) {
      // Window manager is Windows-only here; ignore startup races.
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() => _maximized = true);
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() => _maximized = false);
    }
  }

  @override
  void onWindowRestore() {
    _loadWindowState();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: context.appTextSecondary,
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      height: 1,
      decoration: TextDecoration.none,
    );

    return ColoredBox(
      color: context.appBg,
      child: SizedBox(
        height: AppWindowTitleBar.height,
        child: Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: SizedBox.expand(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'windows/runner/resources/index.png',
                            width: 17,
                            height: 17,
                            filterQuality: FilterQuality.medium,
                          ),
                          const SizedBox(width: 8),
                          Text('SpringNote', style: textStyle),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            WindowCaptionButton.minimize(
              brightness: brightness,
              onPressed: () => windowManager.minimize(),
            ),
            if (_maximized)
              WindowCaptionButton.unmaximize(
                brightness: brightness,
                onPressed: () => windowManager.unmaximize(),
              )
            else
              WindowCaptionButton.maximize(
                brightness: brightness,
                onPressed: () => windowManager.maximize(),
              ),
            WindowCaptionButton.close(
              brightness: brightness,
              onPressed: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}
