part of 'settings_page.dart';

class _ProviderListItem extends StatefulWidget {
  const _ProviderListItem({
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final ProviderConfig provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ProviderListItem> createState() => _ProviderListItemState();
}

class _ProviderListItemState extends State<_ProviderListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.selected
        ? context.appCardBgHover
        : context.appCardBgHover;
    final active = widget.selected || _hovered;
    final contentColor = active
        ? context.appTextPrimary
        : context.appTextTertiary;
    final avatarBackgroundColor = active
        ? context.appCardBgHover
        : context.appCardBg;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 46,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  opacity: active ? 1 : 0,
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: backgroundColor),
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    builder: (context, color, _) {
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: color ?? backgroundColor,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned.fill(
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: contentColor),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, color, _) {
                    final animatedColor = color ?? contentColor;
                    return TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: avatarBackgroundColor),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      builder: (context, avatarColor, _) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor:
                                    avatarColor ?? avatarBackgroundColor,
                                child: Text(
                                  widget.provider.name.characters.first
                                      .toUpperCase(),
                                  style: TextStyle(
                                    color: animatedColor,
                                    height: 1,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.provider.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: animatedColor,
                                        height: 1.2,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ),
                              _StatusPill(enabled: widget.provider.enabled),
                            ],
                          ),
                        );
                      },
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

class _ProvidersPanel extends StatelessWidget {
  const _ProvidersPanel({
    required this.appDataDir,
    required this.apiLogEnabled,
    required this.aiClientService,
    required this.providers,
    required this.selectedProvider,
    required this.selectedProviderId,
    required this.onSelectedProviderChanged,
    required this.onProviderChanged,
    required this.onProviderDeleted,
    required this.onProviderAdded,
    required this.onModelChanged,
    required this.onModelDeleted,
  });

  final String appDataDir;
  final bool apiLogEnabled;
  final AiClientService aiClientService;
  final List<ProviderConfig> providers;
  final ProviderConfig? selectedProvider;
  final String? selectedProviderId;
  final ValueChanged<String> onSelectedProviderChanged;
  final Future<void> Function(ProviderConfig provider) onProviderChanged;
  final Future<void> Function(String id) onProviderDeleted;
  final Future<void> Function(ProviderConfig provider) onProviderAdded;
  final Future<void> Function(ProviderConfig provider, ModelConfig model)
  onModelChanged;
  final Future<void> Function(ProviderConfig provider, String modelId)
  onModelDeleted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 320,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: context.appBorder)),
          ),
          child: Column(
            children: [
              const TextField(
                decoration: InputDecoration(
                  hintText: '搜索供应商或分组',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: providers.isEmpty
                    ? Center(
                        child: Text(
                          '暂无供应商',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : ListView.separated(
                        itemCount: providers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final provider = providers[index];
                          return _ProviderListItem(
                            provider: provider,
                            selected:
                                provider.id == selectedProviderId ||
                                (selectedProviderId == null && index == 0),
                            onTap: () => onSelectedProviderChanged(provider.id),
                          );
                        },
                      ),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('add-provider-button'),
                  onPressed: () async {
                    final provider = await showDialog<ProviderConfig>(
                      context: context,
                      builder: (_) => const _AddProviderDialog(),
                    );
                    if (provider != null) {
                      await onProviderAdded(provider);
                    }
                  },
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('添加'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: selectedProvider == null
              ? const _EmptyProviderDetails()
              : _ProviderDetails(
                  appDataDir: appDataDir,
                  apiLogEnabled: apiLogEnabled,
                  aiClientService: aiClientService,
                  provider: selectedProvider!,
                  onProviderChanged: onProviderChanged,
                  onProviderDeleted: onProviderDeleted,
                  onModelChanged: onModelChanged,
                  onModelDeleted: onModelDeleted,
                ),
        ),
      ],
    );
  }
}

class _ProviderDetails extends StatefulWidget {
  const _ProviderDetails({
    required this.appDataDir,
    required this.apiLogEnabled,
    required this.aiClientService,
    required this.provider,
    required this.onProviderChanged,
    required this.onProviderDeleted,
    required this.onModelChanged,
    required this.onModelDeleted,
  });

  final String appDataDir;
  final bool apiLogEnabled;
  final AiClientService aiClientService;
  final ProviderConfig provider;
  final Future<void> Function(ProviderConfig provider) onProviderChanged;
  final Future<void> Function(String id) onProviderDeleted;
  final Future<void> Function(ProviderConfig provider, ModelConfig model)
  onModelChanged;
  final Future<void> Function(ProviderConfig provider, String modelId)
  onModelDeleted;

  @override
  State<_ProviderDetails> createState() => _ProviderDetailsState();
}

class _ProviderDetailsState extends State<_ProviderDetails> {
  final bool _testingConnection = false;
  bool _fetchingModels = false;
  String? _actionMessage;

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(36, 30, 36, 0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: _ProviderDetailsHeader(
                provider: provider,
                onProviderChanged: widget.onProviderChanged,
                onProviderDeleted: widget.onProviderDeleted,
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey('provider-details-body-${provider.id}'),
            padding: const EdgeInsets.fromLTRB(36, 14, 36, 42),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LooseField(
                      label: '名称',
                      value: provider.name,
                      onChanged: (value) {
                        widget.onProviderChanged(
                          provider.copyWith(name: value),
                        );
                      },
                    ),
                    _LooseField(
                      label: 'API Key',
                      value: provider.apiKey,
                      obscureText: true,
                      onChanged: (value) {
                        widget.onProviderChanged(
                          provider.copyWith(apiKey: value),
                        );
                      },
                    ),
                    _ProtocolField(
                      value: provider.protocol,
                      onChanged: (value) {
                        widget.onProviderChanged(
                          provider.copyWith(protocol: value),
                        );
                      },
                    ),
                    _LooseField(
                      label: 'API Base URL',
                      value: provider.baseUrl,
                      onChanged: (value) {
                        widget.onProviderChanged(
                          provider.copyWith(baseUrl: value),
                        );
                      },
                    ),
                    _LooseField(
                      label: 'API 路径',
                      value: provider.apiPath,
                      onChanged: (value) {
                        widget.onProviderChanged(
                          provider.copyWith(apiPath: value),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _ModelsList(
                      provider: provider,
                      testingConnection: _testingConnection,
                      fetchingModels: _fetchingModels,
                      actionMessage: _actionMessage,
                      onTestConnection: _testConnection,
                      onFetchModels: _fetchModels,
                      onModelChanged: widget.onModelChanged,
                      onModelDeleted: widget.onModelDeleted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _testConnection() async {
    if (widget.provider.models.isEmpty) {
      setState(() => _actionMessage = '请先添加至少一个模型。');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => _ProviderConnectionTestDialog(
        appDataDir: widget.appDataDir,
        apiLogEnabled: widget.apiLogEnabled,
        aiClientService: widget.aiClientService,
        provider: widget.provider,
      ),
    );
  }

  Future<void> _fetchModels() async {
    if (_fetchingModels) {
      return;
    }
    setState(() {
      _fetchingModels = true;
      _actionMessage = null;
    });
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => _ProviderModelFetchDialog(
          appDataDir: widget.appDataDir,
          apiLogEnabled: widget.apiLogEnabled,
          aiClientService: widget.aiClientService,
          provider: widget.provider,
          onModelAdded: (model) async {
            await widget.onModelChanged(widget.provider, model);
            if (mounted) {
              setState(() => _actionMessage = '已添加 ${model.displayName}');
            }
          },
          onModelRemoved: (modelId) async {
            await widget.onModelDeleted(widget.provider, modelId);
            if (mounted) {
              setState(() => _actionMessage = '已移除模型');
            }
          },
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _actionMessage = '获取模型失败，请检查供应商配置。');
      }
    } finally {
      if (mounted) {
        setState(() => _fetchingModels = false);
      }
    }
  }
}

class _ProviderDetailsHeader extends StatelessWidget {
  const _ProviderDetailsHeader({
    required this.provider,
    required this.onProviderChanged,
    required this.onProviderDeleted,
  });

  final ProviderConfig provider;
  final Future<void> Function(ProviderConfig provider) onProviderChanged;
  final Future<void> Function(String id) onProviderDeleted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: Row(
            children: [
              Text(
                provider.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              SizedBox(
                width: 48,
                height: 32,
                child: Transform.scale(
                  scale: 0.86,
                  child: Switch(
                    value: provider.enabled,
                    onChanged: (value) async =>
                        onProviderChanged(provider.copyWith(enabled: value)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: '删除供应商',
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => _DeleteProviderConfirmDialog(
                      providerName: provider.name,
                    ),
                  );
                  if (confirmed == true) {
                    await onProviderDeleted(provider.id);
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        const Divider(height: 1),
      ],
    );
  }
}

class _DeleteProviderConfirmDialog extends StatelessWidget {
  const _DeleteProviderConfirmDialog({required this.providerName});

  final String providerName;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.appCardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '删除供应商',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: context.appTextPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '确定要删除该供应商吗？此操作不可撤销。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.appTextPrimary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _DeleteDialogButton(
                    label: '取消',
                    isDestructive: false,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 10),
                  _DeleteDialogButton(
                    label: '删除',
                    isDestructive: true,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteDialogButton extends StatefulWidget {
  const _DeleteDialogButton({
    required this.label,
    required this.isDestructive,
    required this.onTap,
  });

  final String label;
  final bool isDestructive;
  final VoidCallback onTap;

  @override
  State<_DeleteDialogButton> createState() => _DeleteDialogButtonState();
}

class _DeleteDialogButtonState extends State<_DeleteDialogButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _hovered
        ? context.appCardBgHover
        : context.appCardBg;
    final foregroundColor = widget.isDestructive
        ? const Color(0xFFEF4444)
        : context.appTextPrimary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foregroundColor,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderConnectionTestDialog extends StatefulWidget {
  const _ProviderConnectionTestDialog({
    required this.appDataDir,
    required this.apiLogEnabled,
    required this.aiClientService,
    required this.provider,
  });

  final String appDataDir;
  final bool apiLogEnabled;
  final AiClientService aiClientService;
  final ProviderConfig provider;

  @override
  State<_ProviderConnectionTestDialog> createState() =>
      _ProviderConnectionTestDialogState();
}

class _ProviderConnectionTestDialogState
    extends State<_ProviderConnectionTestDialog> {
  String? _selectedModelId;
  _ProviderConnectionTestStatus? _status;
  bool _useStream = false;

  ModelConfig? get _selectedModel {
    final selectedId = _selectedModelId;
    if (selectedId == null) {
      return null;
    }
    return widget.provider.models.firstWhere(
      (model) => model.modelId == selectedId,
      orElse: () => widget.provider.models.first,
    );
  }

  bool get _testing =>
      _status?.kind == _ProviderConnectionTestStatusKind.testing;

  Future<void> _openModelPicker() async {
    final model = await showDialog<ModelConfig>(
      context: context,
      builder: (_) => _ProviderConnectionModelPickerDialog(
        provider: widget.provider,
        selectedModelId: _selectedModelId,
      ),
    );
    if (model == null || !mounted) {
      return;
    }
    setState(() {
      _selectedModelId = model.modelId;
      _status = null;
    });
  }

  Future<void> _runTest() async {
    final model = _selectedModel;
    if (_testing) {
      return;
    }
    if (model == null) {
      await _openModelPicker();
      return;
    }

    setState(() {
      _status = _ProviderConnectionTestStatus.testing(
        _useStream ? '流式测试中' : '测试中',
      );
    });

    try {
      final result = _useStream
          ? await widget.aiClientService.testProviderConnectionStream(
              appDataDir: widget.appDataDir,
              apiLogEnabled: widget.apiLogEnabled,
              provider: widget.provider,
              model: model,
            )
          : await widget.aiClientService.testProviderConnection(
              appDataDir: widget.appDataDir,
              apiLogEnabled: widget.apiLogEnabled,
              provider: widget.provider,
              model: model,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = result.ok
            ? _ProviderConnectionTestStatus.success(result.message)
            : _ProviderConnectionTestStatus.failure(result.message);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = _ProviderConnectionTestStatus.failure('连接测试失败');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedModel = _selectedModel;
    return Dialog(
      key: const ValueKey('provider-connection-test-dialog'),
      backgroundColor: context.appCardBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(
                '测试连接',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: context.appTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: _ProviderSelectedModelButton(
                model: selectedModel,
                onTap: _testing ? null : _openModelPicker,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    '使用流式',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: context.appTextPrimary,
                      height: 1.2,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 52,
                    height: 30,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Switch(
                        value: _useStream,
                        activeThumbColor: context.appCardBg,
                        activeTrackColor: context.appTextPrimary,
                        inactiveThumbColor: context.appCardBg,
                        inactiveTrackColor: context.appCardBgHover,
                        onChanged: _testing
                            ? null
                            : (value) => setState(() {
                                _useStream = value;
                                _status = null;
                              }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Center(
                child: _ProviderConnectionResultView(status: _status),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ProviderTestDialogButton(
                    label: '取消',
                    filled: false,
                    onTap: _testing ? null : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  _ProviderTestDialogButton(
                    label: _testing ? '测试中' : '测试',
                    filled: true,
                    onTap: _testing ? null : _runTest,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ProviderConnectionTestStatusKind { testing, success, failure }

class _ProviderConnectionTestStatus {
  const _ProviderConnectionTestStatus._({
    required this.kind,
    required this.message,
  });

  factory _ProviderConnectionTestStatus.testing(String message) {
    return _ProviderConnectionTestStatus._(
      kind: _ProviderConnectionTestStatusKind.testing,
      message: message,
    );
  }

  factory _ProviderConnectionTestStatus.success(String message) {
    return _ProviderConnectionTestStatus._(
      kind: _ProviderConnectionTestStatusKind.success,
      message: message.isEmpty ? '连接成功' : message,
    );
  }

  factory _ProviderConnectionTestStatus.failure(String message) {
    return _ProviderConnectionTestStatus._(
      kind: _ProviderConnectionTestStatusKind.failure,
      message: message.isEmpty ? '连接失败' : message,
    );
  }

  final _ProviderConnectionTestStatusKind kind;
  final String message;
}

class _ProviderSelectedModelButton extends StatefulWidget {
  const _ProviderSelectedModelButton({
    required this.model,
    required this.onTap,
  });

  final ModelConfig? model;
  final VoidCallback? onTap;

  @override
  State<_ProviderSelectedModelButton> createState() =>
      _ProviderSelectedModelButtonState();
}

class _ProviderSelectedModelButtonState
    extends State<_ProviderSelectedModelButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final model = widget.model;
    return MouseRegion(
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
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: 50,
          decoration: BoxDecoration(
            color: _hovered ? context.appCardBg : context.appCardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.appBorder),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (model != null)
                const Positioned(
                  left: 16,
                  child: _ProviderModelAvatar(size: 20),
                ),
              Center(
                child: Text(
                  model?.displayName ?? '选择模型',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.appTextPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
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

class _ProviderConnectionResultView extends StatelessWidget {
  const _ProviderConnectionResultView({required this.status});

  final _ProviderConnectionTestStatus? status;

  @override
  Widget build(BuildContext context) {
    final current = status;
    if (current == null) {
      return const SizedBox(height: 18);
    }
    if (current.kind == _ProviderConnectionTestStatusKind.testing) {
      return SizedBox(
        key: const ValueKey('provider-connection-testing'),
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(context.appTextSecondary),
        ),
      );
    }

    final success = current.kind == _ProviderConnectionTestStatusKind.success;
    return Tooltip(
      message: current.message,
      child: Text(
        success ? '测试成功' : current.message,
        key: ValueKey(
          success
              ? 'provider-connection-success'
              : 'provider-connection-failure',
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: success ? const Color(0xFF48B45A) : const Color(0xFFB24A4A),
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }
}

class _ProviderConnectionModelPickerDialog extends StatefulWidget {
  const _ProviderConnectionModelPickerDialog({
    required this.provider,
    required this.selectedModelId,
  });

  final ProviderConfig provider;
  final String? selectedModelId;

  @override
  State<_ProviderConnectionModelPickerDialog> createState() =>
      _ProviderConnectionModelPickerDialogState();
}

class _ProviderConnectionModelPickerDialogState
    extends State<_ProviderConnectionModelPickerDialog> {
  late final TextEditingController _controller = TextEditingController();
  String _query = '';
  String? _hoveredModelId;

  List<ModelConfig> get _models {
    final normalizedQuery = _query.trim().toLowerCase();
    final values = [...widget.provider.models]
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    if (normalizedQuery.isEmpty) {
      return values;
    }
    return values.where((model) {
      final searchable =
          '${model.displayName} ${model.modelId} ${widget.provider.name}'
              .toLowerCase();
      return searchable.contains(normalizedQuery);
    }).toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final models = _models;
    return Dialog(
      key: const ValueKey('provider-connection-model-picker-dialog'),
      backgroundColor: context.appCardBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 560,
        height: 600,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: _SettingsSearchField(
                controller: _controller,
                autofocus: true,
                hintText: '搜索模型或服务商',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: models.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的模型',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                      itemCount: models.length,
                      itemBuilder: (context, index) {
                        final model = models[index];
                        return _ProviderConnectionModelOptionTile(
                          model: model,
                          selected: model.modelId == widget.selectedModelId,
                          hovered: model.modelId == _hoveredModelId,
                          onHoverChanged: (hovered) {
                            setState(() {
                              if (hovered) {
                                _hoveredModelId = model.modelId;
                              } else if (_hoveredModelId == model.modelId) {
                                _hoveredModelId = null;
                              }
                            });
                          },
                          onTap: () => Navigator.of(context).pop(model),
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

class _ProviderConnectionModelOptionTile extends StatelessWidget {
  const _ProviderConnectionModelOptionTile({
    required this.model,
    required this.selected,
    required this.hovered,
    required this.onHoverChanged,
    required this.onTap,
  });

  final ModelConfig model;
  final bool selected;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = selected || hovered;
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
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  opacity: active ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? context.appCardBgHover
                          : context.appCardBgHover,
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const _ProviderModelAvatar(size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          model.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: active
                                    ? context.appTextPrimary
                                    : context.appTextSecondary,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                height: 1.2,
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: selected ? 1 : 0,
                        child: Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: context.appTextPrimary,
                        ),
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

class _ProviderModelAvatar extends StatelessWidget {
  const _ProviderModelAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.appCardBgHover,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Icon(
        Icons.auto_awesome_outlined,
        size: size * 0.62,
        color: context.appTextSecondary,
      ),
    );
  }
}

class _ProviderTestDialogButton extends StatefulWidget {
  const _ProviderTestDialogButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback? onTap;

  @override
  State<_ProviderTestDialogButton> createState() =>
      _ProviderTestDialogButtonState();
}

class _ProviderTestDialogButtonState extends State<_ProviderTestDialogButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final backgroundColor = widget.filled
        ? !enabled
              ? context.appTextTertiary.withValues(alpha: 0.48)
              : (_hovered
                    ? context.appTextPrimary.withValues(alpha: 0.88)
                    : context.appTextPrimary)
        : (_hovered && enabled ? context.appCardBgHover : context.appCardBg);
    final foregroundColor = widget.filled
        ? Colors.white
        : context.appTextPrimary;
    return MouseRegion(
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
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: widget.filled
                ? null
                : Border.all(color: context.appTextTertiary),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderModelFetchDialog extends StatefulWidget {
  const _ProviderModelFetchDialog({
    required this.appDataDir,
    required this.apiLogEnabled,
    required this.aiClientService,
    required this.provider,
    required this.onModelAdded,
    required this.onModelRemoved,
  });

  final String appDataDir;
  final bool apiLogEnabled;
  final AiClientService aiClientService;
  final ProviderConfig provider;
  final Future<void> Function(ModelConfig model) onModelAdded;
  final Future<void> Function(String modelId) onModelRemoved;

  @override
  State<_ProviderModelFetchDialog> createState() =>
      _ProviderModelFetchDialogState();
}

class _ProviderModelFetchDialogState extends State<_ProviderModelFetchDialog> {
  late final TextEditingController _controller = TextEditingController();
  late final ScrollController _scrollController = ScrollController();
  late final Set<String> _selectedModelIds;
  final Set<String> _expandedGroups = {};
  final Set<String> _busyModelIds = {};

  List<ModelConfig> _models = const [];
  String _query = '';
  String? _errorMessage;
  String? _hoveredGroup;
  String? _hoveredModelId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedModelIds = {
      for (final model in widget.provider.models) model.modelId,
    };
    _loadModels();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<_ProviderModelGroup> get _groups {
    final normalizedQuery = _query.trim().toLowerCase();
    final grouped = <String, List<ModelConfig>>{};
    for (final model in _models) {
      final groupName = _providerModelGroupName(model.modelId);
      final searchable = '${model.displayName} ${model.modelId} $groupName'
          .toLowerCase();
      if (normalizedQuery.isNotEmpty && !searchable.contains(normalizedQuery)) {
        continue;
      }
      grouped.putIfAbsent(groupName, () => <ModelConfig>[]).add(model);
    }

    final groupNames = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      for (final groupName in groupNames)
        _ProviderModelGroup(
          name: groupName,
          models: grouped[groupName]!
            ..sort(
              (a, b) => a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              ),
            ),
        ),
    ];
  }

  Future<void> _loadModels() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.aiClientService.fetchProviderModels(
        appDataDir: widget.appDataDir,
        apiLogEnabled: widget.apiLogEnabled,
        provider: widget.provider,
      );
      if (!mounted) {
        return;
      }
      if (!result.ok) {
        setState(() {
          _loading = false;
          _models = const [];
          _errorMessage = result.errorMessage.isEmpty
              ? '获取模型失败，请检查供应商配置。'
              : result.errorMessage;
        });
        return;
      }

      final modelsById = <String, ModelConfig>{};
      for (final model in result.models) {
        final modelId = model.modelId.trim();
        if (modelId.isEmpty) {
          continue;
        }
        final rawDisplayName = model.displayName.trim();
        modelsById[modelId] = ModelConfig(
          modelId: modelId,
          displayName: _providerModelDisplayName(modelId, rawDisplayName),
        );
      }
      final models = modelsById.values.toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
      final groups = _buildProviderModelGroups(models);
      final selectedGroups = {
        for (final group in groups)
          if (group.models.any(
            (model) => _selectedModelIds.contains(model.modelId),
          ))
            group.name,
      };
      setState(() {
        _loading = false;
        _models = models;
        _expandedGroups
          ..clear()
          ..addAll(
            selectedGroups.isEmpty && groups.isNotEmpty
                ? {groups.first.name}
                : selectedGroups,
          );
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _models = const [];
          _errorMessage = '获取模型失败，请检查供应商配置。';
        });
      }
    }
  }

  Future<void> _toggleModel(ModelConfig model) async {
    if (_busyModelIds.contains(model.modelId)) {
      return;
    }
    final selected = _selectedModelIds.contains(model.modelId);
    setState(() {
      _busyModelIds.add(model.modelId);
      if (selected) {
        _selectedModelIds.remove(model.modelId);
      } else {
        _selectedModelIds.add(model.modelId);
      }
    });
    try {
      if (selected) {
        await widget.onModelRemoved(model.modelId);
      } else {
        await widget.onModelAdded(model);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (selected) {
            _selectedModelIds.add(model.modelId);
          } else {
            _selectedModelIds.remove(model.modelId);
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busyModelIds.remove(model.modelId));
      }
    }
  }

  void _toggleGroup(String groupName) {
    setState(() {
      if (_expandedGroups.contains(groupName)) {
        _expandedGroups.remove(groupName);
      } else {
        _expandedGroups.add(groupName);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final searching = _query.trim().isNotEmpty;
    return Dialog(
      key: const ValueKey('provider-model-fetch-dialog'),
      backgroundColor: context.appCardBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 720,
        height: 660,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.provider.name} 模型',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: context.appTextPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '选择要添加到当前提供商的模型',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: context.appTextTertiary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _loading ? null : _loadModels,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _SettingsSearchField(
                controller: _controller,
                autofocus: true,
                hintText: '搜索模型',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _loading
                    ? const _ProviderModelLoadingView()
                    : _errorMessage != null
                    ? _ProviderModelErrorView(
                        message: _errorMessage!,
                        onRetry: _loadModels,
                      )
                    : groups.isEmpty
                    ? _ProviderModelEmptyView(
                        message: _models.isEmpty ? '没有获取到模型' : '没有匹配的模型',
                      )
                    : ScrollConfiguration(
                        key: const ValueKey('provider-model-groups'),
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
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final group in groups)
                                  _ProviderModelGroupSection(
                                    group: group,
                                    expanded:
                                        searching ||
                                        _expandedGroups.contains(group.name),
                                    hoveredGroup: _hoveredGroup == group.name,
                                    selectedModelIds: _selectedModelIds,
                                    busyModelIds: _busyModelIds,
                                    hoveredModelId: _hoveredModelId,
                                    onGroupHoverChanged: (hovered) {
                                      setState(() {
                                        if (hovered) {
                                          _hoveredGroup = group.name;
                                        } else if (_hoveredGroup ==
                                            group.name) {
                                          _hoveredGroup = null;
                                        }
                                      });
                                    },
                                    onGroupTap: () => _toggleGroup(group.name),
                                    onModelHoverChanged: (modelId, hovered) {
                                      setState(() {
                                        if (hovered) {
                                          _hoveredModelId = modelId;
                                        } else if (_hoveredModelId == modelId) {
                                          _hoveredModelId = null;
                                        }
                                      });
                                    },
                                    onModelTap: _toggleModel,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderModelGroup {
  const _ProviderModelGroup({required this.name, required this.models});

  final String name;
  final List<ModelConfig> models;
}

class _ProviderModelGroupSection extends StatelessWidget {
  const _ProviderModelGroupSection({
    required this.group,
    required this.expanded,
    required this.hoveredGroup,
    required this.selectedModelIds,
    required this.busyModelIds,
    required this.hoveredModelId,
    required this.onGroupHoverChanged,
    required this.onGroupTap,
    required this.onModelHoverChanged,
    required this.onModelTap,
  });

  final _ProviderModelGroup group;
  final bool expanded;
  final bool hoveredGroup;
  final Set<String> selectedModelIds;
  final Set<String> busyModelIds;
  final String? hoveredModelId;
  final ValueChanged<bool> onGroupHoverChanged;
  final VoidCallback onGroupTap;
  final void Function(String modelId, bool hovered) onModelHoverChanged;
  final ValueChanged<ModelConfig> onModelTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          _ProviderModelGroupHeader(
            name: group.name,
            count: group.models.length,
            expanded: expanded,
            hovered: hoveredGroup,
            onHoverChanged: onGroupHoverChanged,
            onTap: onGroupTap,
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
                        for (final model in group.models)
                          _ProviderModelOptionTile(
                            model: model,
                            selected: selectedModelIds.contains(model.modelId),
                            busy: busyModelIds.contains(model.modelId),
                            hovered: hoveredModelId == model.modelId,
                            onHoverChanged: (hovered) =>
                                onModelHoverChanged(model.modelId, hovered),
                            onTap: () => onModelTap(model),
                          ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderModelGroupHeader extends StatefulWidget {
  const _ProviderModelGroupHeader({
    required this.name,
    required this.count,
    required this.expanded,
    required this.hovered,
    required this.onHoverChanged,
    required this.onTap,
  });

  final String name;
  final int count;
  final bool expanded;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;

  @override
  State<_ProviderModelGroupHeader> createState() =>
      _ProviderModelGroupHeaderState();
}

class _ProviderModelGroupHeaderState extends State<_ProviderModelGroupHeader> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.expanded
        ? context.appCardBgHover
        : widget.hovered
        ? context.appCardBg
        : context.appCardBg;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => widget.onHoverChanged(true),
      onExit: (_) => widget.onHoverChanged(false),
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
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 130),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        AnimatedRotation(
                          turns: widget.expanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 19,
                            color: context.appTextSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.name,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: context.appTextPrimary,
                                  fontWeight: FontWeight.w600,
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
                            color: context.appCardBg.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${widget.count}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: context.appTextTertiary,
                                  fontSize: 12,
                                  height: 1.1,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderModelOptionTile extends StatelessWidget {
  const _ProviderModelOptionTile({
    required this.model,
    required this.selected,
    required this.busy,
    required this.hovered,
    required this.onHoverChanged,
    required this.onTap,
  });

  final ModelConfig model;
  final bool selected;
  final bool busy;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = selected || hovered;
    return MouseRegion(
      cursor: busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy ? null : onTap,
        child: SizedBox(
          height: 50,
          child: Stack(
            children: [
              Positioned(
                left: 28,
                top: 0,
                right: 0,
                bottom: 5,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  opacity: active ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? context.appCardBgHover
                          : context.appCardBgHover,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 28,
                top: 0,
                right: 0,
                bottom: 5,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: active
                                    ? context.appTextPrimary
                                    : context.appTextSecondary,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                height: 1.2,
                              ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _ProviderModelToggleButton(
                        selected: selected,
                        busy: busy,
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

class _ProviderModelToggleButton extends StatelessWidget {
  const _ProviderModelToggleButton({
    required this.selected,
    required this.busy,
  });

  final bool selected;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: selected ? context.appTextPrimary : context.appCardBgHover,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Center(
        child: busy
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.7,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    selected ? Colors.white : context.appTextSecondary,
                  ),
                ),
              )
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: Icon(
                  selected ? Icons.remove_rounded : Icons.add_rounded,
                  key: ValueKey(selected),
                  size: 17,
                  color: selected ? Colors.white : context.appTextPrimary,
                ),
              ),
      ),
    );
  }
}

class _ProviderModelLoadingView extends StatelessWidget {
  const _ProviderModelLoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('provider-model-loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(
                context.appTextTertiary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '正在获取模型...',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.appTextTertiary),
          ),
        ],
      ),
    );
  }
}

class _ProviderModelErrorView extends StatelessWidget {
  const _ProviderModelErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('provider-model-error'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.appTextTertiary),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _ProviderModelEmptyView extends StatelessWidget {
  const _ProviderModelEmptyView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('provider-model-empty'),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.appTextTertiary),
      ),
    );
  }
}

List<_ProviderModelGroup> _buildProviderModelGroups(List<ModelConfig> models) {
  final grouped = <String, List<ModelConfig>>{};
  for (final model in models) {
    grouped
        .putIfAbsent(_providerModelGroupName(model.modelId), () => [])
        .add(model);
  }
  final groupNames = grouped.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [
    for (final groupName in groupNames)
      _ProviderModelGroup(
        name: groupName,
        models: grouped[groupName]!
          ..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          ),
      ),
  ];
}

String _providerModelGroupName(String modelId) {
  final slashIndex = modelId.indexOf('/');
  if (slashIndex > 0) {
    return modelId.substring(0, slashIndex);
  }
  return '其他模型';
}

String _providerModelDisplayName(String modelId, String displayName) {
  if (displayName.isNotEmpty && displayName != modelId) {
    return displayName;
  }
  final slashIndex = modelId.lastIndexOf('/');
  if (slashIndex >= 0 && slashIndex < modelId.length - 1) {
    return modelId.substring(slashIndex + 1);
  }
  return modelId;
}

class _ModelsList extends StatelessWidget {
  const _ModelsList({
    required this.provider,
    required this.testingConnection,
    required this.fetchingModels,
    required this.actionMessage,
    required this.onTestConnection,
    required this.onFetchModels,
    required this.onModelChanged,
    required this.onModelDeleted,
  });

  final ProviderConfig provider;
  final bool testingConnection;
  final bool fetchingModels;
  final String? actionMessage;
  final VoidCallback onTestConnection;
  final VoidCallback onFetchModels;
  final Future<void> Function(ProviderConfig provider, ModelConfig model)
  onModelChanged;
  final Future<void> Function(ProviderConfig provider, String modelId)
  onModelDeleted;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: '模型',
      titleAccessory: _ModelCountPill(count: provider.models.length),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModelHeaderIconButton(
            key: const ValueKey('test-provider-connection-button'),
            tooltip: testingConnection ? '测试中' : '测试连接',
            onPressed: testingConnection ? null : onTestConnection,
            icon: testingConnection
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cable_rounded, size: 16),
          ),
          const SizedBox(width: 4),
          _ModelHeaderIconButton(
            key: const ValueKey('fetch-provider-models-button'),
            tooltip: fetchingModels ? '获取中' : '获取模型',
            onPressed: fetchingModels ? null : onFetchModels,
            icon: fetchingModels
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined, size: 16),
          ),
          const SizedBox(width: 4),
          _ModelHeaderIconButton(
            key: const ValueKey('add-model-button'),
            tooltip: '添加模型',
            onPressed: () async {
              final model = await showDialog<ModelConfig>(
                context: context,
                builder: (_) => const _AddModelDialog(),
              );
              if (model != null) {
                await onModelChanged(provider, model);
              }
            },
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
      children: [
        if (actionMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                actionMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.appTextTertiary,
                ),
              ),
            ),
          ),
        if (provider.models.isEmpty)
          _SimpleRow(label: '暂无模型', value: '点击右上角添加')
        else
          for (final model in provider.models)
            Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.appBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      model.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.appTextPrimary,
                      ),
                    ),
                  ),
                  Text(
                    model.modelId,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  IconButton(
                    key: ValueKey('edit-model-${model.modelId}'),
                    tooltip: '编辑模型',
                    onPressed: () async {
                      final updated = await showDialog<ModelConfig>(
                        context: context,
                        builder: (_) => _EditModelDialog(model: model),
                      );
                      if (updated != null) {
                        await onModelChanged(provider, updated);
                      }
                    },
                    icon: const Icon(Icons.tune_rounded, size: 18),
                  ),
                  IconButton(
                    tooltip: '删除模型',
                    onPressed: () => onModelDeleted(provider, model.modelId),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _ModelCountPill extends StatelessWidget {
  const _ModelCountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      constraints: const BoxConstraints(minWidth: 30),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: context.appCardBgHover,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: context.appTextSecondary,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _ModelHeaderIconButton extends StatefulWidget {
  const _ModelHeaderIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  State<_ModelHeaderIconButton> createState() => _ModelHeaderIconButtonState();
}

class _ModelHeaderIconButtonState extends State<_ModelHeaderIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final active = enabled && _hovered;
    final iconColor = !enabled
        ? context.appTextTertiary.withValues(alpha: 0.56)
        : (active ? context.appTextPrimary : context.appTextTertiary);
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
            width: 32,
            height: 32,
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
                        color: context.appCardBgHover,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                IconTheme(
                  data: IconThemeData(color: iconColor, size: 16),
                  child: widget.icon,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddProviderDialog extends StatefulWidget {
  const _AddProviderDialog();

  @override
  State<_AddProviderDialog> createState() => _AddProviderDialogState();
}

class _AddProviderDialogState extends State<_AddProviderDialog> {
  String _template = 'OpenAI';
  bool _enabled = true;
  late final TextEditingController _nameController = TextEditingController(
    text: 'OpenAI',
  );
  final TextEditingController _apiKeyController = TextEditingController();
  late final TextEditingController _baseUrlController = TextEditingController(
    text: 'https://api.openai.com/v1',
  );
  late final TextEditingController _apiPathController = TextEditingController(
    text: '/chat/completions',
  );

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _apiPathController.dispose();
    super.dispose();
  }

  void _selectTemplate(String template) {
    final provider = ProviderConfig.template(template);
    setState(() {
      _template = template;
      _nameController.text = provider.name;
      _baseUrlController.text = provider.baseUrl;
      _apiPathController.text = provider.apiPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: '添加供应商',
      width: 760,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final template in ProviderConfig.templateNames)
                SizedBox(
                  width: 166,
                  child: _ProviderTemplateChip(
                    label: template,
                    selected: _template == template,
                    onTap: () => _selectTemplate(template),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _DialogSwitchRow(
            label: '是否启用',
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          _DialogTextField(label: '名称', controller: _nameController),
          _DialogTextField(
            label: 'API Key',
            controller: _apiKeyController,
            obscureText: true,
          ),
          _DialogTextField(label: 'Base URL', controller: _baseUrlController),
          _DialogTextField(label: 'API 路径', controller: _apiPathController),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey('confirm-add-provider-button'),
              onPressed: () {
                final template = ProviderConfig.template(_template);
                Navigator.of(context).pop(
                  template.copyWith(
                    enabled: _enabled,
                    name: _nameController.text.trim(),
                    apiKey: _apiKeyController.text,
                    baseUrl: _baseUrlController.text.trim(),
                    apiPath: _apiPathController.text.trim(),
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('添加'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderTemplateChip extends StatefulWidget {
  const _ProviderTemplateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ProviderTemplateChip> createState() => _ProviderTemplateChipState();
}

class _ProviderTemplateChipState extends State<_ProviderTemplateChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final active = selected || _hovered;
    final backgroundColor = selected
        ? context.appCardBgHover
        : (_hovered ? context.appCardBgHover : context.appCardBg);
    final borderColor = selected ? context.appTextTertiary : context.appBorder;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          height: 42,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    opacity: selected ? 1 : 0,
                    child: Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: context.appTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: active
                          ? context.appTextPrimary
                          : context.appTextTertiary,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddModelDialog extends StatefulWidget {
  const _AddModelDialog();

  @override
  State<_AddModelDialog> createState() => _AddModelDialogState();
}

class _AddModelDialogState extends State<_AddModelDialog> {
  final TextEditingController _modelIdController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();

  @override
  void dispose() {
    _modelIdController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: '添加模型',
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DialogTextField(
            key: const ValueKey('add-model-id-field'),
            label: '模型 ID',
            controller: _modelIdController,
          ),
          _DialogTextField(
            key: const ValueKey('add-model-name-field'),
            label: '模型名称',
            controller: _displayNameController,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('confirm-add-model-button'),
              onPressed: () {
                final modelId = _modelIdController.text.trim();
                if (modelId.isEmpty) {
                  return;
                }
                Navigator.of(context).pop(
                  ModelConfig(
                    modelId: modelId,
                    displayName: _displayNameController.text.trim().isEmpty
                        ? modelId
                        : _displayNameController.text.trim(),
                  ),
                );
              },
              child: const Text('添加'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditModelDialog extends StatefulWidget {
  const _EditModelDialog({required this.model});

  final ModelConfig model;

  @override
  State<_EditModelDialog> createState() => _EditModelDialogState();
}

class _EditModelDialogState extends State<_EditModelDialog> {
  late final TextEditingController _displayNameController =
      TextEditingController(text: widget.model.displayName);
  late List<String> _modelTypes = [...widget.model.modelTypes];
  late List<String> _inputModes = [...widget.model.inputModes];
  late List<String> _capabilities = [...widget.model.capabilities];

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ModelEditDialogShell(
      title: '编辑模型',
      subtitle: '调整模型展示名称、输入类型与可用能力',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModelIdentityCard(
            modelId: widget.model.modelId,
            nameController: _displayNameController,
          ),
          const SizedBox(height: 14),
          _ModelOptionsCard(
            children: [
              _OptionGroup(
                label: '模型类型',
                values: const {'chat': '聊天', 'completion': '补全'},
                selected: _modelTypes,
                onChanged: (value) => setState(() => _modelTypes = value),
              ),
              _OptionGroup(
                label: '输入模式',
                values: const {'text': '文本', 'image': '图片'},
                selected: _inputModes,
                onChanged: (value) => setState(() => _inputModes = value),
              ),
              _OptionGroup(
                label: '能力',
                values: const {'tools': '工具', 'reasoning': '推理'},
                selected: _capabilities,
                onChanged: (value) => setState(() => _capabilities = value),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ModelDialogButton(
                label: '取消',
                filled: false,
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 10),
              _ModelDialogButton(
                key: const ValueKey('confirm-edit-model-button'),
                label: '确认',
                filled: true,
                onTap: () {
                  Navigator.of(context).pop(
                    widget.model.copyWith(
                      displayName: _displayNameController.text.trim().isEmpty
                          ? widget.model.modelId
                          : _displayNameController.text.trim(),
                      modelTypes: _modelTypes,
                      inputModes: _inputModes,
                      capabilities: _capabilities,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModelEditDialogShell extends StatelessWidget {
  const _ModelEditDialogShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.appCardBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: context.appTextPrimary,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: context.appTextTertiary,
                                height: 1.25,
                              ),
                        ),
                      ],
                    ),
                  ),
                  _ModelDialogIconButton(
                    tooltip: '关闭',
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelIdentityCard extends StatelessWidget {
  const _ModelIdentityCard({
    required this.modelId,
    required this.nameController,
  });

  final String modelId;
  final TextEditingController nameController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ModelReadOnlyField(label: '模型 ID', value: modelId),
        const SizedBox(height: 10),
        _ModelTextField(
          key: const ValueKey('edit-model-name-field'),
          label: '模型名称',
          controller: nameController,
        ),
      ],
    );
  }
}

class _ModelOptionsCard extends StatelessWidget {
  const _ModelOptionsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (index, child) in children.indexed) ...[
          child,
          if (index != children.length - 1)
            Divider(height: 1, color: context.appBorder),
        ],
      ],
    );
  }
}

class _OptionGroup extends StatelessWidget {
  const _OptionGroup({
    required this.label,
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final Map<String, String> values;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.appTextPrimary,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in values.entries)
                  _ModelOptionChip(
                    label: entry.value,
                    selected: selected.contains(entry.key),
                    onTap: () {
                      final next = [...selected];
                      if (selected.contains(entry.key)) {
                        next.remove(entry.key);
                      } else {
                        next.add(entry.key);
                      }
                      onChanged(next);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelOptionChip extends StatefulWidget {
  const _ModelOptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ModelOptionChip> createState() => _ModelOptionChipState();
}

class _ModelOptionChipState extends State<_ModelOptionChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final background = selected
        ? context.appCardBgHover
        : (_hovered ? context.appCardBgHover : context.appCardBg);
    final foreground = context.appTextPrimary;
    final borderColor = selected ? context.appTextTertiary : context.appBorder;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          width: 116,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.appCardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 15,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  opacity: selected ? 1 : 0,
                  child: Icon(Icons.check_rounded, size: 15, color: foreground),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelReadOnlyField extends StatelessWidget {
  const _ModelReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _ModelFieldShell(
      label: label,
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              value,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: context.appTextPrimary,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _ModelCopyIconButton(value: value),
        ],
      ),
    );
  }
}

class _ModelCopyIconButton extends StatefulWidget {
  const _ModelCopyIconButton({required this.value});

  final String value;

  @override
  State<_ModelCopyIconButton> createState() => _ModelCopyIconButtonState();
}

class _ModelCopyIconButtonState extends State<_ModelCopyIconButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ModelDialogIconButton(
      tooltip: _copied ? '已复制' : '复制模型 ID',
      icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
      active: _copied,
      onTap: _copy,
    );
  }
}

class _ModelTextField extends StatelessWidget {
  const _ModelTextField({
    super.key,
    required this.label,
    required this.controller,
  });

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return _ModelFieldShell(
      label: label,
      child: TextField(
        controller: controller,
        textAlignVertical: TextAlignVertical.center,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: context.appTextPrimary,
          height: 1.2,
        ),
      ),
    );
  }
}

class _ModelFieldShell extends StatelessWidget {
  const _ModelFieldShell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.appTextTertiary,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ],
      ),
    );
  }
}

class _ModelDialogButton extends StatefulWidget {
  const _ModelDialogButton({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  State<_ModelDialogButton> createState() => _ModelDialogButtonState();
}

class _ModelDialogButtonState extends State<_ModelDialogButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final background = widget.filled
        ? (_hovered
              ? context.appTextPrimary.withValues(alpha: 0.88)
              : context.appTextPrimary)
        : (_hovered ? context.appCardBgHover : context.appCardBg);
    final foreground = widget.filled ? Colors.white : context.appTextPrimary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: context.appCardBg,
            borderRadius: BorderRadius.circular(999),
            border: widget.filled ? null : Border.all(color: context.appBorder),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelDialogIconButton extends StatefulWidget {
  const _ModelDialogIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_ModelDialogIconButton> createState() => _ModelDialogIconButtonState();
}

class _ModelDialogIconButtonState extends State<_ModelDialogIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active || _hovered;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOutCubic,
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: active ? context.appCardBgHover : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TweenAnimationBuilder<double>(
              key: ValueKey(widget.icon),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              builder: (context, opacity, child) {
                return Opacity(opacity: opacity, child: child);
              },
              child: Icon(
                widget.icon,
                size: 18,
                color: active
                    ? context.appTextPrimary
                    : context.appTextTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
