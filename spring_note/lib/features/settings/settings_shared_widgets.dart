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
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
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
    final foreground = active ? AppTheme.text : AppTheme.textSubtle;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
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
                        color: const Color(0xFFF0F0F0),
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
                    end: active ? AppTheme.text : AppTheme.text,
                  ),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, color, _) {
                    final labelColor = color ?? AppTheme.text;
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFF1F2) : const Color(0xFFF0FDF4),
        border: Border.all(
          color: error ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: error ? const Color(0xFFB91C1C) : const Color(0xFF166534),
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
        color: focused ? const Color(0xFFE2E2E2) : const Color(0xFFEDEDED),
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
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.text, height: 1.2),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSubtle.withValues(alpha: 0.78),
              height: 1.2,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 18,
              color: Color(0xFF8A8A8A),
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
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppTheme.text,
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
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
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
                    color: enabled ? AppTheme.text : AppTheme.textSubtle,
                  ),
                ),
                if (description != null && description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      description!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSubtle,
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
          : InputDecoration(isDense: true, errorText: _errorText),
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

class _ProtocolField extends StatelessWidget {
  const _ProtocolField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const protocols = {
      'openaiCompatible': 'OpenAI-compatible',
      'gemini': 'Gemini',
      'claude': 'Claude',
    };
    final trimmedValue = value.trim();
    final current = trimmedValue.isEmpty ? 'openaiCompatible' : trimmedValue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('协议', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: current,
            items: [
              if (!protocols.containsKey(current))
                DropdownMenuItem(value: current, child: Text(current)),
              for (final entry in protocols.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (next) {
              if (next != null) {
                onChanged(next);
              }
            },
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              constraints: BoxConstraints.tightFor(height: 48),
            ),
          ),
        ],
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
        color: enabled ? const Color(0xFFDCFCE7) : const Color(0xFFFFEDD5),
        borderRadius: BorderRadius.circular(999),
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
      backgroundColor: Colors.white,
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
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
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
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(label),
          const Spacer(),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
