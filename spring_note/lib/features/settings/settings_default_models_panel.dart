part of 'settings_page.dart';

class _DefaultModelsPanel extends StatelessWidget {
  const _DefaultModelsPanel({
    required this.config,
    required this.models,
    required this.onChanged,
  });

  final AppConfig config;
  final List<_ProviderModelOption> models;
  final ValueChanged<AppConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsScrollFrame(
      maxWidth: 1120,
      children: [
        _DefaultModelCard(
          title: '智能生成模型',
          description: '用于首页随手记录后的结构化整理和日报合并。',
          value: config.defaultModels['intelligentGenerationModel'],
          models: models,
          onSelected: (value) =>
              _setDefault('intelligentGenerationModel', value),
        ),
        _DefaultModelCard(
          title: '编辑补全模型',
          description: '用于便签页补全。模型类型包含补全时，默认按 completions FIM 调用。',
          value: config.defaultModels['editCompletionModel'],
          models: models
              .where((option) => option.model.modelTypes.contains('completion'))
              .toList(),
          onSelected: (value) => _setDefault('editCompletionModel', value),
        ),
        _DefaultModelCard(
          title: '回忆书模型',
          description: '用于回忆书问答和历史记录检索回答。',
          value: config.defaultModels['memoryBookModel'],
          models: models,
          onSelected: (value) => _setDefault('memoryBookModel', value),
        ),
      ],
    );
  }

  void _setDefault(String key, String? value) {
    final defaultModels = Map<String, String?>.from(config.defaultModels);
    defaultModels[key] = value;
    onChanged(config.copyWith(defaultModels: defaultModels));
  }
}

class _ProviderModelOption {
  const _ProviderModelOption({required this.provider, required this.model});

  final ProviderConfig provider;
  final ModelConfig model;

  String get value =>
      ModelReference.encode(providerId: provider.id, modelId: model.modelId);
}

class _DefaultModelCard extends StatelessWidget {
  const _DefaultModelCard({
    required this.title,
    required this.description,
    required this.value,
    required this.models,
    required this.onSelected,
  });

  final String title;
  final String description;
  final String? value;
  final List<_ProviderModelOption> models;
  final ValueChanged<String?> onSelected;

  Future<void> _openPicker(BuildContext context) async {
    final result = await showDialog<_ModelSelectionResult>(
      context: context,
      builder: (_) => _ModelPickerDialog(
        title: title,
        models: models,
        selectedValue: value,
      ),
    );
    if (result != null) {
      onSelected(result.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedRef = ModelReference.parse(value);
    final selected = selectedRef == null
        ? null
        : models
              .where(
                (option) => selectedRef.matches(
                  providerId: option.provider.id,
                  modelId: option.model.modelId,
                ),
              )
              .firstOrNull;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border.all(color: context.appBorder),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          MouseRegion(
            key: ValueKey('default-model-$title'),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openPicker(context),
              child: Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: context.appCardBgHover,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: value == null
                          ? context.appCardBgHover
                          : const Color(0xFFDCFCE7),
                      child: Text(
                        value == null ? '未' : '已',
                        style: TextStyle(
                          color: value == null
                              ? context.appTextSecondary
                              : const Color(0xFF166534),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        selected == null
                            ? '未选择模型'
                            : '${selected.model.displayName} · ${selected.provider.name}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.appTextPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more_rounded,
                      color: context.appTextTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelSelectionResult {
  const _ModelSelectionResult(this.value);

  final String? value;
}

class _ModelPickerDialog extends StatefulWidget {
  const _ModelPickerDialog({
    required this.title,
    required this.models,
    required this.selectedValue,
  });

  final String title;
  final List<_ProviderModelOption> models;
  final String? selectedValue;

  @override
  State<_ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<_ModelPickerDialog> {
  late final TextEditingController _controller = TextEditingController();
  late final ScrollController _scrollController = ScrollController();
  String _query = '';
  String? _hoveredOptionKey;
  String? _hoveredProviderId;
  final Set<String> _expandedProviderIds = {};

  List<_ProviderModelOption> get _filteredModels {
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return widget.models;
    }
    return widget.models.where((model) {
      return '${model.model.displayName} ${model.model.modelId} ${model.provider.name}'
          .toLowerCase()
          .contains(normalizedQuery);
    }).toList();
  }

  bool get _showNoneOption {
    final normalizedQuery = _query.trim().toLowerCase();
    return normalizedQuery.isEmpty || '未选择'.contains(normalizedQuery);
  }

  List<_ModelPickerProviderGroup> get _groups {
    final groupsByProvider = <String, _ModelPickerProviderGroup>{};
    for (final option in _filteredModels) {
      groupsByProvider
          .putIfAbsent(
            option.provider.id,
            () => _ModelPickerProviderGroup(
              provider: option.provider,
              models: <_ProviderModelOption>[],
            ),
          )
          .models
          .add(option);
    }
    return groupsByProvider.values.toList();
  }

  @override
  void initState() {
    super.initState();
    final selectedRef = ModelReference.parse(widget.selectedValue);
    final selectedProviderId = selectedRef == null
        ? null
        : widget.models
              .where(
                (option) => selectedRef.matches(
                  providerId: option.provider.id,
                  modelId: option.model.modelId,
                ),
              )
              .firstOrNull
              ?.provider
              .id;
    final initialProviderId =
        selectedProviderId ?? widget.models.firstOrNull?.provider.id;
    if (initialProviderId != null) {
      _expandedProviderIds.add(initialProviderId);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _providerExpanded(String providerId) {
    if (_query.trim().isNotEmpty) {
      return true;
    }
    return _expandedProviderIds.contains(providerId);
  }

  void _toggleProvider(String providerId) {
    setState(() {
      if (_expandedProviderIds.contains(providerId)) {
        _expandedProviderIds.remove(providerId);
      } else {
        _expandedProviderIds.add(providerId);
      }
    });
  }

  void _setHoveredOption(String optionKey, bool hovered) {
    setState(() {
      if (hovered) {
        _hoveredOptionKey = optionKey;
      } else if (_hoveredOptionKey == optionKey) {
        _hoveredOptionKey = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final showNoneOption = _showNoneOption;
    final selectedRef = ModelReference.parse(widget.selectedValue);
    return Dialog(
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
                          '选择${widget.title}',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: context.appTextPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '按供应商选择默认模型',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: context.appTextTertiary),
                        ),
                      ],
                    ),
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
              child: groups.isEmpty && !showNoneOption
                  ? Center(
                      child: Text(
                        '没有匹配的模型',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ScrollConfiguration(
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
                              if (showNoneOption)
                                _ModelOptionTile(
                                  model: null,
                                  selected: selectedRef == null,
                                  hovered: _hoveredOptionKey == '__none__',
                                  onHoverChanged: (hovered) =>
                                      _setHoveredOption('__none__', hovered),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pop(const _ModelSelectionResult(null)),
                                ),
                              for (final group in groups) ...[
                                _ProviderModelGroupHeader(
                                  name: group.provider.name,
                                  count: group.models.length,
                                  expanded: _providerExpanded(
                                    group.provider.id,
                                  ),
                                  hovered:
                                      _hoveredProviderId == group.provider.id,
                                  onHoverChanged: (hovered) {
                                    setState(() {
                                      if (hovered) {
                                        _hoveredProviderId = group.provider.id;
                                      } else if (_hoveredProviderId ==
                                          group.provider.id) {
                                        _hoveredProviderId = null;
                                      }
                                    });
                                  },
                                  onTap: () =>
                                      _toggleProvider(group.provider.id),
                                ),
                                ClipRect(
                                  child: AnimatedSize(
                                    duration: const Duration(milliseconds: 280),
                                    reverseDuration: const Duration(
                                      milliseconds: 190,
                                    ),
                                    curve: Curves.easeOutCubic,
                                    alignment: Alignment.topCenter,
                                    child: _providerExpanded(group.provider.id)
                                        ? Column(
                                            children: [
                                              const SizedBox(height: 6),
                                              for (final model in group.models)
                                                _ModelOptionTile(
                                                  model: model,
                                                  selected:
                                                      selectedRef?.matches(
                                                        providerId:
                                                            model.provider.id,
                                                        modelId:
                                                            model.model.modelId,
                                                      ) ??
                                                      false,
                                                  hovered:
                                                      _hoveredOptionKey ==
                                                      model.value,
                                                  onHoverChanged: (hovered) =>
                                                      _setHoveredOption(
                                                        model.value,
                                                        hovered,
                                                      ),
                                                  onTap: () =>
                                                      Navigator.of(context).pop(
                                                        _ModelSelectionResult(
                                                          model.value,
                                                        ),
                                                      ),
                                                ),
                                            ],
                                          )
                                        : const SizedBox(
                                            width: double.infinity,
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
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

class _ModelPickerProviderGroup {
  const _ModelPickerProviderGroup({
    required this.provider,
    required this.models,
  });

  final ProviderConfig provider;
  final List<_ProviderModelOption> models;
}

class _ModelOptionTile extends StatelessWidget {
  const _ModelOptionTile({
    required this.model,
    required this.selected,
    required this.hovered,
    required this.onHoverChanged,
    required this.onTap,
  });

  final _ProviderModelOption? model;
  final bool selected;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = selected || hovered;
    final backgroundColor = selected
        ? context.appCardBgHover
        : context.appCardBgHover;
    final option = model;
    final title = option?.model.displayName ?? '未选择';
    final contentColor = active
        ? context.appTextPrimary
        : context.appTextSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: option == null ? 48 : 50,
          child: Stack(
            children: [
              Positioned(
                left: option == null ? 0 : 28,
                top: 0,
                right: 0,
                bottom: option == null ? 4 : 5,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  opacity: active ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(
                        option == null ? 13 : 14,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: option == null ? 0 : 28,
                top: 0,
                right: 0,
                bottom: option == null ? 4 : 5,
                child: Padding(
                  padding: option == null
                      ? const EdgeInsets.symmetric(horizontal: 12)
                      : const EdgeInsets.only(left: 14, right: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: contentColor,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                height: 1.2,
                              ),
                        ),
                      ),
                      if (selected)
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
