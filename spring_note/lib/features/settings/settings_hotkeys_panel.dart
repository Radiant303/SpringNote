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
    final defaultToggleWindow = AppConfig.defaultToggleWindowHotkey;
    final submitShortcut = Platform.isMacOS ? 'Cmd+Enter' : 'Ctrl+Enter';
    return _SettingsScrollFrame(
      maxWidth: 1120,
      children: [
        _SettingsCard(
          title: '全局快捷键',
          children: [
            _HotkeySettingRow(
              label: '显示/隐藏页面',
              value: toggleWindow,
              enabled: hotkeysSupported,
              description: hotkeysSupported ? null : _platformFeatureMessage(),
              onRecorded: hotkeysSupported
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
                            hotkeys['toggleWindow'] = defaultToggleWindow;
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
                                      ? defaultToggleWindow
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

class _HotkeySettingRow extends StatelessWidget {
  const _HotkeySettingRow({
    required this.label,
    required this.value,
    required this.onRecorded,
    this.enabled = true,
    this.description,
    this.trailing,
  });

  final String label;
  final String value;
  final ValueChanged<String>? onRecorded;
  final bool enabled;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: label,
      enabled: enabled,
      description: description,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            child: _HotkeyRecorderField(
              key: const ValueKey('toggle-window-hotkey-recorder'),
              value: value,
              enabled: enabled,
              onRecorded: onRecorded,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _HotkeyRecorderField extends StatefulWidget {
  const _HotkeyRecorderField({
    super.key,
    required this.value,
    required this.enabled,
    required this.onRecorded,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String>? onRecorded;

  @override
  State<_HotkeyRecorderField> createState() => _HotkeyRecorderFieldState();
}

class _HotkeyRecorderFieldState extends State<_HotkeyRecorderField> {
  late final FocusNode _focusNode = FocusNode()
    ..addListener(_handleFocusChange);
  bool _recording = false;
  String? _errorText;

  bool get _isMacOS => Platform.isMacOS;

  @override
  void didUpdateWidget(covariant _HotkeyRecorderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _recording) {
      _recording = false;
      _errorText = null;
      _focusNode.unfocus();
    }
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _recording && mounted) {
      setState(() {
        _recording = false;
        _errorText = null;
      });
    }
  }

  void _beginRecording() {
    if (!widget.enabled) {
      return;
    }
    setState(() {
      _recording = true;
      _errorText = null;
    });
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_recording) {
      return KeyEventResult.ignored;
    }

    if (_isModifierKey(event.logicalKey)) {
      setState(() => _errorText = null);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent || event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }

    final modifiers = _pressedModifierTokens(macOS: _isMacOS);
    if (event.logicalKey == LogicalKeyboardKey.escape && modifiers.isEmpty) {
      setState(() {
        _recording = false;
        _errorText = null;
      });
      _focusNode.unfocus();
      return KeyEventResult.handled;
    }

    final keyToken = _hotkeyTokenForKey(event.logicalKey, macOS: _isMacOS);
    if (keyToken == null) {
      setState(() => _errorText = '暂不支持这个按键');
      return KeyEventResult.handled;
    }
    if (modifiers.isEmpty) {
      setState(
        () => _errorText = _isMacOS
            ? '需包含 Cmd、Ctrl、Option 或 Shift'
            : '需包含 Ctrl、Alt、Shift 或 Win',
      );
      return KeyEventResult.handled;
    }

    final shortcut = [...modifiers, keyToken].join('+');
    widget.onRecorded?.call(shortcut);
    setState(() {
      _recording = false;
      _errorText = null;
    });
    _focusNode.unfocus();
    return KeyEventResult.handled;
  }

  String get _displayText {
    if (_recording) {
      if (_errorText case final error?) {
        return error;
      }
      final modifiers = _pressedModifierTokens(macOS: _isMacOS);
      return modifiers.isEmpty ? '请按下快捷键' : '${modifiers.join('+')}+…';
    }
    final value = widget.value.trim();
    return value.isEmpty ? '未设置' : _displayHotkey(value, macOS: _isMacOS);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final hasError = _recording && _errorText != null;
    final borderColor = hasError
        ? Theme.of(context).colorScheme.error
        : (_recording ? colors.textSubtle : colors.border);
    final textColor = !widget.enabled
        ? colors.textSubtle.withValues(alpha: 0.56)
        : (hasError ? Theme.of(context).colorScheme.error : colors.text);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _beginRecording,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: _recording ? colors.inputFocusedFill : colors.inputFill,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _displayText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: textColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (_recording && !hasError)
                  Icon(
                    Icons.keyboard_rounded,
                    size: 16,
                    color: colors.textSubtle,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<String> _pressedModifierTokens({required bool macOS}) {
  final keyboard = HardwareKeyboard.instance;
  final tokens = <String>[];
  if (macOS) {
    if (keyboard.isMetaPressed) tokens.add('Cmd');
    if (keyboard.isShiftPressed) tokens.add('Shift');
    if (keyboard.isAltPressed) tokens.add('Option');
    if (keyboard.isControlPressed) tokens.add('Ctrl');
  } else {
    if (keyboard.isControlPressed) tokens.add('Ctrl');
    if (keyboard.isShiftPressed) tokens.add('Shift');
    if (keyboard.isAltPressed) tokens.add('Alt');
    if (keyboard.isMetaPressed) tokens.add('Win');
  }
  return tokens;
}

bool _isModifierKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;
}

String? _hotkeyTokenForKey(LogicalKeyboardKey key, {required bool macOS}) {
  final label = key.keyLabel.toUpperCase();
  if (RegExp(r'^[A-Z0-9]$').hasMatch(label)) {
    return label;
  }

  final functionKeyIndex = _functionKeys.indexOf(key);
  final maxFunctionKey = macOS ? 20 : 24;
  if (functionKeyIndex >= 0 && functionKeyIndex < maxFunctionKey) {
    return 'F${functionKeyIndex + 1}';
  }

  if (!macOS && key == LogicalKeyboardKey.insert) return 'Insert';
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.tab) return 'Tab';
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    return 'Enter';
  }
  if (key == LogicalKeyboardKey.escape) return 'Esc';
  if (key == LogicalKeyboardKey.backspace) return 'Backspace';
  if (key == LogicalKeyboardKey.delete) return 'Delete';
  if (key == LogicalKeyboardKey.home) return 'Home';
  if (key == LogicalKeyboardKey.end) return 'End';
  if (key == LogicalKeyboardKey.pageUp) return 'PageUp';
  if (key == LogicalKeyboardKey.pageDown) return 'PageDown';
  if (key == LogicalKeyboardKey.arrowUp) return 'Up';
  if (key == LogicalKeyboardKey.arrowDown) return 'Down';
  if (key == LogicalKeyboardKey.arrowLeft) return 'Left';
  if (key == LogicalKeyboardKey.arrowRight) return 'Right';
  return null;
}

String _displayHotkey(String value, {required bool macOS}) {
  return value
      .split('+')
      .map((token) {
        final normalized = token.trim().toUpperCase();
        return switch (normalized) {
          'CONTROL' || 'CTRL' => 'Ctrl',
          'SHIFT' => 'Shift',
          'ALT' || 'OPTION' => macOS ? 'Option' : 'Alt',
          'WIN' ||
          'WINDOWS' ||
          'META' ||
          'CMD' ||
          'COMMAND' ||
          'SUPER' => macOS ? 'Cmd' : 'Win',
          'RETURN' || 'ENTER' => 'Enter',
          'ESCAPE' || 'ESC' => 'Esc',
          'DEL' || 'DELETE' => 'Delete',
          'INS' || 'INSERT' => 'Insert',
          'PGUP' || 'PAGEUP' => 'PageUp',
          'PGDN' || 'PAGEDOWN' => 'PageDown',
          _ => token.trim(),
        };
      })
      .where((token) => token.isNotEmpty)
      .join('+');
}

const _functionKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
  LogicalKeyboardKey.f13,
  LogicalKeyboardKey.f14,
  LogicalKeyboardKey.f15,
  LogicalKeyboardKey.f16,
  LogicalKeyboardKey.f17,
  LogicalKeyboardKey.f18,
  LogicalKeyboardKey.f19,
  LogicalKeyboardKey.f20,
  LogicalKeyboardKey.f21,
  LogicalKeyboardKey.f22,
  LogicalKeyboardKey.f23,
  LogicalKeyboardKey.f24,
];

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
    final colors = AppTheme.colors(context);
    final backgroundColor = colors.surfaceHover;
    final iconColor = !enabled
        ? colors.textSubtle.withValues(alpha: 0.56)
        : (active ? colors.text : colors.textSubtle);

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
                Icon(widget.icon, size: 16, color: iconColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
