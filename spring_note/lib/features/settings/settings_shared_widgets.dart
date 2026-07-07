part of 'settings_page.dart';

class _SettingsScrollFrame extends StatelessWidget {
  const _SettingsScrollFrame({required this.children, required this.maxWidth});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(36, 30, 36, 42),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: child,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.children,
    this.titleAccessory,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? titleAccessory;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border.all(color: context.appBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (titleAccessory != null) ...[
                  const SizedBox(width: 8),
                  titleAccessory!,
                ],
                const Spacer(),
                ?trailing,
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _ActionSettingRow extends StatefulWidget {
  const _ActionSettingRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  State<_ActionSettingRow> createState() => _ActionSettingRowState();
}

class _ActionSettingRowState extends State<_ActionSettingRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered;
    final foreground = active
        ? context.appTextPrimary
        : context.appTextTertiary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.appBorder)),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    opacity: active ? 1 : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.appCardBgHover,
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(
                    end: active
                        ? context.appTextPrimary
                        : context.appTextPrimary,
                  ),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, color, _) {
                    final labelColor = color ?? context.appTextPrimary;
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.label,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(color: labelColor),
                          ),
                        ),
                        const SizedBox(width: 16),
                        if (widget.value.isNotEmpty) ...[
                          Flexible(
                            child: Text(
                              widget.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: foreground),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: foreground,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextSettingRow extends StatelessWidget {
  const _TextSettingRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.description,
    this.trailing,
    this.validator,
  });

  final String label;
  final String value;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final String? description;
  final Widget? trailing;
  final String? Function(String value)? validator;

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
            child: _CommittedTextField(
              value: value,
              enabled: enabled,
              onChanged: onChanged,
              validator: validator,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _SettingsMessage extends StatelessWidget {
  const _SettingsMessage({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: error
            ? (dark ? const Color(0xFF3B1119) : const Color(0xFFFFF1F2))
            : (dark ? const Color(0xFF0F2F1B) : const Color(0xFFF0FDF4)),
        border: Border.all(
          color: error
              ? (dark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA))
              : (dark ? const Color(0xFF166534) : const Color(0xFFBBF7D0)),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: error
              ? (dark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C))
              : (dark ? const Color(0xFF86EFAC) : const Color(0xFF166534)),
        ),
      ),
    );
  }
}

class _SettingsSearchField extends StatefulWidget {
  const _SettingsSearchField({
    required this.controller,
    required this.onChanged,
    required this.hintText,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final bool autofocus;

  @override
  State<_SettingsSearchField> createState() => _SettingsSearchFieldState();
}

class _SettingsSearchFieldState extends State<_SettingsSearchField> {
  late final FocusNode _focusNode = FocusNode()
    ..addListener(_handleFocusChanged);

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      height: 40,
      decoration: BoxDecoration(
        color: focused ? context.appCardBg : context.appCardBgHover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onChanged: widget.onChanged,
          textAlignVertical: TextAlignVertical.center,
          cursorHeight: 16,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.appTextPrimary,
            height: 1.2,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.appTextTertiary.withValues(alpha: 0.78),
              height: 1.2,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color: context.appTextTertiary,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            isDense: true,
            isCollapsed: true,
            filled: false,
            hoverColor: Colors.transparent,
            contentPadding: const EdgeInsets.only(right: 12),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

class _NumberSettingRow extends StatelessWidget {
  const _NumberSettingRow({
    required this.label,
    required this.value,
    required this.suffix,
    required this.onChanged,
    this.minValue,
    this.maxValue,
  });

  final String label;
  final double value;
  final String suffix;
  final ValueChanged<double> onChanged;
  final double? minValue;
  final double? maxValue;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 96,
            child: _BoundedNumberTextField(
              value: value,
              minValue: minValue,
              maxValue: maxValue,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 8),
          Text(suffix, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _BoundedNumberTextField extends StatefulWidget {
  const _BoundedNumberTextField({
    required this.value,
    required this.onChanged,
    this.minValue,
    this.maxValue,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double? minValue;
  final double? maxValue;

  @override
  State<_BoundedNumberTextField> createState() =>
      _BoundedNumberTextFieldState();
}

class _BoundedNumberTextFieldState extends State<_BoundedNumberTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: _formatNumber(widget.value),
  );

  @override
  void didUpdateWidget(covariant _BoundedNumberTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = _formatNumber(widget.value);
    if (widget.value != oldWidget.value && text != _controller.text) {
      _setText(text);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_DecimalNumberTextInputFormatter()],
      onChanged: _handleChanged,
      onSubmitted: _commit,
      onEditingComplete: () => _commit(_controller.text),
      decoration: const InputDecoration(isDense: true),
    );
  }

  void _handleChanged(String text) {
    final parsed = double.tryParse(text);
    if (parsed == null) {
      return;
    }

    final min = widget.minValue;
    if (min != null && parsed < min) {
      return;
    }

    final max = widget.maxValue;
    if (max != null && parsed > max) {
      _setText(_formatNumber(max));
      widget.onChanged(max);
      return;
    }

    widget.onChanged(parsed);
  }

  void _commit(String text) {
    final parsed = double.tryParse(text);
    if (parsed == null) {
      _setText(_formatNumber(widget.value));
      return;
    }
    final clamped = _clamp(parsed);
    _setText(_formatNumber(clamped));
    widget.onChanged(clamped);
  }

  double _clamp(double value) {
    final min = widget.minValue;
    final max = widget.maxValue;
    if (min != null && value < min) {
      return min;
    }
    if (max != null && value > max) {
      return max;
    }
    return value;
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }
}

class _DecimalNumberTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty || RegExp(r'^\d*\.?\d*$').hasMatch(text)) {
      return newValue;
    }
    return oldValue;
  }
}

class _SwitchSettingRow extends StatelessWidget {
  const _SwitchSettingRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.description,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: label,
      enabled: enabled,
      description: description,
      child: Switch(value: value, onChanged: enabled ? onChanged : null),
    );
  }
}

class _ChoiceSettingRow<T> extends StatelessWidget {
  const _ChoiceSettingRow({
    required this.label,
    required this.value,
    required this.options,
    required this.labels,
    required this.onChanged,
    this.description,
  });

  final String label;
  final T value;
  final List<T> options;
  final List<String> labels;
  final ValueChanged<T> onChanged;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: label,
      description: description,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: context.appCardBgHover,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < options.length; i++)
              _ChoicePill(
                label: labels[i],
                selected: options[i] == value,
                onTap: () => onChanged(options[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? context.appCardBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: context.appBorder)
                : Border.all(color: Colors.transparent),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: selected
                  ? context.appTextPrimary
                  : context.appTextSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutSettingRow extends StatelessWidget {
  const _ShortcutSettingRow({required this.label, required this.shortcut});

  final String label;
  final String shortcut;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: label,
      child: SizedBox(width: 220, child: _ShortcutKeyField(shortcut)),
    );
  }
}

class _ShortcutKeyField extends StatelessWidget {
  const _ShortcutKeyField(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border.all(color: context.appBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: context.appTextPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _SettingRowShell extends StatelessWidget {
  const _SettingRowShell({
    required this.label,
    required this.child,
    this.enabled = true,
    this.description,
  });

  final String label;
  final Widget child;
  final bool enabled;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.appBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: enabled
                        ? context.appTextPrimary
                        : context.appTextTertiary,
                  ),
                ),
                if (description != null && description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      description!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.appTextTertiary,
                        height: 1.15,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          child,
        ],
      ),
    );
  }
}

class _CommittedTextField extends StatefulWidget {
  const _CommittedTextField({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.obscureText = false,
    this.compact = false,
    this.validator,
  });

  final String value;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool obscureText;
  final bool compact;
  final String? Function(String value)? validator;

  @override
  State<_CommittedTextField> createState() => _CommittedTextFieldState();
}

class _CommittedTextFieldState extends State<_CommittedTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  String? _errorText;

  @override
  void didUpdateWidget(covariant _CommittedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
      _errorText = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      textAlignVertical: widget.compact ? TextAlignVertical.center : null,
      obscureText: widget.obscureText,
      onChanged: widget.enabled ? _handleChanged : null,
      onSubmitted: widget.enabled ? _handleChanged : null,
      onEditingComplete: widget.enabled && widget.onChanged != null
          ? () => _handleChanged(_controller.text)
          : null,
      decoration: widget.compact
          ? InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 9,
              ),
              constraints: const BoxConstraints.tightFor(height: 48),
              errorText: _errorText,
            )
          : InputDecoration(
              isDense: true,
              constraints: const BoxConstraints.tightFor(height: 42),
              errorText: _errorText,
            ),
    );
  }

  void _handleChanged(String value) {
    final errorText = widget.validator?.call(value);
    if (errorText != _errorText) {
      setState(() => _errorText = errorText);
    }
    if (errorText == null) {
      widget.onChanged?.call(value);
    }
  }
}

class _LooseField extends StatelessWidget {
  const _LooseField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.obscureText = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          _CommittedTextField(
            value: value,
            obscureText: obscureText,
            compact: true,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ProtocolField extends StatefulWidget {
  const _ProtocolField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_ProtocolField> createState() => _ProtocolFieldState();
}

class _ProtocolFieldState extends State<_ProtocolField> {
  final MenuController _controller = MenuController();
  bool _hovered = false;
  bool _menuOpen = false;

  static const Map<String, String> _protocols = {
    'openaiCompatible': 'OpenAI-compatible',
    'gemini': 'Gemini',
    'claude': 'Claude',
  };

  String get _current {
    final trimmedValue = widget.value.trim();
    return trimmedValue.isEmpty ? 'openaiCompatible' : trimmedValue;
  }

  List<MapEntry<String, String>> get _options {
    final current = _current;
    return [
      if (!_protocols.containsKey(current)) MapEntry(current, current),
      ..._protocols.entries,
    ];
  }

  void _toggleMenu() {
    if (_controller.isOpen) {
      _controller.close();
    } else {
      _controller.open();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final currentLabel = _protocols[current] ?? current;
    final options = _options;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('协议', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final menuWidth = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : 280.0;
              final menuHeight =
                  _ProtocolMenuSurface.verticalPadding * 2 +
                  _ProtocolMenuOption.itemHeight * options.length;
              return MenuAnchor(
                controller: _controller,
                alignmentOffset: const Offset(0, 6),
                style: MenuStyle(
                  backgroundColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  elevation: const WidgetStatePropertyAll(0),
                  minimumSize: const WidgetStatePropertyAll(Size.zero),
                  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                onOpen: () => setState(() => _menuOpen = true),
                onClose: () => setState(() => _menuOpen = false),
                menuChildren: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      final devicePixelRatio = MediaQuery.of(
                        context,
                      ).devicePixelRatio;
                      final rawOffset = (1 - value) * menuHeight * -0.06;
                      final physicalPixel = 1 / devicePixelRatio;
                      final dy = rawOffset.abs() <= physicalPixel
                          ? 0.0
                          : (rawOffset * devicePixelRatio).roundToDouble() /
                                devicePixelRatio;
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, dy),
                          child: child,
                        ),
                      );
                    },
                    child: _ProtocolMenuSurface(
                      width: menuWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final option in options)
                            _ProtocolMenuOption(
                              width: menuWidth,
                              label: option.value,
                              selected: option.key == current,
                              onTap: () {
                                _controller.close();
                                widget.onChanged(option.key);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                builder: (context, controller, child) {
                  final active = _hovered || _menuOpen;
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hovered = true),
                    onExit: (_) => setState(() => _hovered = false),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleMenu,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 130),
                        curve: Curves.easeOutCubic,
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: active
                              ? context.appCardBgHover
                              : context.appCardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _menuOpen
                                ? context.appTextTertiary
                                : context.appBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                currentLabel,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: context.appTextPrimary,
                                      fontWeight: FontWeight.w400,
                                      height: 1.2,
                                    ),
                              ),
                            ),
                            AnimatedRotation(
                              turns: _menuOpen ? 0.5 : 0,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              child: Icon(
                                Icons.expand_more_rounded,
                                size: 19,
                                color: context.appTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProtocolMenuSurface extends StatelessWidget {
  const _ProtocolMenuSurface({required this.width, required this.child});

  static const double verticalPadding = 4;

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: verticalPadding),
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border.all(color: context.appBorder),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0x05000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0x05000000).withValues(alpha: 0.12),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ProtocolMenuOption extends StatefulWidget {
  const _ProtocolMenuOption({
    required this.width,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  static const double itemHeight = 38;

  final double width;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ProtocolMenuOption> createState() => _ProtocolMenuOptionState();
}

class _ProtocolMenuOptionState extends State<_ProtocolMenuOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;
    final backgroundColor = widget.selected
        ? context.appCardBgHover
        : context.appCardBgHover;
    final contentColor = active
        ? context.appTextPrimary
        : context.appTextSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          height: _ProtocolMenuOption.itemHeight,
          child: Stack(
            children: [
              Positioned.fill(
                left: 6,
                right: 6,
                top: 2,
                bottom: 2,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  opacity: active ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          widget.label,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: contentColor,
                                fontWeight: FontWeight.w400,
                                height: 1.2,
                              ),
                        ),
                      ),
                      if (widget.selected)
                        Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: context.appTextPrimary,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleRow extends StatelessWidget {
  const _SimpleRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: label,
      child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled
            ? (Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF123522)
                  : const Color(0xFFDCFCE7))
            : (Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF3B2714)
                  : const Color(0xFFFFEDD5)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.appBorder),
      ),
      child: Text(
        enabled ? '启用' : '禁用',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: enabled ? const Color(0xFF16A34A) : const Color(0xFFF97316),
          fontSize: 11,
          height: 1,
        ),
      ),
    );
  }
}

class _EmptyProviderDetails extends StatelessWidget {
  const _EmptyProviderDetails();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '添加供应商后在这里编辑配置',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.child,
    required this.width,
  });

  final String title;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.appCardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: context.appTextPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogTextField extends StatelessWidget {
  const _DialogTextField({
    super.key,
    required this.label,
    required this.controller,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: context.appTextPrimary,
          height: 1.25,
        ),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _DialogSwitchRow extends StatelessWidget {
  const _DialogSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: context.appCardBgHover,
        border: Border.all(color: context.appBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.appTextPrimary),
          ),
          const Spacer(),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 滑块设置行（双端标签 + 当前值）。
class _SliderSettingRow extends StatelessWidget {
  const _SliderSettingRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.suffix = '',
    this.enabled = true,
    this.valueFormatter,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String suffix;
  final bool enabled;
  final ValueChanged<double> onChanged;

  /// 自定义值格式化；默认显示百分比。
  final String Function(double v)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    final displayValue = valueFormatter != null
        ? valueFormatter!(value)
        : '${(value * 100).round()}%';
    return _SettingRowShell(
      label: label,
      enabled: enabled,
      child: SizedBox(
        width: 240,
        child: Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: context.appTextPrimary,
                  inactiveTrackColor: context.appBorder,
                  thumbColor: context.appTextPrimary,
                  overlayColor: context.appTextPrimary.withOpacity(0.08),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: enabled ? onChanged : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: Text(
                displayValue,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.appTextSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 颜色选择行（点击后弹出原生颜色选择器）。
class _ColorSettingRow extends StatelessWidget {
  const _ColorSettingRow({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  Future<void> _pickColor(BuildContext context) async {
    final result = await showModalBottomSheet<Color>(
      context: context,
      backgroundColor: context.appCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _ColorPickerSheet(current: color),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _pickColor(context),
          child: Container(
            width: 44,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.appBorder),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorPickerSheet extends StatelessWidget {
  const _ColorPickerSheet({required this.current});

  final Color current;

  static const _palette = <Color>[
    Color(0xFFF1FAEF),
    Color(0xFFFFFFFF),
    Color(0xFFE2E8F0),
    Color(0xFFFCE7F3),
    Color(0xFFFEF3C7),
    Color(0xFFDCFCE7),
    Color(0xFFE0E7FF),
    Color(0xFFFEE2E2),
    Color(0xFF1F2024),
    Color(0xFF121316),
    Color(0xFF0F172A),
    Color(0xFF1E293B),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('选择颜色', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: c.value == current.value
                              ? context.appTextPrimary
                              : context.appBorder,
                          width: c.value == current.value ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 实时壁纸预览条。
class _WallpaperPreview extends StatelessWidget {
  const _WallpaperPreview({
    required this.settings,
    required this.dataDirectory,
  });

  final WallpaperSettings settings;
  final String dataDirectory;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: context.appBgSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (settings.mode == WallpaperMode.image)
            _previewImage()
          else if (settings.mode == WallpaperMode.solid)
            Container(color: Color(settings.solidColorArgb))
          else
            DefaultGreenWallpaper(showLeaves: !context.appIsDark),
          if (settings.maskOpacity > 0)
            Container(
              color: context.appBg.withOpacity(
                settings.maskOpacity.clamp(0.0, 1.0),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: settings.transparentControls
                    ? context.appCardBg.withOpacity(
                        settings.controlAlpha.clamp(0.0, 1.0),
                      )
                    : context.appCardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: context.appBorder.withOpacity(
                    settings.showBorders ? 1.0 : 0.0,
                  ),
                ),
              ),
              child: Text(
                '预览 · ${_modeLabel(settings.mode)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.appTextSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewImage() {
    final abs = WallpaperService.resolveAbsolutePath(
      settings: settings,
      dataDirectory: dataDirectory,
    );
    if (abs == null) return DefaultGreenWallpaper(showLeaves: false);
    // Use Image.file directly with errorBuilder instead of a FutureBuilder
    // around file.exists(). The previous implementation allocated a new
    // Future<bool> on every build, which re-ran the existence check (and
    // triggered a setState) on every parent rebuild — including harmless
    // ones like theme toggles and scroll-driven rebuilds. Image.file caches
    // the resolved file internally and only re-decodes when the path
    // actually changes; errorBuilder handles the missing-file fallback in
    // a single pass. This mirrors the pattern in wallpaper_layer.dart.
    return Image.file(
      File(abs),
      fit: WallpaperService.toBoxFit(settings.fillMode),
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => DefaultGreenWallpaper(showLeaves: false),
    );
  }

  static String _modeLabel(WallpaperMode mode) {
    switch (mode) {
      case WallpaperMode.defaultBg:
        return '默认绿叶';
      case WallpaperMode.image:
        return '本地图片';
      case WallpaperMode.solid:
        return '纯色';
    }
  }
}
