part of 'settings_page.dart';

class _HotkeysPanel extends StatelessWidget {
  const _HotkeysPanel({required this.config, required this.onChanged});

  final AppConfig config;
  final ValueChanged<AppConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final toggleWindow = config.hotkeys['toggleWindow'] ?? '';
    final hotkeysSupported = PlatformFeatureSupport.supportsGlobalHotkeys;
    final toggleWindowEnabled =
        hotkeysSupported && toggleWindow.trim().isNotEmpty;
    final submitShortcut = Platform.isMacOS ? 'Cmd+Enter' : 'Ctrl+Enter';
    return _SettingsScrollFrame(
      maxWidth: 1120,
      children: [
        _SettingsCard(
          title: '全局快捷键',
          children: [
            _TextSettingRow(
              label: '显示/隐藏页面',
              value: toggleWindow,
              enabled: hotkeysSupported,
              description: hotkeysSupported ? null : _platformFeatureMessage(),
              validator: _validateGlobalHotkey,
              onChanged: hotkeysSupported
                  ? (value) {
                      final hotkeys = Map<String, String?>.from(config.hotkeys);
                      hotkeys['toggleWindow'] = value;
                      onChanged(config.copyWith(hotkeys: hotkeys));
                    }
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 4),
                  _HotkeyActionButton(
                    tooltip: '重置',
                    icon: Icons.restart_alt_rounded,
                    onPressed: hotkeysSupported
                        ? () {
                            final hotkeys = Map<String, String?>.from(
                              config.hotkeys,
                            );
                            hotkeys['toggleWindow'] = 'Ctrl+Shift+S';
                            onChanged(config.copyWith(hotkeys: hotkeys));
                          }
                        : null,
                  ),
                  _HotkeyActionButton(
                    tooltip: '清除',
                    icon: Icons.close_rounded,
                    onPressed: hotkeysSupported
                        ? () {
                            final hotkeys = Map<String, String?>.from(
                              config.hotkeys,
                            );
                            hotkeys['toggleWindow'] = '';
                            onChanged(config.copyWith(hotkeys: hotkeys));
                          }
                        : null,
                  ),
                  Switch(
                    value: toggleWindowEnabled,
                    onChanged: hotkeysSupported
                        ? (enabled) {
                            final hotkeys = Map<String, String?>.from(
                              config.hotkeys,
                            );
                            hotkeys['toggleWindow'] = enabled
                                ? (toggleWindow.trim().isEmpty
                                      ? 'Ctrl+Shift+S'
                                      : toggleWindow.trim())
                                : '';
                            onChanged(config.copyWith(hotkeys: hotkeys));
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
        _SettingsCard(
          title: '输入快捷键',
          children: [
            _ShortcutSettingRow(label: '首页快速输入', shortcut: submitShortcut),
            _ShortcutSettingRow(label: '回忆书对话输入', shortcut: submitShortcut),
          ],
        ),
      ],
    );
  }
}

String? _validateGlobalHotkey(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || _isValidGlobalHotkey(trimmed)) {
    return null;
  }
  return '请输入类似 Ctrl+Shift+S 的组合键';
}

bool _isValidGlobalHotkey(String value) {
  final tokens = value
      .split('+')
      .map((token) => token.trim().toUpperCase())
      .where((token) => token.isNotEmpty)
      .toList();
  if (tokens.length < 2) {
    return false;
  }

  var hasModifier = false;
  var keyCount = 0;
  for (final token in tokens) {
    if (_isGlobalHotkeyModifier(token)) {
      hasModifier = true;
      continue;
    }
    if (!_isGlobalHotkeyKey(token)) {
      return false;
    }
    keyCount += 1;
    if (keyCount > 1) {
      return false;
    }
  }

  return hasModifier && keyCount == 1;
}

bool _isGlobalHotkeyModifier(String token) {
  return switch (token) {
    'CTRL' ||
    'CONTROL' ||
    'SHIFT' ||
    'ALT' ||
    'OPTION' ||
    'WIN' ||
    'WINDOWS' ||
    'META' ||
    'CMD' ||
    'COMMAND' ||
    'SUPER' => true,
    _ => false,
  };
}

bool _isGlobalHotkeyKey(String token) {
  if (token.length == 1) {
    final code = token.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 48 && code <= 57);
  }

  if (token.startsWith('F')) {
    final number = int.tryParse(token.substring(1));
    final maxFunctionKey = Platform.isMacOS ? 20 : 24;
    if (number != null && number >= 1 && number <= maxFunctionKey) {
      return true;
    }
  }

  final commonKeys = {
    'SPACE',
    'TAB',
    'ENTER',
    'RETURN',
    'ESC',
    'ESCAPE',
    'BACKSPACE',
    'DELETE',
    'DEL',
    'HOME',
    'END',
    'PAGEUP',
    'PGUP',
    'PAGEDOWN',
    'PGDN',
    'UP',
    'DOWN',
    'LEFT',
    'RIGHT',
  };
  if (!Platform.isMacOS) {
    commonKeys.addAll({'INSERT', 'INS'});
  }
  return commonKeys.contains(token);
}

class _HotkeyActionButton extends StatefulWidget {
  const _HotkeyActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<_HotkeyActionButton> createState() => _HotkeyActionButtonState();
}

class _HotkeyActionButtonState extends State<_HotkeyActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final active = enabled && _hovered;
    const backgroundColor = Color(0xFFF5F5F5);
    final iconColor = !enabled
        ? const Color(0xFFBDBDBD)
        : (active ? AppTheme.text : AppTheme.textSubtle);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) {
          if (enabled) {
            setState(() => _hovered = true);
          }
        },
        onExit: (_) {
          if (_hovered) {
            setState(() => _hovered = false);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    opacity: active ? 1 : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                Icon(
                  widget.icon,
                  size: 16,
                  color: iconColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
