import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../core/models/app_config.dart';
import '../../core/models/local_data_state.dart';
import '../../core/models/model_config.dart';
import '../../core/models/provider_config.dart';
import '../../core/services/ai_client_service.dart';
import '../../core/services/local_data_service.dart';
import '../../core/services/stats_service.dart';
import '../../core/theme/app_theme.dart';
import '../../src/rust/stats.dart' as rust_stats;

enum _SettingsSection {
  preferences('偏好设置', Icons.tune_rounded),
  providers('供应商', Icons.power_rounded),
  models('默认模型', Icons.smart_toy_outlined),
  hotkeys('快捷键', Icons.keyboard_rounded),
  stats('统计', Icons.bar_chart_rounded),
  about('关于', Icons.info_outline_rounded);

  const _SettingsSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.localDataState,
    this.localDataService = const LocalDataService(),
    this.onConfigChanged,
  });

  final LocalDataState localDataState;
  final LocalDataService localDataService;
  final ValueChanged<AppConfig>? onConfigChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _SettingsSection _section = _SettingsSection.preferences;
  late AppConfig _config = widget.localDataState.config;
  String? _selectedProviderId;
  bool _saving = false;

  ProviderConfig? get _selectedProvider {
    if (_config.providers.isEmpty) {
      return null;
    }
    return _config.providers.firstWhere(
      (provider) => provider.id == _selectedProviderId,
      orElse: () => _config.providers.first,
    );
  }

  List<ModelConfig> get _allModels {
    return [
      for (final provider in _config.providers)
        for (final model in provider.models) model,
    ];
  }

  Future<void> _updateConfig(AppConfig config) async {
    setState(() {
      _config = config;
      _saving = true;
      if (_selectedProviderId == null && config.providers.isNotEmpty) {
        _selectedProviderId = config.providers.first.id;
      }
    });
    await widget.localDataService.saveConfig(config);
    widget.onConfigChanged?.call(config);
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Future<void> _updateProvider(ProviderConfig provider) async {
    final providers = [
      for (final item in _config.providers)
        if (item.id == provider.id) provider else item,
    ];
    await _updateConfig(_config.copyWith(providers: providers));
  }

  Future<void> _deleteProvider(String id) async {
    final removedModelIds = _config.providers
        .where((provider) => provider.id == id)
        .expand((provider) => provider.models)
        .map((model) => model.modelId)
        .toSet();
    final providers = _config.providers
        .where((provider) => provider.id != id)
        .toList();
    final defaultModels = Map<String, String?>.from(_config.defaultModels);
    for (final entry in defaultModels.entries.toList()) {
      if (removedModelIds.contains(entry.value)) {
        defaultModels[entry.key] = null;
      }
    }
    await _updateConfig(
      _config.copyWith(providers: providers, defaultModels: defaultModels),
    );
    setState(
      () => _selectedProviderId = providers.isEmpty ? null : providers.first.id,
    );
  }

  Future<void> _addProvider(ProviderConfig provider) async {
    final providers = [..._config.providers, provider];
    await _updateConfig(_config.copyWith(providers: providers));
    setState(() => _selectedProviderId = provider.id);
  }

  Future<void> _upsertModel(ProviderConfig provider, ModelConfig model) async {
    final exists = provider.models.any((item) => item.modelId == model.modelId);
    final models = exists
        ? [
            for (final item in provider.models)
              if (item.modelId == model.modelId) model else item,
          ]
        : [...provider.models, model];
    await _updateProvider(provider.copyWith(models: models));
  }

  Future<void> _deleteModel(ProviderConfig provider, String modelId) async {
    final models = provider.models
        .where((model) => model.modelId != modelId)
        .toList();
    final defaultModels = Map<String, String?>.from(_config.defaultModels);
    for (final entry in defaultModels.entries.toList()) {
      if (entry.value == modelId) {
        defaultModels[entry.key] = null;
      }
    }
    final providers = [
      for (final item in _config.providers)
        if (item.id == provider.id) provider.copyWith(models: models) else item,
    ];
    await _updateConfig(
      _config.copyWith(providers: providers, defaultModels: defaultModels),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Row(
        children: [
          Container(
            width: 220,
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 18),
            decoration: const BoxDecoration(
              color: AppTheme.background,
              border: Border(right: BorderSide(color: Color(0xFFEEF2F7))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('设置', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    if (_saving)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                for (final section in _SettingsSection.values)
                  _SettingsNavItem(
                    section: section,
                    selected: section == _section,
                    onTap: () => setState(() => _section = section),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildSection()),
        ],
      ),
    );
  }

  Widget _buildSection() {
    return switch (_section) {
      _SettingsSection.preferences => _PreferencesPanel(
        config: _config,
        onChanged: _updateConfig,
        configPath: widget.localDataState.configPath,
      ),
      _SettingsSection.providers => _ProvidersPanel(
        appDataDir: widget.localDataState.dataDirectory,
        apiLogEnabled: _config.apiLogEnabled,
        providers: _config.providers,
        selectedProvider: _selectedProvider,
        selectedProviderId: _selectedProviderId,
        onSelectedProviderChanged: (id) =>
            setState(() => _selectedProviderId = id),
        onProviderChanged: _updateProvider,
        onProviderDeleted: _deleteProvider,
        onProviderAdded: _addProvider,
        onModelChanged: _upsertModel,
        onModelDeleted: _deleteModel,
      ),
      _SettingsSection.models => _DefaultModelsPanel(
        config: _config,
        models: _allModels,
        onChanged: _updateConfig,
      ),
      _SettingsSection.hotkeys => _HotkeysPanel(
        config: _config,
        onChanged: _updateConfig,
      ),
      _SettingsSection.stats => _StatsPanel(
        localDataState: widget.localDataState.copyWith(config: _config),
      ),
      _SettingsSection.about => const _AboutPanel(),
    };
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final _SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.surfaceMuted : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                section.icon,
                size: 15,
                color: selected ? AppTheme.text : AppTheme.textMuted,
              ),
              const SizedBox(width: 9),
              Text(
                section.label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? AppTheme.text : AppTheme.textMuted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreferencesPanel extends StatelessWidget {
  const _PreferencesPanel({
    required this.config,
    required this.onChanged,
    required this.configPath,
  });

  final AppConfig config;
  final ValueChanged<AppConfig> onChanged;
  final String configPath;

  @override
  Widget build(BuildContext context) {
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
            _TextSettingRow(
              label: '应用字体',
              value: config.appFont == 'system' ? '系统默认' : config.appFont,
              onChanged: (value) => onChanged(
                config.copyWith(
                  appFont: value.trim().isEmpty || value == '系统默认'
                      ? 'system'
                      : value,
                ),
              ),
              trailing: IconButton(
                tooltip: '重置字体',
                onPressed: () => onChanged(config.copyWith(appFont: 'system')),
                icon: const Icon(Icons.restart_alt_rounded, size: 17),
              ),
            ),
            _NumberSettingRow(
              label: '字体大小',
              value: config.fontScale,
              suffix: '%',
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
              onChanged: (value) =>
                  onChanged(config.copyWith(autoStart: value)),
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
          title: '组件设置',
          children: [
            _SwitchSettingRow(
              label: '显示桌面组件',
              value: config.showDesktopWidget,
              onChanged: (value) =>
                  onChanged(config.copyWith(showDesktopWidget: value)),
            ),
          ],
        ),
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

class _ProvidersPanel extends StatelessWidget {
  const _ProvidersPanel({
    required this.appDataDir,
    required this.apiLogEnabled,
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
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Color(0xFFEEF2F7))),
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

class _ProviderListItem extends StatelessWidget {
  const _ProviderListItem({
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final ProviderConfig provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.surfaceMuted : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFFEFF6FF),
              child: Text(provider.name.characters.first.toUpperCase()),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(provider.name, overflow: TextOverflow.ellipsis),
            ),
            _StatusPill(enabled: provider.enabled),
          ],
        ),
      ),
    );
  }
}

class _ProviderDetails extends StatefulWidget {
  const _ProviderDetails({
    required this.appDataDir,
    required this.apiLogEnabled,
    required this.provider,
    required this.onProviderChanged,
    required this.onProviderDeleted,
    required this.onModelChanged,
    required this.onModelDeleted,
  });

  final String appDataDir;
  final bool apiLogEnabled;
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
  final AiClientService _aiClientService = const AiClientService();
  bool _testingConnection = false;
  bool _fetchingModels = false;
  String? _actionMessage;

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return _SettingsScrollFrame(
      maxWidth: 1120,
      children: [
        Row(
          children: [
            Text(provider.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 10),
            Text(
              provider.protocol,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            Switch(
              value: provider.enabled,
              onChanged: (value) async =>
                  widget.onProviderChanged(provider.copyWith(enabled: value)),
            ),
            IconButton(
              tooltip: '删除供应商',
              onPressed: () async => widget.onProviderDeleted(provider.id),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        const Divider(height: 22),
        _LooseField(
          label: '名称',
          value: provider.name,
          onChanged: (value) {
            widget.onProviderChanged(provider.copyWith(name: value));
          },
        ),
        _LooseField(
          label: 'API Key',
          value: provider.apiKey,
          obscureText: true,
          onChanged: (value) {
            widget.onProviderChanged(provider.copyWith(apiKey: value));
          },
        ),
        _LooseField(
          label: 'API Base URL',
          value: provider.baseUrl,
          onChanged: (value) {
            widget.onProviderChanged(provider.copyWith(baseUrl: value));
          },
        ),
        _LooseField(
          label: 'API 路径',
          value: provider.apiPath,
          onChanged: (value) {
            widget.onProviderChanged(provider.copyWith(apiPath: value));
          },
        ),
        const SizedBox(height: 12),
        _ProviderActionsRow(
          testingConnection: _testingConnection,
          fetchingModels: _fetchingModels,
          message: _actionMessage,
          onTestConnection: _testConnection,
          onFetchModels: _fetchModels,
        ),
        const SizedBox(height: 10),
        _ModelsList(
          provider: provider,
          onModelChanged: widget.onModelChanged,
          onModelDeleted: widget.onModelDeleted,
        ),
      ],
    );
  }

  Future<void> _testConnection() async {
    final model = widget.provider.models.isEmpty
        ? null
        : widget.provider.models.first;
    if (model == null) {
      setState(() => _actionMessage = '请先添加至少一个模型。');
      return;
    }

    setState(() {
      _testingConnection = true;
      _actionMessage = null;
    });
    try {
      final result = await _aiClientService.testProviderConnection(
        appDataDir: widget.appDataDir,
        apiLogEnabled: widget.apiLogEnabled,
        provider: widget.provider,
        model: model,
      );
      if (!mounted) {
        return;
      }
      setState(() => _actionMessage = result.message);
    } catch (_) {
      if (mounted) {
        setState(() => _actionMessage = '连接测试失败，请检查 API Key、Base URL 和模型。');
      }
    } finally {
      if (mounted) {
        setState(() => _testingConnection = false);
      }
    }
  }

  Future<void> _fetchModels() async {
    setState(() {
      _fetchingModels = true;
      _actionMessage = null;
    });
    try {
      final result = await _aiClientService.fetchProviderModels(
        appDataDir: widget.appDataDir,
        apiLogEnabled: widget.apiLogEnabled,
        provider: widget.provider,
      );
      if (!mounted) {
        return;
      }
      if (!result.ok) {
        setState(() => _actionMessage = result.errorMessage);
        return;
      }
      final modelsById = {
        for (final model in widget.provider.models) model.modelId: model,
        for (final model in result.models)
          model.modelId: ModelConfig(
            modelId: model.modelId,
            displayName: model.displayName,
          ),
      };
      await widget.onProviderChanged(
        widget.provider.copyWith(models: modelsById.values.toList()),
      );
      if (mounted) {
        setState(() => _actionMessage = '已获取 ${result.models.length} 个模型。');
      }
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

class _ProviderActionsRow extends StatelessWidget {
  const _ProviderActionsRow({
    required this.testingConnection,
    required this.fetchingModels,
    required this.message,
    required this.onTestConnection,
    required this.onFetchModels,
  });

  final bool testingConnection;
  final bool fetchingModels;
  final String? message;
  final VoidCallback onTestConnection;
  final VoidCallback onFetchModels;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: testingConnection ? null : onTestConnection,
          icon: testingConnection
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cable_rounded, size: 16),
          label: Text(testingConnection ? '测试中' : '测试连接'),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: fetchingModels ? null : onFetchModels,
          icon: fetchingModels
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_download_outlined, size: 16),
          label: Text(fetchingModels ? '获取中' : '获取模型'),
        ),
        if (message != null) ...[
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSubtle),
            ),
          ),
        ] else
          const Spacer(),
      ],
    );
  }
}

class _ModelsList extends StatelessWidget {
  const _ModelsList({
    required this.provider,
    required this.onModelChanged,
    required this.onModelDeleted,
  });

  final ProviderConfig provider;
  final Future<void> Function(ProviderConfig provider, ModelConfig model)
  onModelChanged;
  final Future<void> Function(ProviderConfig provider, String modelId)
  onModelDeleted;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: '模型',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${provider.models.length}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          IconButton(
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
        if (provider.models.isEmpty)
          _SimpleRow(label: '暂无模型', value: '点击右上角添加')
        else
          for (final model in provider.models)
            Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      model.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppTheme.text),
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

class _DefaultModelsPanel extends StatelessWidget {
  const _DefaultModelsPanel({
    required this.config,
    required this.models,
    required this.onChanged,
  });

  final AppConfig config;
  final List<ModelConfig> models;
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
              .where((model) => model.modelTypes.contains('completion'))
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
  final List<ModelConfig> models;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = models
        .where((model) => model.modelId == value)
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
          PopupMenuButton<String?>(
            key: ValueKey('default-model-$title'),
            onSelected: onSelected,
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('未选择')),
              for (final model in models)
                PopupMenuItem(
                  value: model.modelId,
                  child: Text(model.displayName),
                ),
            ],
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
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFFDCFCE7),
                    child: Text(
                      value == null ? '未' : '已',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(selected?.displayName ?? '未选择模型')),
                  const Icon(Icons.expand_more_rounded),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HotkeysPanel extends StatelessWidget {
  const _HotkeysPanel({required this.config, required this.onChanged});

  final AppConfig config;
  final ValueChanged<AppConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final toggleWindow = config.hotkeys['toggleWindow'] ?? '';
    return _SettingsScrollFrame(
      maxWidth: 1120,
      children: [
        Text('快捷键', style: Theme.of(context).textTheme.titleLarge),
        _SettingsCard(
          title: '全局快捷键',
          children: [
            _TextSettingRow(
              label: '显示/隐藏页面',
              value: toggleWindow,
              onChanged: (value) {
                final hotkeys = Map<String, String?>.from(config.hotkeys);
                hotkeys['toggleWindow'] = value;
                onChanged(config.copyWith(hotkeys: hotkeys));
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '重置',
                    onPressed: () {
                      final hotkeys = Map<String, String?>.from(config.hotkeys);
                      hotkeys['toggleWindow'] = 'Ctrl+Shift+S';
                      onChanged(config.copyWith(hotkeys: hotkeys));
                    },
                    icon: const Icon(Icons.restart_alt_rounded, size: 17),
                  ),
                  IconButton(
                    tooltip: '清除',
                    onPressed: () {
                      final hotkeys = Map<String, String?>.from(config.hotkeys);
                      hotkeys['toggleWindow'] = '';
                      onChanged(config.copyWith(hotkeys: hotkeys));
                    },
                    icon: const Icon(Icons.close_rounded, size: 17),
                  ),
                  Switch(value: true, onChanged: (_) {}),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatsPanel extends StatefulWidget {
  const _StatsPanel({required this.localDataState});

  final LocalDataState localDataState;

  @override
  State<_StatsPanel> createState() => _StatsPanelState();
}

class _StatsPanelState extends State<_StatsPanel> {
  final StatsService _statsService = const StatsService();
  late Future<_StatsPanelData> _future = _loadStats();

  @override
  void didUpdateWidget(covariant _StatsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.localDataState.dataDirectory !=
        oldWidget.localDataState.dataDirectory) {
      _future = _loadStats();
    }
  }

  Future<_StatsPanelData> _loadStats() async {
    final today = DateTime.now();
    final trendStart = today.subtract(const Duration(days: 29));
    final heatmapStart = today.subtract(const Duration(days: 364));
    final results = await Future.wait([
      _statsService.readSnapshot(
        localDataState: widget.localDataState,
        start: trendStart,
        end: today,
      ),
      _statsService.readSnapshot(
        localDataState: widget.localDataState,
        start: heatmapStart,
        end: today,
      ),
    ]);
    return _StatsPanelData(recent: results[0], yearly: results[1]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StatsPanelData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final recent = data?.recent ?? StatsService.emptySnapshot;
        final yearly = data?.yearly ?? StatsService.emptySnapshot;
        final loading = snapshot.connectionState != ConnectionState.done;

        return _SettingsScrollFrame(
          maxWidth: 1120,
          children: [
            Row(
              children: [
                const Chip(label: Text('最近30天')),
                const SizedBox(width: 8),
                Chip(
                  label: Text(loading ? '读取中' : '已同步 SQLite'),
                  backgroundColor: const Color(0xFFF8FAFC),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '刷新统计',
                  onPressed: () => setState(() => _future = _loadStats()),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
              ],
            ),
            _SettingsCard(
              title: '年度热力图',
              trailing: Text(
                '365 天',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                  child: _YearHeatmap(activity: yearly.activity),
                ),
              ],
            ),
            _StatsMetricsGrid(snapshot: recent),
            _SettingsCard(
              title: '模型用量趋势',
              trailing: Text(
                '最近 30 天',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                  child: _UsageTrendChart(snapshot: recent),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _StatsPanelData {
  const _StatsPanelData({required this.recent, required this.yearly});

  final rust_stats.StatsSnapshot recent;
  final rust_stats.StatsSnapshot yearly;
}

class _StatsMetricsGrid extends StatelessWidget {
  const _StatsMetricsGrid({required this.snapshot});

  final rust_stats.StatsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final summary = snapshot.summary;
    final metrics = [
      ('总结数', summary.summaries),
      ('编辑补全次数', summary.fimCompletions),
      ('总记录数', summary.totalRecords),
      ('日报数', summary.dailyNotes),
      ('周报数', summary.weeklyNotes),
      ('月报数', summary.monthlyNotes),
      ('输入 Tokens', summary.inputTokens),
      ('输出 Tokens', summary.outputTokens),
      ('缓存 Tokens', summary.cachedTokens),
      ('应用启动次数', summary.appLaunches),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final metric in metrics)
          SizedBox(
            width: 190,
            child: _MetricCard(
              label: metric.$1,
              value: _formatNumber(metric.$2),
            ),
          ),
      ],
    );
  }
}

class _YearHeatmap extends StatelessWidget {
  const _YearHeatmap({required this.activity});

  final List<rust_stats.DailyActivity> activity;

  static const _colors = [
    Color(0xFFF1F5F9),
    Color(0xFFDCFCE7),
    Color(0xFFBBF7D0),
    Color(0xFF86EFAC),
    Color(0xFF4ADE80),
  ];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 364));
    final activityByDate = {for (final item in activity) item.date: item.count};
    final weeks = <List<DateTime>>[];
    var cursor = start;
    while (!cursor.isAfter(today)) {
      if (weeks.isEmpty || weeks.last.length == 7) {
        weeks.add([]);
      }
      weeks.last.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final week in weeks)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                children: [
                  for (final date in week)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _HeatmapCell(
                        date: date,
                        count:
                            activityByDate[StatsService.formatDate(date)] ?? 0,
                        colors: _colors,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.date,
    required this.count,
    required this.colors,
  });

  final DateTime date;
  final int count;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${StatsService.formatDate(date)}：$count 次记录',
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: colors[_level(count)],
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  int _level(int count) {
    if (count >= 8) {
      return 4;
    }
    if (count >= 5) {
      return 3;
    }
    if (count >= 3) {
      return 2;
    }
    if (count >= 1) {
      return 1;
    }
    return 0;
  }
}

class _UsageTrendChart extends StatefulWidget {
  const _UsageTrendChart({required this.snapshot});

  final rust_stats.StatsSnapshot snapshot;

  @override
  State<_UsageTrendChart> createState() => _UsageTrendChartState();
}

class _UsageTrendChartState extends State<_UsageTrendChart> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final usageByDate = {
      for (final item in widget.snapshot.tokenUsage) item.date: item,
    };
    final days = List.generate(30, (index) {
      final date = today.subtract(Duration(days: 29 - index));
      return _DailyUsagePoint(
        date: date,
        usage: usageByDate[StatsService.formatDate(date)],
      );
    });
    final maxTokens = days.fold<int>(
      1,
      (max, point) => point.totalTokens > max ? point.totalTokens : max,
    );
    final models = _topModelUsage(widget.snapshot.providerUsage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Listener(
          onPointerSignal: _handlePointerSignal,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = (days.length * 34).toDouble();
              return SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: contentWidth < constraints.maxWidth
                      ? constraints.maxWidth
                      : contentWidth,
                  height: 210,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final point in days)
                        Expanded(
                          child: _UsageBar(point: point, maxTokens: maxTokens),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (models.isEmpty)
              Text('暂无模型调用记录', style: Theme.of(context).textTheme.bodyMedium)
            else
              for (final model in models)
                Chip(
                  label: Text(
                    '${model.label} · ${_formatNumber(model.tokens)}',
                  ),
                  backgroundColor: const Color(0xFFF8FAFC),
                ),
          ],
        ),
      ],
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !_controller.hasClients ||
        _controller.position.maxScrollExtent <= 0) {
      return;
    }
    final next = (_controller.offset + event.scrollDelta.dy).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.jumpTo(next);
  }

  List<_ModelUsageTotal> _topModelUsage(
    List<rust_stats.ProviderTokenUsage> usage,
  ) {
    final totals = <String, int>{};
    for (final item in usage) {
      final key = '${item.providerName}/${item.modelId}';
      totals[key] = (totals[key] ?? 0) + item.tokens;
    }
    final result = [
      for (final entry in totals.entries)
        _ModelUsageTotal(label: entry.key, tokens: entry.value),
    ];
    result.sort((left, right) => right.tokens.compareTo(left.tokens));
    return result.take(4).toList();
  }
}

class _DailyUsagePoint {
  const _DailyUsagePoint({required this.date, this.usage});

  final DateTime date;
  final rust_stats.DailyTokenUsage? usage;

  int get totalTokens => usage?.totalTokens ?? 0;
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.point, required this.maxTokens});

  final _DailyUsagePoint point;
  final int maxTokens;

  @override
  Widget build(BuildContext context) {
    final usage = point.usage;
    final heightFactor = point.totalTokens <= 0
        ? 0.03
        : (point.totalTokens / maxTokens).clamp(0.08, 1.0);
    final date = StatsService.formatDate(point.date);
    final label =
        '$date\n输入 ${usage?.inputTokens ?? 0}\n输出 ${usage?.outputTokens ?? 0}\n缓存 ${usage?.cachedTokens ?? 0}';

    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: heightFactor,
                  child: Container(
                    width: 14,
                    decoration: BoxDecoration(
                      color: point.totalTokens == 0
                          ? const Color(0xFFE2E8F0)
                          : const Color(0xFF3B82F6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              point.date.day.toString().padLeft(2, '0'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textSubtle),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelUsageTotal {
  const _ModelUsageTotal({required this.label, required this.tokens});

  final String label;
  final int tokens;
}

String _formatNumber(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    final position = text.length - index;
    buffer.write(text[index]);
    if (position > 1 && position % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel();

  @override
  Widget build(BuildContext context) {
    return _SettingsScrollFrame(
      maxWidth: 1120,
      children: [
        Text('关于', style: Theme.of(context).textTheme.titleLarge),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const CircleAvatar(radius: 24, child: Text('S')),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SpringNote',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'AI 智能便签与日报生成工具',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: '关于',
          children: const [
            _SimpleRow(label: '版本', value: '1.0.0+1'),
            _SimpleRow(label: '系统', value: 'Windows'),
            _SimpleRow(label: '官网', value: '未配置'),
            _SimpleRow(label: 'GitHub', value: '未配置'),
            _SimpleRow(label: '许可证', value: '未配置'),
          ],
        ),
      ],
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
          Row(
            children: [
              for (final template in ['OpenAI', 'Google', 'Claude'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(template),
                      selected: _template == template,
                      onSelected: (_) => _selectTemplate(template),
                    ),
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
    return _DialogFrame(
      title: '编辑模型',
      width: 760,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadOnlyField(label: '模型 ID', value: widget.model.modelId),
          _DialogTextField(
            key: const ValueKey('edit-model-name-field'),
            label: '模型名称',
            controller: _displayNameController,
          ),
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
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('confirm-edit-model-button'),
              onPressed: () {
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
              child: const Text('确认'),
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in values.entries)
                FilterChip(
                  label: Text(entry.value),
                  selected: selected.contains(entry.key),
                  onSelected: (checked) {
                    final next = [...selected];
                    if (checked) {
                      next.add(entry.key);
                    } else {
                      next.remove(entry.key);
                    }
                    onChanged(next);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

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
    this.trailing,
  });

  final String title;
  final List<Widget> children;
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

class _TextSettingRow extends StatelessWidget {
  const _TextSettingRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.trailing,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            child: _CommittedTextField(value: value, onChanged: onChanged),
          ),
          ?trailing,
        ],
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
  });

  final String label;
  final double value;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 96,
            child: _CommittedTextField(
              value: _formatNumber(value),
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              onChanged: (text) => onChanged(double.tryParse(text) ?? value),
            ),
          ),
          const SizedBox(width: 8),
          Text(suffix, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }
}

class _SwitchSettingRow extends StatelessWidget {
  const _SwitchSettingRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      label: label,
      child: Switch(value: value, onChanged: onChanged),
    );
  }
}

class _SettingRowShell extends StatelessWidget {
  const _SettingRowShell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.text),
          ),
          const Spacer(),
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
    this.textAlign = TextAlign.start,
    this.keyboardType,
    this.obscureText = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  State<_CommittedTextField> createState() => _CommittedTextFieldState();
}

class _CommittedTextFieldState extends State<_CommittedTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant _CommittedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
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
      textAlign: widget.textAlign,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      onChanged: widget.onChanged,
      onSubmitted: widget.onChanged,
      onEditingComplete: () => widget.onChanged(_controller.text),
      decoration: const InputDecoration(isDense: true),
    );
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _CommittedTextField(
            value: value,
            obscureText: obscureText,
            onChanged: onChanged,
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFDCFCE7) : const Color(0xFFFFEDD5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        enabled ? '启用' : '禁用',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: enabled ? const Color(0xFF16A34A) : const Color(0xFFF97316),
          fontSize: 11,
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

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: TextEditingController(text: value),
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.copy_rounded, size: 17),
        ),
      ),
    );
  }
}
