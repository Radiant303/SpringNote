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
              label: '最近同步',
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
    var submitting = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          key: const ValueKey('cloud-sync-delete-confirm-dialog'),
          title: const Text('确认删除同步'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('检测到文件删除。确认后才会删除对应文件。'),
                  if (deleteLocal.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('将从本地删除'),
                    const SizedBox(height: 6),
                    _CloudSyncDeleteList(paths: deleteLocal),
                  ],
                  if (deleteRemote.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('将从远端删除'),
                    const SizedBox(height: 6),
                    _CloudSyncDeleteList(paths: deleteRemote),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () {
                      submitting = true;
                      setDialogState(() {});
                      Navigator.of(context).pop(true);
                    },
              child: const Text('确认删除并同步'),
            ),
          ],
        ),
      ),
    );
    return confirmed ?? false;
  }

  Future<_DeleteModifyConflictDecision> _confirmDeleteModifyConflicts(
    List<CloudSyncDeleteModifyConflict> conflicts,
  ) async {
    final selections = {
      for (final conflict in conflicts)
        conflict.relativePath: _DeleteModifyResolution.skip,
    };
    var submitting = false;
    final confirmed = await showDialog<_DeleteModifyConflictDecision>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          key: const ValueKey('cloud-sync-delete-modify-confirm-dialog'),
          title: const Text('处理删除修改冲突'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('检测到一端删除、另一端修改的文件，请选择处理方式。'),
                  const SizedBox(height: 14),
                  for (final conflict in conflicts) ...[
                    _DeleteModifyConflictTile(
                      conflict: conflict,
                      value:
                          selections[conflict.relativePath] ??
                          _DeleteModifyResolution.skip,
                      enabled: !submitting,
                      onChanged: (value) {
                        setDialogState(() {
                          selections[conflict.relativePath] = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.of(context).pop(
                      _DeleteModifyConflictDecision.fromSelections(conflicts, {
                        for (final conflict in conflicts)
                          conflict.relativePath: _DeleteModifyResolution.skip,
                      }),
                    ),
              child: const Text('全部跳过'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () {
                      submitting = true;
                      setDialogState(() {});
                      Navigator.of(context).pop(
                        _DeleteModifyConflictDecision.fromSelections(
                          conflicts,
                          selections,
                        ),
                      );
                    },
              child: const Text('按选择继续'),
            ),
          ],
        ),
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

class _CloudSyncDeleteList extends StatelessWidget {
  const _CloudSyncDeleteList({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final path in paths.take(12))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  _formatDeletePath(path),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (paths.length > 12)
              Text(
                '还有 ${paths.length - 12} 个文件...',
                style: Theme.of(context).textTheme.bodySmall,
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

class _DeleteModifyConflictTile extends StatelessWidget {
  const _DeleteModifyConflictTile({
    required this.conflict,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final CloudSyncDeleteModifyConflict conflict;
  final _DeleteModifyResolution value;
  final bool enabled;
  final ValueChanged<_DeleteModifyResolution> onChanged;

  bool get _localModifiedRemoteDeleted {
    return conflict.direction == 'local_modified_remote_deleted';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatDeletePath(conflict.relativePath),
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(_description, style: textTheme.bodySmall),
            const SizedBox(height: 10),
            _SettingsSegmentedControl<_DeleteModifyResolution>(
              value: value,
              enabled: enabled,
              onChanged: onChanged,
              options: const [
                _SettingsSegmentOption(
                  value: _DeleteModifyResolution.overwriteRemote,
                  label: '覆盖远端',
                ),
                _SettingsSegmentOption(
                  value: _DeleteModifyResolution.skip,
                  label: '跳过',
                ),
                _SettingsSegmentOption(
                  value: _DeleteModifyResolution.overwriteLocal,
                  label: '覆盖本地',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _description {
    return _localModifiedRemoteDeleted ? '本地已修改，远端已删除' : '本地已删除，远端已修改';
  }
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
