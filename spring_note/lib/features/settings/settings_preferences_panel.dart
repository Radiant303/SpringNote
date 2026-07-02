part of 'settings_page.dart';

class _PreferencesPanel extends StatelessWidget {
  const _PreferencesPanel({
    required this.config,
    required this.onChanged,
    required this.dataDirectory,
    required this.configPath,
    required this.appDataDir,
    required this.aiClientService,
    required this.saving,
    required this.errorMessage,
    required this.onDataDirectoryChanged,
  });

  final AppConfig config;
  final ValueChanged<AppConfig> onChanged;
  final String dataDirectory;
  final String configPath;
  final String appDataDir;
  final AiClientService aiClientService;
  final bool saving;
  final String? errorMessage;
  final ValueChanged<String?> onDataDirectoryChanged;

  @override
  Widget build(BuildContext context) {
    final windowsOnlyLabel = _platformFeatureMessage();
    return _SettingsScrollFrame(
      maxWidth: 1080,
      children: [
        _SettingsCard(
          title: '个人信息',
          children: [
            _NumberSettingRow(
              label: '每日工作时长',
              value: config.dailyWorkHours,
              suffix: '小时',
              onChanged: (value) =>
                  onChanged(config.copyWith(dailyWorkHours: value)),
            ),
            _NumberSettingRow(
              label: '日薪',
              value: config.dailySalary,
              suffix: '¥',
              onChanged: (value) =>
                  onChanged(config.copyWith(dailySalary: value)),
            ),
            _TextSettingRow(
              label: '所在行业',
              value: config.industry,
              onChanged: (value) => onChanged(config.copyWith(industry: value)),
            ),
          ],
        ),
        _SettingsCard(
          title: '字体与显示',
          children: [
            _FontSettingRow(
              label: '应用字体',
              value: config.appFont,
              onChanged: (value) => onChanged(config.copyWith(appFont: value)),
            ),
            _NumberSettingRow(
              label: '字体大小',
              value: config.fontScale,
              suffix: '%',
              minValue: 80,
              maxValue: 140,
              onChanged: (value) =>
                  onChanged(config.copyWith(fontScale: value)),
            ),
          ],
        ),
        _SettingsCard(
          title: '行为与启动',
          children: [
            _SwitchSettingRow(
              label: '开机自启动',
              value: config.autoStart,
              enabled: PlatformFeatureSupport.supportsAutoStart,
              description: PlatformFeatureSupport.supportsAutoStart
                  ? null
                  : windowsOnlyLabel,
              onChanged: PlatformFeatureSupport.supportsAutoStart
                  ? (value) => onChanged(config.copyWith(autoStart: value))
                  : null,
            ),
            _SwitchSettingRow(
              label: '显示更新',
              value: config.showUpdates,
              onChanged: (value) =>
                  onChanged(config.copyWith(showUpdates: value)),
            ),
            _SwitchSettingRow(
              label: '记录 API 网络日志',
              value: config.apiLogEnabled,
              onChanged: (value) =>
                  onChanged(config.copyWith(apiLogEnabled: value)),
            ),
          ],
        ),
        _SettingsCard(
          title: '托盘',
          children: [
            _SwitchSettingRow(
              label: '显示托盘图标',
              value: PlatformFeatureSupport.supportsTray && config.showTrayIcon,
              enabled: PlatformFeatureSupport.supportsTray,
              description: PlatformFeatureSupport.supportsTray
                  ? null
                  : windowsOnlyLabel,
              onChanged: PlatformFeatureSupport.supportsTray
                  ? (value) => onChanged(
                      config.copyWith(
                        showTrayIcon: value,
                        closeToTray: value ? config.closeToTray : false,
                      ),
                    )
                  : null,
            ),
            _SwitchSettingRow(
              label: '关闭时最小化到托盘',
              value:
                  PlatformFeatureSupport.supportsTray &&
                  config.showTrayIcon &&
                  config.closeToTray,
              enabled:
                  PlatformFeatureSupport.supportsTray && config.showTrayIcon,
              description: PlatformFeatureSupport.supportsTray
                  ? null
                  : windowsOnlyLabel,
              onChanged:
                  PlatformFeatureSupport.supportsTray && config.showTrayIcon
                  ? (value) => onChanged(config.copyWith(closeToTray: value))
                  : null,
            ),
          ],
        ),
        _SettingsCard(
          title: '数据保存',
          children: [
            _DataDirectorySettingRow(
              dataDirectory: dataDirectory,
              defaultDirectory: config.customDataDirectory == null,
              saving: saving,
              onChanged: onDataDirectoryChanged,
            ),
          ],
        ),
        _SettingsCard(
          title: '组件设置',
          children: [
            _SwitchSettingRow(
              label: '显示桌面组件',
              value:
                  PlatformFeatureSupport.supportsDesktopWidget &&
                  config.showDesktopWidget,
              enabled: PlatformFeatureSupport.supportsDesktopWidget,
              description: PlatformFeatureSupport.supportsDesktopWidget
                  ? null
                  : windowsOnlyLabel,
              onChanged: PlatformFeatureSupport.supportsDesktopWidget
                  ? (value) =>
                        onChanged(config.copyWith(showDesktopWidget: value))
                  : null,
            ),
            _SwitchSettingRow(
              label: '桌面组件圆球模式',
              value:
                  PlatformFeatureSupport.supportsDesktopWidget &&
                  config.showDesktopWidget &&
                  config.desktopWidgetOrbMode,
              enabled:
                  PlatformFeatureSupport.supportsDesktopWidget &&
                  config.showDesktopWidget,
              description: PlatformFeatureSupport.supportsDesktopWidget
                  ? null
                  : windowsOnlyLabel,
              onChanged:
                  PlatformFeatureSupport.supportsDesktopWidget &&
                      config.showDesktopWidget
                  ? (value) =>
                        onChanged(config.copyWith(desktopWidgetOrbMode: value))
                  : null,
            ),
          ],
        ),
        _SettingsCard(
          title: '提示词',
          children: [
            _ActionSettingRow(
              label: '日报整理提示词',
              value: '',
              onTap: () async {
                final prompt = await showDialog<String>(
                  context: context,
                  builder: (_) => _DailyMergePromptDialog(
                    appDataDir: appDataDir,
                    config: config,
                    aiClientService: aiClientService,
                  ),
                );
                if (prompt != null) {
                  onChanged(config.copyWith(dailyMergePrompt: prompt));
                }
              },
            ),
          ],
        ),
        _SettingsCard(
          title: '回忆书检索',
          children: [
            _NumberSettingRow(
              label: '回忆书单轮最大搜索次数',
              value: config.memorySearchLimit,
              suffix: '次',
              minValue: 1,
              maxValue: 120,
              onChanged: (value) =>
                  onChanged(config.copyWith(memorySearchLimit: value)),
            ),
            _NumberSettingRow(
              label: '单条结果返回最大字符数',
              value: config.memoryResultMaxCharacters,
              suffix: '字',
              minValue: 80,
              maxValue: 10000,
              onChanged: (value) =>
                  onChanged(config.copyWith(memoryResultMaxCharacters: value)),
            ),
            _NumberSettingRow(
              label: '连续日报读取最大数量',
              value: config.memoryWeekDailyNoteLimit,
              suffix: '条',
              minValue: 1,
              maxValue: 31,
              onChanged: (value) =>
                  onChanged(config.copyWith(memoryWeekDailyNoteLimit: value)),
            ),
            _NumberSettingRow(
              label: '关键词搜索结果最大数量',
              value: config.memoryKeywordSearchResultLimit,
              suffix: '条',
              minValue: 1,
              maxValue: 200,
              onChanged: (value) => onChanged(
                config.copyWith(memoryKeywordSearchResultLimit: value),
              ),
            ),
            _NumberSettingRow(
              label: '命中关键词截取前最大字符数',
              value: config.memoryKeywordContextBefore,
              suffix: '字',
              minValue: 0,
              maxValue: 4000,
              onChanged: (value) =>
                  onChanged(config.copyWith(memoryKeywordContextBefore: value)),
            ),
            _NumberSettingRow(
              label: '命中关键词截取后最大字符数',
              value: config.memoryKeywordContextAfter,
              suffix: '字',
              minValue: 0,
              maxValue: 6000,
              onChanged: (value) =>
                  onChanged(config.copyWith(memoryKeywordContextAfter: value)),
            ),
          ],
        ),
        if (errorMessage != null)
          _SettingsMessage(text: errorMessage!, error: true),
        Text(
          '配置文件：$configPath',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSubtle),
        ),
      ],
    );
  }
}

String _platformFeatureMessage() {
  if (Platform.isWindows) {
    return '';
  }
  return '当前平台暂不支持';
}

class _DataMigrationCompleteDialog extends StatelessWidget {
  const _DataMigrationCompleteDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const ValueKey('data-migration-complete-dialog'),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _DataMigrationSuccessIcon(),
              const SizedBox(height: 10),
              Text(
                '数据迁移完成',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '已成功切换至新的数据目录。\n确认数据正常后，可删除原目录以释放存储空间。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSubtle,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _DataMigrationDialogButton(
                label: '确定',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DataMigrationSuccessIcon extends StatelessWidget {
  const _DataMigrationSuccessIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: CustomPaint(painter: _DataMigrationSuccessIconPainter()),
    );
  }
}

class _DataMigrationSuccessIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final backgroundPaint = Paint()
      ..color = const Color(0xFFF5F5F5)
      ..style = PaintingStyle.fill;
    final ringPaint = Paint()
      ..color = const Color(0xFFE2E2E2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final checkPaint = Paint()
      ..color = AppTheme.text
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawCircle(center, radius - 0.6, backgroundPaint);
    canvas.drawCircle(center, radius - 1.2, ringPaint);

    final checkPath = Path()
      ..moveTo(size.width * 0.31, size.height * 0.52)
      ..lineTo(size.width * 0.45, size.height * 0.66)
      ..lineTo(size.width * 0.70, size.height * 0.38);
    canvas.drawPath(checkPath, checkPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DataMigrationDialogButton extends StatefulWidget {
  const _DataMigrationDialogButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_DataMigrationDialogButton> createState() =>
      _DataMigrationDialogButtonState();
}

class _DataMigrationDialogButtonState
    extends State<_DataMigrationDialogButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _pressed
        ? const Color(0xFF202020)
        : (_hovered ? const Color(0xFF2A2A2A) : Colors.black);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.975 : 1,
          duration: _pressed
              ? const Duration(milliseconds: 70)
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOutCubic,
            height: 36,
            width: 88,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Center(
              child: Text(
                widget.label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyMergePromptDialog extends StatefulWidget {
  const _DailyMergePromptDialog({
    required this.appDataDir,
    required this.config,
    required this.aiClientService,
  });

  final String appDataDir;
  final AppConfig config;
  final AiClientService aiClientService;

  @override
  State<_DailyMergePromptDialog> createState() =>
      _DailyMergePromptDialogState();
}

class _DailyMergePromptDialogState extends State<_DailyMergePromptDialog> {
  late final _PromptFimTextEditingController _controller =
      _PromptFimTextEditingController(text: widget.config.dailyMergePrompt);
  late final FocusNode _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
  final ScrollController _scrollController = ScrollController();
  Timer? _fimDebounce;
  int _fimGeneration = 0;
  String? _fimPrediction;
  String? _fimMessage;
  bool _predicting = false;
  bool _acceptingFim = false;
  late String _lastPromptText = _controller.text;
  late TextSelection _lastPromptSelection = _controller.selection;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _fimDebounce?.cancel();
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Dialog(
      key: const ValueKey('daily-merge-prompt-dialog'),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 720,
        height: 680,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '编辑日报整理提示词',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppTheme.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _PromptFimStatusPill(
                    statusText: _promptFimStatusText,
                    active: _promptFimActive,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Prompt',
                      style: textTheme.labelLarge?.copyWith(
                        color: AppTheme.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: TextSelectionTheme(
                            data: TextSelectionTheme.of(context).copyWith(
                              cursorColor: const Color(0xFF6E6E6E),
                              selectionColor: const Color(
                                0xFFBDBDBD,
                              ).withValues(alpha: 0.34),
                              selectionHandleColor: const Color(0xFF737373),
                            ),
                            child: ScrollConfiguration(
                              behavior: const _PromptTextFieldScrollBehavior(),
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                scrollController: _scrollController,
                                expands: true,
                                maxLines: null,
                                minLines: null,
                                textAlignVertical: TextAlignVertical.top,
                                keyboardType: TextInputType.multiline,
                                style:
                                    textTheme.bodyLarge?.copyWith(
                                      color: const Color(0xFF3A3A3A),
                                      fontSize: 14,
                                      height: 1.55,
                                    ) ??
                                    const TextStyle(
                                      color: Color(0xFF3A3A3A),
                                      fontSize: 14,
                                      height: 1.55,
                                    ),
                                cursorColor: const Color(0xFF6E6E6E),
                                cursorWidth: 1.25,
                                cursorRadius: const Radius.circular(1),
                                selectionControls:
                                    desktopTextSelectionHandleControls,
                                enableInteractiveSelection: true,
                                decoration: const InputDecoration(
                                  hintText: '输入日报整理 Prompt...',
                                  hintStyle: TextStyle(
                                    color: Color(0xFFCFCFCF),
                                  ),
                                  filled: true,
                                  fillColor: Color(0xFFFAFAFA),
                                  hoverColor: Color(0xFFFAFAFA),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEDEDED)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
              child: _PromptVariablesHint(textTheme: textTheme),
            ),
            const Divider(height: 1, color: Color(0xFFEDEDED)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              child: Row(
                children: [
                  _ProviderTestDialogButton(
                    label: '恢复默认',
                    filled: false,
                    onTap: _restoreDefault,
                  ),
                  const Spacer(),
                  _ProviderTestDialogButton(
                    label: '取消',
                    filled: false,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  _ProviderTestDialogButton(
                    label: '保存',
                    filled: true,
                    onTap: () => Navigator.of(context).pop(_controller.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _promptFimStatusText {
    if (_predicting) {
      return 'AI 补全预测中';
    }
    if (_fimPrediction != null) {
      return 'Tab 全部 · Ctrl+L 单行 · Ctrl+K 单字';
    }
    if (_fimMessage != null) {
      return _fimMessage!;
    }
    return 'AI 实时补全已就绪';
  }

  bool get _promptFimActive =>
      _predicting || _fimPrediction != null || _fimMessage == null;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final controlPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (key == LogicalKeyboardKey.tab) {
      if (_fimPrediction == null) {
        _insertText('\t');
      } else {
        _acceptFim(_PromptFimAcceptMode.all);
      }
      return KeyEventResult.handled;
    }
    if (_fimPrediction == null) {
      return KeyEventResult.ignored;
    }
    if (controlPressed && key == LogicalKeyboardKey.keyL) {
      _acceptFim(_PromptFimAcceptMode.line);
      return KeyEventResult.handled;
    }
    if (controlPressed && key == LogicalKeyboardKey.keyK) {
      _acceptFim(_PromptFimAcceptMode.character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleChanged() {
    final text = _controller.text;
    final selection = _controller.selection;
    final textChanged = text != _lastPromptText;
    final selectionChanged = selection != _lastPromptSelection;

    _lastPromptText = text;
    _lastPromptSelection = selection;

    if (_acceptingFim) {
      return;
    }

    if (textChanged || selectionChanged) {
      _invalidateFimPrediction(scheduleNext: true);
    }
  }

  void _invalidateFimPrediction({required bool scheduleNext}) {
    _fimGeneration++;
    _fimDebounce?.cancel();

    if (_fimPrediction != null || _predicting) {
      setState(() {
        _fimPrediction = null;
        _predicting = false;
        _fimMessage = null;
        _controller.clearFimPrediction();
      });
    }

    if (!scheduleNext) {
      return;
    }

    final generation = _fimGeneration;
    final text = _controller.text;
    final selection = _controller.selection;

    if (!selection.isValid || !selection.isCollapsed) {
      return;
    }

    final reason = widget.aiClientService.fimUnavailableReason(widget.config);
    if (reason != null) {
      setState(() => _fimMessage = 'FIM 未触发：$reason');
      return;
    }

    if (_fimMessage != null) {
      setState(() => _fimMessage = null);
    }

    _fimDebounce = Timer(const Duration(milliseconds: 300), () {
      _requestFimPrediction(
        generation: generation,
        text: text,
        selection: selection,
      );
    });
  }

  Future<void> _requestFimPrediction({
    required int generation,
    required String text,
    required TextSelection selection,
  }) async {
    if (!mounted ||
        generation != _fimGeneration ||
        text != _controller.text ||
        selection != _controller.selection) {
      return;
    }

    setState(() => _predicting = true);
    final offset = selection.baseOffset;
    String? prediction;
    String? fimError;
    try {
      final result = await widget.aiClientService.fimCompleteMarkdown(
        appDataDir: widget.appDataDir,
        config: widget.config,
        prompt: text.substring(0, offset),
        suffix: text.substring(offset),
      );
      prediction = result.content;
      fimError = result.error;
    } catch (_) {
      prediction = null;
    }

    if (!mounted ||
        generation != _fimGeneration ||
        text != _controller.text ||
        selection != _controller.selection) {
      return;
    }

    setState(() {
      _predicting = false;
      if (prediction?.isEmpty ?? true) {
        _fimPrediction = null;
        _fimMessage = fimError != null && fimError.isNotEmpty
            ? 'FIM 请求失败：$fimError'
            : 'FIM 已请求，但没有返回可用预测';
      } else {
        _fimPrediction = prediction;
        _fimMessage = null;
        _controller.setFimPrediction(prediction!, offset: selection.baseOffset);
      }
    });
  }

  void _acceptFim(_PromptFimAcceptMode mode) {
    final prediction = _fimPrediction;
    final selection = _controller.selection;
    if (prediction == null || prediction.isEmpty || !selection.isValid) {
      return;
    }
    final accepted = switch (mode) {
      _PromptFimAcceptMode.all => prediction,
      _PromptFimAcceptMode.line => _firstPredictionLine(prediction),
      _PromptFimAcceptMode.character => prediction.characters.first,
    };
    final remaining = prediction.substring(accepted.length);
    final text = _controller.text;
    final start = selection.start;
    final end = selection.end;
    final nextText = text.replaceRange(start, end, accepted);
    final nextOffset = start + accepted.length;
    _acceptingFim = true;
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _acceptingFim = false;
    setState(() {
      if (remaining.isEmpty) {
        _fimPrediction = null;
        _controller.clearFimPrediction();
      } else {
        _fimPrediction = remaining;
        _controller.setFimPrediction(remaining, offset: nextOffset);
      }
      _fimMessage = null;
    });
  }

  void _insertText(String value) {
    final selection = _controller.selection;
    if (!selection.isValid) {
      return;
    }
    final text = _controller.text;
    final nextText = text.replaceRange(selection.start, selection.end, value);
    final nextOffset = selection.start + value.length;
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
  }

  String _firstPredictionLine(String prediction) {
    final newlineIndex = prediction.indexOf('\n');
    if (newlineIndex == -1) {
      return prediction;
    }
    return prediction.substring(0, newlineIndex + 1);
  }

  void _restoreDefault() {
    _controller.value = const TextEditingValue(
      text: defaultDailyMergePrompt,
      selection: TextSelection.collapsed(
        offset: defaultDailyMergePrompt.length,
      ),
    );
  }
}

enum _PromptFimAcceptMode { all, line, character }

class _PromptTextFieldScrollBehavior extends ScrollBehavior {
  const _PromptTextFieldScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _PromptFimStatusPill extends StatelessWidget {
  const _PromptFimStatusPill({required this.statusText, required this.active});

  final String statusText;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final foreground = active
        ? const Color(0xFF10B981)
        : const Color(0xFF666666);
    final background = active
        ? const Color(0xFFECFDF5)
        : const Color(0xFFF5F5F5);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            statusText,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptFimTextEditingController extends TextEditingController {
  _PromptFimTextEditingController({super.text});

  String? _fimPrediction;
  int? _fimOffset;

  void setFimPrediction(String prediction, {required int offset}) {
    final normalizedOffset = offset.clamp(0, text.length);
    if (_fimPrediction == prediction && _fimOffset == normalizedOffset) {
      return;
    }
    _fimPrediction = prediction;
    _fimOffset = normalizedOffset;
    notifyListeners();
  }

  void clearFimPrediction() {
    if (_fimPrediction == null && _fimOffset == null) {
      return;
    }
    _fimPrediction = null;
    _fimOffset = null;
    notifyListeners();
  }

  TextSpan _bottomSpacer(TextStyle style) {
    return TextSpan(
      text: '\n',
      style: style.copyWith(color: Colors.transparent),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final prediction = _fimPrediction;
    final offset = _fimOffset;
    final effectiveStyle = style ?? const TextStyle();
    if (prediction == null ||
        prediction.isEmpty ||
        offset == null ||
        offset < 0 ||
        offset > text.length) {
      return TextSpan(
        style: effectiveStyle,
        children: [
          super.buildTextSpan(
            context: context,
            style: style,
            withComposing: withComposing,
          ),
          _bottomSpacer(effectiveStyle),
        ],
      );
    }
    return TextSpan(
      style: effectiveStyle,
      children: [
        TextSpan(text: text.substring(0, offset)),
        TextSpan(
          text: prediction,
          style: effectiveStyle.copyWith(color: const Color(0xFF9AA0A6)),
        ),
        TextSpan(text: text.substring(offset)),
        _bottomSpacer(effectiveStyle),
      ],
    );
  }
}

class _PromptVariablesHint extends StatelessWidget {
  const _PromptVariablesHint({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    const variables = [
      (Icons.calendar_month_outlined, '{date}', '当前日期'),
      (Icons.article_outlined, '{existing_markdown}', '已有日报内容'),
      (Icons.edit_note_rounded, '{raw_input}', '新增随手记录'),
      (Icons.business_center_outlined, '{industry}', '用户所在行业'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 4
            : (constraints.maxWidth >= 460 ? 2 : 1);
        const spacing = 10.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in variables)
              SizedBox(
                width: itemWidth,
                child: _PromptVariableChip(
                  icon: item.$1,
                  name: item.$2,
                  description: item.$3,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PromptVariableChip extends StatelessWidget {
  const _PromptVariableChip({
    required this.icon,
    required this.name,
    required this.description,
  });

  final IconData icon;
  final String name;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.textMuted),
          const SizedBox(width: 7),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.text,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSubtle,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w400,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DataDirectorySettingRow extends StatefulWidget {
  const _DataDirectorySettingRow({
    required this.dataDirectory,
    required this.defaultDirectory,
    required this.saving,
    required this.onChanged,
  });

  final String dataDirectory;
  final bool defaultDirectory;
  final bool saving;
  final ValueChanged<String?> onChanged;

  @override
  State<_DataDirectorySettingRow> createState() =>
      _DataDirectorySettingRowState();
}

class _DataDirectorySettingRowState extends State<_DataDirectorySettingRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.dataDirectory,
  );

  @override
  void didUpdateWidget(covariant _DataDirectorySettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dataDirectory != oldWidget.dataDirectory &&
        widget.dataDirectory != _controller.text) {
      _controller.text = widget.dataDirectory;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    if (widget.saving) {
      return;
    }
    final path = await getDirectoryPath(
      initialDirectory: widget.dataDirectory,
      confirmButtonText: '选择此文件夹',
    );
    if (path == null || path.trim().isEmpty) {
      return;
    }
    widget.onChanged(path.trim());
  }

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: '保存目录',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !widget.saving,
                readOnly: true,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '当前保存目录',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _DataDirectoryActionButton(
              tooltip: '选择并迁移目录',
              onPressed: widget.saving ? null : _pickDirectory,
              child: widget.saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const _DataDirectoryActionIcon(
                      type: _DataDirectoryActionIconType.folderUp,
                      size: 16,
                    ),
            ),
            const SizedBox(width: 2),
            _DataDirectoryActionButton(
              tooltip: '恢复默认目录',
              onPressed: widget.saving || widget.defaultDirectory
                  ? null
                  : () => widget.onChanged(null),
              child: const Icon(Icons.restart_alt_rounded, size: 17),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DataDirectoryActionIconType { folderUp }

class _DataDirectoryActionButton extends StatefulWidget {
  const _DataDirectoryActionButton({
    required this.tooltip,
    required this.child,
    required this.onPressed,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback? onPressed;

  @override
  State<_DataDirectoryActionButton> createState() =>
      _DataDirectoryActionButtonState();
}

class _DataDirectoryActionButtonState
    extends State<_DataDirectoryActionButton> {
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
                IconTheme(
                  data: IconThemeData(color: iconColor, size: 16),
                  child: widget.child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DataDirectoryActionIcon extends StatelessWidget {
  const _DataDirectoryActionIcon({required this.type, required this.size});

  final _DataDirectoryActionIconType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? AppTheme.textSubtle;
    return CustomPaint(
      size: Size.square(size),
      painter: _DataDirectoryActionIconPainter(type: type, color: color),
    );
  }
}

class _DataDirectoryActionIconPainter extends CustomPainter {
  const _DataDirectoryActionIconPainter({
    required this.type,
    required this.color,
  });

  final _DataDirectoryActionIconType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24;
    final sy = size.height / 24;
    final strokeScale = sx < sy ? sx : sy;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * strokeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset point(double x, double y) => Offset(x * sx, y * sy);
    switch (type) {
      case _DataDirectoryActionIconType.folderUp:
        final folderPath = Path()
          ..moveTo(point(3, 6.5).dx, point(3, 6.5).dy)
          ..cubicTo(
            point(3, 5.4).dx,
            point(3, 5.4).dy,
            point(3.9, 4.5).dx,
            point(3.9, 4.5).dy,
            point(5, 4.5).dx,
            point(5, 4.5).dy,
          )
          ..lineTo(point(9.1, 4.5).dx, point(9.1, 4.5).dy)
          ..lineTo(point(11.3, 7).dx, point(11.3, 7).dy)
          ..lineTo(point(19, 7).dx, point(19, 7).dy)
          ..cubicTo(
            point(20.1, 7).dx,
            point(20.1, 7).dy,
            point(21, 7.9).dx,
            point(21, 7.9).dy,
            point(21, 9).dx,
            point(21, 9).dy,
          )
          ..lineTo(point(21, 17.5).dx, point(21, 17.5).dy)
          ..cubicTo(
            point(21, 18.6).dx,
            point(21, 18.6).dy,
            point(20.1, 19.5).dx,
            point(20.1, 19.5).dy,
            point(19, 19.5).dx,
            point(19, 19.5).dy,
          )
          ..lineTo(point(5, 19.5).dx, point(5, 19.5).dy)
          ..cubicTo(
            point(3.9, 19.5).dx,
            point(3.9, 19.5).dy,
            point(3, 18.6).dx,
            point(3, 18.6).dy,
            point(3, 17.5).dx,
            point(3, 17.5).dy,
          )
          ..close();
        canvas.drawPath(folderPath, paint);
        canvas.drawLine(point(12, 16), point(12, 11), paint);
        canvas.drawPath(
          Path()
            ..moveTo(point(8.9, 13.1).dx, point(8.9, 13.1).dy)
            ..lineTo(point(12, 10).dx, point(12, 10).dy)
            ..lineTo(point(15.1, 13.1).dx, point(15.1, 13.1).dy),
          paint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _DataDirectoryActionIconPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}

class _FontSettingRow extends StatefulWidget {
  const _FontSettingRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_FontSettingRow> createState() => _FontSettingRowState();
}

class _FontSettingRowState extends State<_FontSettingRow> {
  bool _loading = false;

  Future<void> _openFontPicker() async {
    if (_loading) {
      return;
    }

    setState(() => _loading = true);
    final fonts = await const SystemFontService().loadFonts();
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);

    final selectedFont = await showDialog<String>(
      context: context,
      builder: (context) =>
          _FontPickerDialog(fonts: fonts, selectedFont: widget.value),
    );
    if (selectedFont == null || selectedFont == widget.value) {
      return;
    }
    widget.onChanged(selectedFont);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.value == 'system' ? '系统默认' : widget.value;

    return _SettingRowShell(
      label: widget.label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FontPickerButton(
            label: label,
            loading: _loading,
            onTap: _openFontPicker,
          ),
          _FontResetButton(
            onPressed: widget.value == 'system'
                ? null
                : () => widget.onChanged('system'),
          ),
        ],
      ),
    );
  }
}

class _FontPickerButton extends StatefulWidget {
  const _FontPickerButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  State<_FontPickerButton> createState() => _FontPickerButtonState();
}

class _FontPickerButtonState extends State<_FontPickerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || widget.loading;
    return MouseRegion(
      cursor: widget.loading
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.loading ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          width: 220,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFEDEDED) : const Color(0xFFF5F5F5),
            border: Border.all(
              color: active ? const Color(0xFFCFCFCF) : const Color(0xFFE5E5E5),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.text,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.loading)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.7),
                )
              else
                const Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: AppTheme.textSubtle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FontPickerDialog extends StatefulWidget {
  const _FontPickerDialog({required this.fonts, required this.selectedFont});

  final List<String> fonts;
  final String selectedFont;

  @override
  State<_FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<_FontPickerDialog> {
  late final TextEditingController _controller = TextEditingController();
  String _query = '';
  String? _hoveredFont;

  List<String> get _fonts {
    final normalizedQuery = _query.trim().toLowerCase();
    final values = ['system', ...widget.fonts];
    if (normalizedQuery.isEmpty) {
      return values;
    }
    return values
        .where(
          (font) => _fontLabel(font).toLowerCase().contains(normalizedQuery),
        )
        .toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fonts = _fonts;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 460,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
              child: Row(
                children: [
                  Text('选择字体', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: _SettingsSearchField(
                controller: _controller,
                autofocus: true,
                hintText: '搜索系统字体',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: fonts.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的字体',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                      itemCount: fonts.length,
                      itemBuilder: (context, index) {
                        final font = fonts[index];
                        return _FontOptionTile(
                          font: font,
                          selected: font == widget.selectedFont,
                          hovered: font == _hoveredFont,
                          onHoverChanged: (hovered) {
                            setState(() {
                              if (hovered) {
                                _hoveredFont = font;
                              } else if (_hoveredFont == font) {
                                _hoveredFont = null;
                              }
                            });
                          },
                          onTap: () => Navigator.of(context).pop(font),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FontOptionTile extends StatelessWidget {
  const _FontOptionTile({
    required this.font,
    required this.selected,
    required this.hovered,
    required this.onHoverChanged,
    required this.onTap,
  });

  final String font;
  final bool selected;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = selected || hovered;
    final fontFamily = font == 'system' ? null : font;
    final backgroundColor = selected
        ? const Color(0xFFE2E2E2)
        : const Color(0xFFF5F5F5);
    final contentColor = active ? AppTheme.text : AppTheme.textMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                bottom: 4,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  opacity: active ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                bottom: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _fontLabel(font),
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: contentColor,
                                fontFamily: fontFamily,
                                height: 1.2,
                              ),
                        ),
                      ),
                      if (selected)
                        const Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: AppTheme.text,
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

String _fontLabel(String font) {
  return font == 'system' ? '系统默认' : font;
}

class _FontResetButton extends StatefulWidget {
  const _FontResetButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<_FontResetButton> createState() => _FontResetButtonState();
}

class _FontResetButtonState extends State<_FontResetButton> {
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
      message: '重置字体',
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
                  Icons.restart_alt_rounded,
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
