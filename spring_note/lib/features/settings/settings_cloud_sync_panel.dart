part of 'settings_page.dart';

class _CloudSyncPanel extends StatefulWidget {
  const _CloudSyncPanel({
    required this.config,
    required this.localDataState,
    required this.cloudSyncService,
    required this.onChanged,
    this.onCloudSyncCompleted,
  });

  final AppConfig config;
  final LocalDataState localDataState;
  final CloudSyncService cloudSyncService;
  final ValueChanged<AppConfig> onChanged;
  final VoidCallback? onCloudSyncCompleted;

  @override
  State<_CloudSyncPanel> createState() => _CloudSyncPanelState();
}

class _CloudSyncPanelState extends State<_CloudSyncPanel> {
  bool _testing = false;
  bool _syncing = false;
  String? _message;
  bool _messageIsError = false;

  static const int _maxSyncConfirmationRounds = 5;

  CloudSyncConfig get _sync => widget.config.cloudSync;

  @override
  Widget build(BuildContext context) {
    final enabled = _sync.enabled;
    return _SettingsScrollFrame(
      maxWidth: 820,
      children: [
        _SettingsCard(
          title: '连接设置',
          children: [
            _SwitchSettingRow(
              label: '启用云同步',
              value: enabled,
              onChanged: (value) => _updateSync(_sync.copyWith(enabled: value)),
            ),
            _TextSettingRow(
              label: 'WebDAV 地址',
              value: _sync.serverUrl,
              enabled: enabled,
              onChanged: (value) =>
                  _updateSync(_sync.copyWith(serverUrl: value)),
              validator: _validateServerUrl,
            ),
            _TextSettingRow(
              label: '账号',
              value: _sync.username,
              enabled: enabled,
              onChanged: (value) =>
                  _updateSync(_sync.copyWith(username: value)),
            ),
            _CloudSyncPasswordRow(
              value: _sync.password,
              enabled: enabled,
              onChanged: (value) =>
                  _updateSync(_sync.copyWith(password: value)),
            ),
          ],
        ),
        _SettingsCard(
          title: '同步策略',
          children: [
            _SwitchSettingRow(
              label: '应用启动时自动同步',
              value: _sync.syncOnStartup,
              enabled: enabled,
              onChanged: (value) =>
                  _updateSync(_sync.copyWith(syncOnStartup: value)),
            ),
            _SwitchSettingRow(
              label: '实时同步',
              value: _sync.realTimeSync,
              enabled: enabled,
              onChanged: (value) =>
                  _updateSync(_sync.copyWith(realTimeSync: value)),
            ),
            _SimpleRow(
              label: '最近一次全量同步',
              value: _formatSyncedAt(_sync.lastSyncedAt),
            ),
            _CloudSyncActionsRow(
              enabled: enabled && !_testing && !_syncing,
              testing: _testing,
              syncing: _syncing,
              onTest: _testConnection,
              onSync: _manualSync,
            ),
          ],
        ),
        _CloudSyncMessageSlot(message: _message, error: _messageIsError),
      ],
    );
  }

  void _updateSync(CloudSyncConfig sync) {
    widget.onChanged(widget.config.copyWith(cloudSync: sync));
  }

  Future<void> _testConnection() async {
    if (_testing || _syncing) {
      return;
    }
    setState(() {
      _testing = true;
      _message = null;
    });
    final result = await widget.cloudSyncService.testConnection(_sync);
    if (!mounted) {
      return;
    }
    setState(() {
      _testing = false;
      _message = result.message;
      _messageIsError = !result.ok;
    });
  }

  Future<void> _manualSync() async {
    if (_testing || _syncing) {
      return;
    }
    setState(() {
      _syncing = true;
      _message = null;
    });
    final state = widget.localDataState.copyWith(config: widget.config);
    var confirmedDeleteLocal = <String>[];
    var confirmedDeleteRemote = <String>[];
    var confirmedOverwriteLocal = <String>[];
    var confirmedOverwriteRemote = <String>[];
    var skippedDeleteModifyConflicts = <String>[];

    for (var round = 0; round < _maxSyncConfirmationRounds; round++) {
      final result = await widget.cloudSyncService.sync(
        localDataState: state,
        trigger: CloudSyncTrigger.manual,
        confirmedDeleteLocal: confirmedDeleteLocal,
        confirmedDeleteRemote: confirmedDeleteRemote,
        confirmedOverwriteLocal: confirmedOverwriteLocal,
        confirmedOverwriteRemote: confirmedOverwriteRemote,
        skippedDeleteModifyConflicts: skippedDeleteModifyConflicts,
      );
      if (!mounted) {
        return;
      }

      confirmedDeleteLocal = [];
      confirmedDeleteRemote = [];
      confirmedOverwriteLocal = [];
      confirmedOverwriteRemote = [];
      skippedDeleteModifyConflicts = [];

      var shouldContinue = false;
      if (result.needsDeleteConfirmation) {
        setState(() => _syncing = false);
        final confirmed = await _confirmDeletePlan(result);
        if (!mounted) {
          return;
        }
        if (!confirmed) {
          setState(() {
            _message = '已取消删除，未执行删除项';
            _messageIsError = false;
          });
          return;
        }
        confirmedDeleteLocal = result.pendingDeleteLocal;
        confirmedDeleteRemote = result.pendingDeleteRemote;
        shouldContinue = true;
      }

      if (result.needsDeleteModifyConfirmation) {
        if (_syncing) {
          setState(() => _syncing = false);
        }
        final decision = await _confirmDeleteModifyConflicts(
          result.pendingDeleteModifyConflicts,
        );
        if (!mounted) {
          return;
        }
        confirmedOverwriteLocal = decision.overwriteLocal;
        confirmedOverwriteRemote = decision.overwriteRemote;
        skippedDeleteModifyConflicts = decision.skipped;
        if (decision.allSkipped &&
            confirmedDeleteLocal.isEmpty &&
            confirmedDeleteRemote.isEmpty) {
          setState(() {
            _message = '已跳过删除修改冲突，未处理冲突项';
            _messageIsError = false;
          });
          return;
        }
        shouldContinue = true;
      }

      if (shouldContinue) {
        if (_testing || _syncing) {
          return;
        }
        setState(() {
          _syncing = true;
          _message = null;
        });
        continue;
      }

      _finishManualSync(result);
      return;
    }

    setState(() {
      _syncing = false;
      _message = '仍有待确认项，请重新同步。';
      _messageIsError = true;
    });
  }

  void _finishManualSync(CloudSyncResult result) {
    setState(() {
      _syncing = false;
      _message = result.message;
      _messageIsError = !result.ok;
    });
    if (result.ok && result.syncedAt != null) {
      final nextConfig = widget.config.copyWith(
        cloudSync: _sync.copyWith(lastSyncedAt: result.syncedAt),
      );
      widget.onChanged(nextConfig);
      widget.onCloudSyncCompleted?.call();
    }
  }

  Future<bool> _confirmDeletePlan(CloudSyncResult result) async {
    final deleteLocal = result.pendingDeleteLocal;
    final deleteRemote = result.pendingDeleteRemote;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _CloudSyncDeleteConfirmDialog(
        key: const ValueKey('cloud-sync-delete-confirm-dialog'),
        deleteLocal: deleteLocal,
        deleteRemote: deleteRemote,
      ),
    );
    return confirmed ?? false;
  }

  Future<_DeleteModifyConflictDecision> _confirmDeleteModifyConflicts(
    List<CloudSyncDeleteModifyConflict> conflicts,
  ) async {
    final confirmed = await showDialog<_DeleteModifyConflictDecision>(
      context: context,
      builder: (context) => _DeleteModifyConflictDialog(
        key: const ValueKey('cloud-sync-delete-modify-confirm-dialog'),
        conflicts: conflicts,
      ),
    );
    return confirmed ??
        _DeleteModifyConflictDecision.fromSelections(conflicts, {
          for (final conflict in conflicts)
            conflict.relativePath: _DeleteModifyResolution.skip,
        });
  }

  String? _validateServerUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty || !uri.hasScheme) {
      return '请输入完整 URL';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return '仅支持 http/https';
    }
    return null;
  }

  String _formatSyncedAt(DateTime? value) {
    if (value == null) {
      return '尚未同步';
    }
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _CloudSyncPasswordRow extends StatelessWidget {
  const _CloudSyncPasswordRow({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: '密码/应用令牌',
      enabled: enabled,
      child: SizedBox(
        width: 220,
        child: _CommittedTextField(
          value: value,
          enabled: enabled,
          obscureText: true,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

enum _CloudSyncDeleteTarget { local, remote }

class _CloudSyncDeleteConfirmDialog extends StatefulWidget {
  const _CloudSyncDeleteConfirmDialog({
    super.key,
    required this.deleteLocal,
    required this.deleteRemote,
  });

  final List<String> deleteLocal;
  final List<String> deleteRemote;

  @override
  State<_CloudSyncDeleteConfirmDialog> createState() =>
      _CloudSyncDeleteConfirmDialogState();
}

class _CloudSyncDeleteConfirmDialogState
    extends State<_CloudSyncDeleteConfirmDialog> {
  late final ScrollController _scrollController = ScrollController();
  final Set<_CloudSyncDeleteTarget> _expandedTargets = {};
  bool _submitting = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleGroup(_CloudSyncDeleteTarget target) {
    setState(() {
      if (_expandedTargets.contains(target)) {
        _expandedTargets.remove(target);
      } else {
        _expandedTargets.add(target);
      }
    });
  }

  void _cancel() {
    if (_submitting) {
      return;
    }
    Navigator.of(context).pop(false);
  }

  void _confirm() {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Dialog(
      backgroundColor: AppTheme.dialogSurface(context),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 720,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '确认删除同步',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: colors.text,
                          fontSize: 18,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '检测到删除操作，确认后将同步删除对应文件。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSubtle,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    interactive: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      primary: false,
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.deleteLocal.isNotEmpty)
                            _CloudSyncDeleteGroupSection(
                              title: '将删除本地文件',
                              icon: Icons.desktop_windows_outlined,
                              paths: widget.deleteLocal,
                              expanded: _expandedTargets.contains(
                                _CloudSyncDeleteTarget.local,
                              ),
                              onTap: () =>
                                  _toggleGroup(_CloudSyncDeleteTarget.local),
                            ),
                          if (widget.deleteLocal.isNotEmpty &&
                              widget.deleteRemote.isNotEmpty)
                            const SizedBox(height: 8),
                          if (widget.deleteRemote.isNotEmpty)
                            _CloudSyncDeleteGroupSection(
                              title: '将删除远端文件',
                              icon: Icons.cloud_outlined,
                              paths: widget.deleteRemote,
                              expanded: _expandedTargets.contains(
                                _CloudSyncDeleteTarget.remote,
                              ),
                              onTap: () =>
                                  _toggleGroup(_CloudSyncDeleteTarget.remote),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.divider)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _DeleteModifyFooterButton(
                      label: '取消',
                      filled: false,
                      enabled: !_submitting,
                      onTap: _cancel,
                    ),
                    const SizedBox(width: 12),
                    _DeleteModifyFooterButton(
                      label: '确认删除并同步',
                      filled: true,
                      enabled: !_submitting,
                      onTap: _confirm,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloudSyncDeleteGroupSection extends StatelessWidget {
  const _CloudSyncDeleteGroupSection({
    required this.title,
    required this.icon,
    required this.paths,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final List<String> paths;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CloudSyncDeleteGroupHeader(
          title: title,
          icon: icon,
          count: paths.length,
          expanded: expanded,
          onTap: onTap,
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 280),
            reverseDuration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    children: [
                      const SizedBox(height: 6),
                      for (final path in paths)
                        _CloudSyncDeleteFileTile(path: _formatDeletePath(path)),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }
}

class _CloudSyncDeleteGroupHeader extends StatefulWidget {
  const _CloudSyncDeleteGroupHeader({
    required this.title,
    required this.icon,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_CloudSyncDeleteGroupHeader> createState() =>
      _CloudSyncDeleteGroupHeaderState();
}

class _CloudSyncDeleteGroupHeaderState
    extends State<_CloudSyncDeleteGroupHeader> {
  bool _hovered = false;
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final backgroundColor = widget.expanded
        ? colors.surfacePressed
        : _hovered
        ? colors.inputFocusedFill
        : colors.inputFill;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        setState(() {
          _hovered = false;
          _pressed = false;
        });
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _setPressed(true),
        onPointerCancel: (_) => _setPressed(false),
        onPointerUp: (_) {
          _setPressed(false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: _pressed
              ? const Duration(milliseconds: 80)
              : const Duration(milliseconds: 240),
          curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
          child: SizedBox(
            height: 50,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: widget.expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 19,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(widget.icon, size: 17, color: colors.textMuted),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      widget.title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.2,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      widget.count.toString(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSubtle,
                        fontWeight: FontWeight.w400,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloudSyncDeleteFileTile extends StatefulWidget {
  const _CloudSyncDeleteFileTile({required this.path});

  final String path;

  @override
  State<_CloudSyncDeleteFileTile> createState() =>
      _CloudSyncDeleteFileTileState();
}

class _CloudSyncDeleteFileTileState extends State<_CloudSyncDeleteFileTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        height: 46,
        margin: const EdgeInsets.only(left: 28),
        padding: const EdgeInsets.only(left: 14, right: 10),
        decoration: BoxDecoration(
          color: _hovered ? colors.surfaceHover : colors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const _DeleteModifyFileIcon(size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DeleteModifyResolution { overwriteRemote, overwriteLocal, skip }

class _DeleteModifyConflictDecision {
  const _DeleteModifyConflictDecision({
    required this.overwriteLocal,
    required this.overwriteRemote,
    required this.skipped,
  });

  final List<String> overwriteLocal;
  final List<String> overwriteRemote;
  final List<String> skipped;

  bool get allSkipped =>
      overwriteLocal.isEmpty && overwriteRemote.isEmpty && skipped.isNotEmpty;

  factory _DeleteModifyConflictDecision.fromSelections(
    List<CloudSyncDeleteModifyConflict> conflicts,
    Map<String, _DeleteModifyResolution> selections,
  ) {
    final overwriteLocal = <String>[];
    final overwriteRemote = <String>[];
    final skipped = <String>[];
    for (final conflict in conflicts) {
      final path = conflict.relativePath;
      switch (selections[path] ?? _DeleteModifyResolution.skip) {
        case _DeleteModifyResolution.overwriteLocal:
          overwriteLocal.add(path);
        case _DeleteModifyResolution.overwriteRemote:
          overwriteRemote.add(path);
        case _DeleteModifyResolution.skip:
          skipped.add(path);
      }
    }
    return _DeleteModifyConflictDecision(
      overwriteLocal: overwriteLocal,
      overwriteRemote: overwriteRemote,
      skipped: skipped,
    );
  }
}

class _DeleteModifyConflictDialog extends StatefulWidget {
  const _DeleteModifyConflictDialog({super.key, required this.conflicts});

  final List<CloudSyncDeleteModifyConflict> conflicts;

  @override
  State<_DeleteModifyConflictDialog> createState() =>
      _DeleteModifyConflictDialogState();
}

class _DeleteModifyConflictDialogState
    extends State<_DeleteModifyConflictDialog> {
  late final ScrollController _scrollController = ScrollController();
  final Map<String, _DeleteModifyResolution> _selections = {};
  bool _submitting = false;

  int get _handledCount => _selections.length;

  int get _remainingCount => widget.conflicts.length - _handledCount;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _setSelection(
    CloudSyncDeleteModifyConflict conflict,
    _DeleteModifyResolution resolution,
  ) {
    if (_submitting) {
      return;
    }
    setState(() => _selections[conflict.relativePath] = resolution);
  }

  Future<void> _continue() async {
    if (_submitting) {
      return;
    }
    final remaining = _remainingCount;
    if (remaining > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.dialogSurface(context),
          surfaceTintColor: Colors.transparent,
          title: const Text('仍有未处理项'),
          content: Text('仍有 $remaining 个文件未选择处理方式，将自动视为“跳过此项”，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('返回选择'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    setState(() => _submitting = true);
    Navigator.of(context).pop(
      _DeleteModifyConflictDecision.fromSelections(
        widget.conflicts,
        _completedSelections(),
      ),
    );
  }

  void _skipAll() {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    Navigator.of(context).pop(
      _DeleteModifyConflictDecision.fromSelections(
        widget.conflicts,
        _skippedSelections(),
      ),
    );
  }

  Map<String, _DeleteModifyResolution> _completedSelections() {
    return {
      for (final conflict in widget.conflicts)
        conflict.relativePath:
            _selections[conflict.relativePath] ?? _DeleteModifyResolution.skip,
    };
  }

  Map<String, _DeleteModifyResolution> _skippedSelections() {
    return {
      for (final conflict in widget.conflicts)
        conflict.relativePath: _DeleteModifyResolution.skip,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Dialog(
      backgroundColor: AppTheme.dialogSurface(context),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 980,
        height: 660,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 18, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '检测到删除冲突',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: colors.text,
                                fontSize: 18,
                                height: 1.2,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '以下文件在一端已删除，另一端已修改，请选择最终保留的结果。',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colors.textSubtle,
                                fontSize: 13,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 22),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  interactive: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (
                          var index = 0;
                          index < widget.conflicts.length;
                          index++
                        ) ...[
                          if (index > 0) const SizedBox(height: 10),
                          _DeleteModifyConflictRow(
                            conflict: widget.conflicts[index],
                            value:
                                _selections[widget
                                    .conflicts[index]
                                    .relativePath],
                            enabled: !_submitting,
                            onChanged: (resolution) => _setSelection(
                              widget.conflicts[index],
                              resolution,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _DeleteModifyDialogFooter(
              totalCount: widget.conflicts.length,
              handledCount: _handledCount,
              remainingCount: _remainingCount,
              submitting: _submitting,
              onSkipAll: _skipAll,
              onContinue: _continue,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteModifyConflictRow extends StatefulWidget {
  const _DeleteModifyConflictRow({
    required this.conflict,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final CloudSyncDeleteModifyConflict conflict;
  final _DeleteModifyResolution? value;
  final bool enabled;
  final ValueChanged<_DeleteModifyResolution> onChanged;

  @override
  State<_DeleteModifyConflictRow> createState() =>
      _DeleteModifyConflictRowState();
}

class _DeleteModifyConflictRowState extends State<_DeleteModifyConflictRow> {
  bool _hovered = false;

  bool get _localModifiedRemoteDeleted {
    return widget.conflict.direction == 'local_modified_remote_deleted';
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.value;
    final colors = AppTheme.colors(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _hovered ? colors.surfaceHover : colors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 840;
            final file = _DeleteModifyFileCell(
              path: _formatDeletePath(widget.conflict.relativePath),
            );
            final status = _DeleteModifyStatusCell(
              localModifiedRemoteDeleted: _localModifiedRemoteDeleted,
            );
            final actions = _DeleteModifyActionCell(
              localModifiedRemoteDeleted: _localModifiedRemoteDeleted,
              value: selected,
              enabled: widget.enabled,
              onChanged: widget.onChanged,
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  file,
                  const SizedBox(height: 12),
                  status,
                  const SizedBox(height: 12),
                  actions,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: file),
                const SizedBox(width: 18),
                SizedBox(width: 250, child: status),
                const SizedBox(width: 18),
                SizedBox(width: 356, child: actions),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DeleteModifyFileCell extends StatelessWidget {
  const _DeleteModifyFileCell({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Row(
      children: [
        const _DeleteModifyFileIcon(size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.text,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeleteModifyStatusCell extends StatelessWidget {
  const _DeleteModifyStatusCell({required this.localModifiedRemoteDeleted});

  final bool localModifiedRemoteDeleted;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _DeleteModifyStatusBadge(
          label: localModifiedRemoteDeleted ? '本地：已修改' : '本地：已删除',
          icon: localModifiedRemoteDeleted
              ? Icons.desktop_windows_outlined
              : Icons.delete_outline_rounded,
          color: localModifiedRemoteDeleted
              ? const Color(0xFF15803D)
              : const Color(0xFFDC2626),
          background: localModifiedRemoteDeleted
              ? const Color(0xFFE9F9EF)
              : const Color(0xFFFFEEEE),
        ),
        _DeleteModifyStatusBadge(
          label: localModifiedRemoteDeleted ? '远端：已删除' : '远端：已修改',
          icon: localModifiedRemoteDeleted
              ? Icons.cloud_off_outlined
              : Icons.cloud_done_outlined,
          color: localModifiedRemoteDeleted
              ? const Color(0xFFDC2626)
              : const Color(0xFF15803D),
          background: localModifiedRemoteDeleted
              ? const Color(0xFFFFEEEE)
              : const Color(0xFFE9F9EF),
        ),
      ],
    );
  }
}

class _DeleteModifyStatusBadge extends StatelessWidget {
  const _DeleteModifyStatusBadge({
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteModifyActionCell extends StatelessWidget {
  const _DeleteModifyActionCell({
    required this.localModifiedRemoteDeleted,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool localModifiedRemoteDeleted;
  final _DeleteModifyResolution? value;
  final bool enabled;
  final ValueChanged<_DeleteModifyResolution> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _DeleteModifyActionButton(
          width: 128,
          label: localModifiedRemoteDeleted ? '保留本地版本' : '保留本地删除',
          tooltip: localModifiedRemoteDeleted
              ? '上传本地文件到远端，恢复远端文件。'
              : '删除远端文件，与本地删除状态保持一致。',
          icon: localModifiedRemoteDeleted
              ? Icons.cloud_upload_outlined
              : Icons.delete_outline_rounded,
          selected: value == _DeleteModifyResolution.overwriteRemote,
          enabled: enabled,
          onTap: () => onChanged(_DeleteModifyResolution.overwriteRemote),
        ),
        _DeleteModifyActionButton(
          width: 128,
          label: localModifiedRemoteDeleted ? '保留远端删除' : '保留远端版本',
          tooltip: localModifiedRemoteDeleted
              ? '删除本地文件，保持远端已删除的状态。'
              : '下载远端文件，恢复本地文件。',
          icon: localModifiedRemoteDeleted
              ? Icons.delete_outline_rounded
              : Icons.cloud_download_outlined,
          selected: value == _DeleteModifyResolution.overwriteLocal,
          enabled: enabled,
          onTap: () => onChanged(_DeleteModifyResolution.overwriteLocal),
        ),
        _DeleteModifyActionButton(
          width: 84,
          label: '跳过',
          tooltip: '本次不同步该文件，下次同步时仍会提示处理。',
          icon: Icons.more_horiz_rounded,
          selected: value == _DeleteModifyResolution.skip,
          enabled: enabled,
          onTap: () => onChanged(_DeleteModifyResolution.skip),
        ),
      ],
    );
  }
}

class _DeleteModifyActionButton extends StatefulWidget {
  const _DeleteModifyActionButton({
    required this.width,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final double width;
  final String label;
  final String tooltip;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_DeleteModifyActionButton> createState() =>
      _DeleteModifyActionButtonState();
}

class _DeleteModifyActionButtonState extends State<_DeleteModifyActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;
    final colors = AppTheme.colors(context);
    final foreground = widget.enabled
        ? colors.text
        : colors.textSubtle.withValues(alpha: 0.45);
    final borderColor = widget.enabled
        ? (active ? colors.textSubtle : colors.border)
        : colors.border;
    final background = widget.selected
        ? colors.surfacePressed
        : _hovered
        ? colors.surfaceHover
        : colors.surface;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) {
          setState(() {
            _hovered = false;
            _pressed = false;
          });
        },
        child: Listener(
          onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
          onPointerCancel: (_) => _setPressed(false),
          onPointerUp: widget.enabled
              ? (_) {
                  _setPressed(false);
                  widget.onTap();
                }
              : null,
          child: AnimatedScale(
            scale: _pressed ? 0.98 : 1,
            duration: _pressed
                ? const Duration(milliseconds: 80)
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              width: widget.width,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: background,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 16, color: foreground),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteModifyDialogFooter extends StatelessWidget {
  const _DeleteModifyDialogFooter({
    required this.totalCount,
    required this.handledCount,
    required this.remainingCount,
    required this.submitting,
    required this.onSkipAll,
    required this.onContinue,
  });

  final int totalCount;
  final int handledCount;
  final int remainingCount;
  final bool submitting;
  final VoidCallback onSkipAll;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _DeleteModifyStatText(label: '共', value: '$totalCount 个冲突'),
                _DeleteModifyStatText(label: '已处理', value: '$handledCount 个'),
                _DeleteModifyStatText(label: '剩余', value: '$remainingCount 个'),
              ],
            ),
          ),
          const SizedBox(width: 18),
          _DeleteModifyFooterButton(
            label: '全部跳过',
            filled: false,
            enabled: !submitting,
            onTap: onSkipAll,
          ),
          const SizedBox(width: 12),
          _DeleteModifyFooterButton(
            label: '按选择继续',
            filled: true,
            enabled: !submitting,
            onTap: onContinue,
          ),
        ],
      ),
    );
  }
}

class _DeleteModifyStatText extends StatelessWidget {
  const _DeleteModifyStatText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label),
          const TextSpan(text: ' '),
          TextSpan(
            text: value,
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w400),
          ),
        ],
      ),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: colors.textSubtle,
        fontSize: 13,
        height: 1.3,
      ),
    );
  }
}

class _DeleteModifyFooterButton extends StatefulWidget {
  const _DeleteModifyFooterButton({
    required this.label,
    required this.filled,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_DeleteModifyFooterButton> createState() =>
      _DeleteModifyFooterButtonState();
}

class _DeleteModifyFooterButtonState extends State<_DeleteModifyFooterButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.filled;
    final colors = AppTheme.colors(context);
    final foreground = filled ? colors.onAccent : colors.text;
    final background = filled
        ? (_hovered ? colors.text.withValues(alpha: 0.88) : colors.text)
        : (_hovered ? colors.surfaceHover : colors.surface);
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        setState(() {
          _hovered = false;
          _pressed = false;
        });
      },
      child: Listener(
        onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
        onPointerCancel: (_) => _setPressed(false),
        onPointerUp: widget.enabled
            ? (_) {
                _setPressed(false);
                widget.onTap();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: _pressed
              ? const Duration(milliseconds: 80)
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            width: filled ? 164 : 150,
            height: 44,
            decoration: BoxDecoration(
              color: widget.enabled
                  ? background
                  : background.withValues(alpha: 0.55),
              border: Border.all(color: filled ? colors.text : colors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                widget.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: widget.enabled
                      ? foreground
                      : foreground.withValues(alpha: 0.45),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteModifyFileIcon extends StatelessWidget {
  const _DeleteModifyFileIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DeleteModifyFileIconPainter(),
    );
  }
}

class _DeleteModifyFileIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8A94A6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.25, size.height * 0.12)
      ..lineTo(size.width * 0.58, size.height * 0.12)
      ..lineTo(size.width * 0.77, size.height * 0.31)
      ..lineTo(size.width * 0.77, size.height * 0.88)
      ..lineTo(size.width * 0.25, size.height * 0.88)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(size.width * 0.58, size.height * 0.12),
      Offset(size.width * 0.58, size.height * 0.32),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.58, size.height * 0.32),
      Offset(size.width * 0.77, size.height * 0.32),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _formatDeletePath(String path) {
  return path.startsWith('notes/') ? path.substring(6) : path;
}

class _CloudSyncActionsRow extends StatelessWidget {
  const _CloudSyncActionsRow({
    required this.enabled,
    required this.testing,
    required this.syncing,
    required this.onTest,
    required this.onSync,
  });

  final bool enabled;
  final bool testing;
  final bool syncing;
  final VoidCallback onTest;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: '同步操作',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: enabled ? onTest : null,
            icon: testing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_done_outlined, size: 18),
            label: Text(testing ? '测试中' : '测试连接'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: enabled ? onSync : null,
            icon: syncing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 18),
            label: Text(syncing ? '同步中' : '手动同步'),
          ),
        ],
      ),
    );
  }
}

class _CloudSyncMessageSlot extends StatelessWidget {
  const _CloudSyncMessageSlot({required this.message, required this.error});

  final String? message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return SizedBox(
      key: const ValueKey('cloud-sync-message-slot'),
      height: 42,
      child: text == null
          ? const SizedBox.shrink()
          : _SettingsMessage(text: text, error: error),
    );
  }
}
