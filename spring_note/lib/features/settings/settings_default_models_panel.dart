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
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
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
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: value == null
                          ? const Color(0xFFE0E0E0)
                          : const Color(0xFFDCFCE7),
                      child: Text(
                        value == null ? '未' : '已',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        selected == null
                            ? '未选择模型'
                            : '${selected.model.displayName} · ${selected.provider.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded),
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
  String _query = '';
  String? _hoveredOptionKey;

  List<_ProviderModelOption?> get _models {
    final normalizedQuery = _query.trim().toLowerCase();
    final values = <_ProviderModelOption?>[null, ...widget.models];
    if (normalizedQuery.isEmpty) {
      return values;
    }
    return values.where((model) {
      if (model == null) {
        return '未选择'.contains(normalizedQuery);
      }
      return '${model.model.displayName} ${model.model.modelId} ${model.provider.name}'
          .toLowerCase()
          .contains(normalizedQuery);
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
    final selectedRef = ModelReference.parse(widget.selectedValue);
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
                  Expanded(
                    child: Text(
                      '选择${widget.title}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
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
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: _SettingsSearchField(
                controller: _controller,
                autofocus: true,
                hintText: '搜索模型',
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
                        final optionKey = model?.value ?? '__none__';
                        return _ModelOptionTile(
                          model: model,
                          selected: model == null
                              ? selectedRef == null
                              : selectedRef?.matches(
                                      providerId: model.provider.id,
                                      modelId: model.model.modelId,
                                    ) ??
                                    false,
                          hovered: optionKey == _hoveredOptionKey,
                          onHoverChanged: (hovered) {
                            setState(() {
                              if (hovered) {
                                _hoveredOptionKey = optionKey;
                              } else if (_hoveredOptionKey == optionKey) {
                                _hoveredOptionKey = null;
                              }
                            });
                          },
                          onTap: () => Navigator.of(
                            context,
                          ).pop(_ModelSelectionResult(model?.value)),
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
        ? const Color(0xFFE2E2E2)
        : const Color(0xFFF5F5F5);
    final option = model;
    final title = option?.model.displayName ?? '未选择';
    final subtitle = option == null
        ? null
        : '${option.provider.name} · ${option.model.modelId}';
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
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: contentColor,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    height: 1.1,
                                  ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppTheme.textSubtle,
                                      height: 1.1,
                                    ),
                              ),
                          ],
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
