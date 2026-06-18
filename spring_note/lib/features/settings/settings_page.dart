import 'package:flutter/material.dart';

import '../../core/models/local_data_state.dart';
import '../../core/theme/app_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.localDataState});

  final LocalDataState localDataState;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedIndex = 0;

  static const _sections = ['偏好设置', '供应商', '默认模型', '快捷键', '统计', '关于'];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.sidebar,
      child: Row(
        children: [
          Container(
            width: 220,
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 18),
            color: AppTheme.background,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('设置', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 18),
                for (final entry in _sections.indexed)
                  _SettingsNavItem(
                    label: entry.$2,
                    selected: entry.$1 == _selectedIndex,
                    onTap: () => setState(() => _selectedIndex = entry.$1),
                  ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                _PreferencesPanel(localDataState: widget.localDataState),
                const _PlaceholderPanel(
                  title: '供应商',
                  description: '第四阶段接入供应商配置。',
                ),
                const _PlaceholderPanel(
                  title: '默认模型',
                  description: '第四阶段只保留三个业务模型。',
                ),
                const _PlaceholderPanel(
                  title: '快捷键',
                  description: '第四阶段接入显示/隐藏页面快捷键。',
                ),
                const _PlaceholderPanel(
                  title: '统计',
                  description: '第七阶段接入统计与热力图。',
                ),
                const _PlaceholderPanel(
                  title: '关于',
                  description: '第四阶段接入应用信息。',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
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
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: selected ? AppTheme.text : AppTheme.textMuted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _PreferencesPanel extends StatelessWidget {
  const _PreferencesPanel({required this.localDataState});

  final LocalDataState localDataState;

  @override
  Widget build(BuildContext context) {
    final config = localDataState.config;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 30, 40, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsGroup(
                title: '个人信息',
                rows: [
                  _SettingRow(
                    label: '每日工作时长',
                    value: '${_formatNumber(config.dailyWorkHours)} 小时',
                  ),
                  _SettingRow(
                    label: '日薪',
                    value: '¥ ${_formatNumber(config.dailySalary)}',
                  ),
                  _SettingRow(label: '所在行业', value: config.industry),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsGroup(
                title: '字体与显示',
                rows: [
                  _SettingRow(
                    label: '应用字体',
                    value: config.appFont == 'system' ? '系统默认' : config.appFont,
                  ),
                  _SettingRow(
                    label: '字体大小',
                    value: '${_formatNumber(config.fontScale)}%',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsGroup(
                title: '行为与启动',
                rows: [
                  _SettingRow(
                    label: '开机自启动',
                    value: config.autoStart ? '开启' : '关闭',
                  ),
                  _SettingRow(
                    label: '显示更新',
                    value: config.showUpdates ? '开启' : '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsGroup(
                title: '组件设置',
                rows: [
                  _SettingRow(
                    label: '显示桌面组件',
                    value: config.showDesktopWidget ? '开启' : '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                '配置文件：${localDataState.configPath}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSubtle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toString();
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.rows});

  final String title;
  final List<_SettingRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final row in rows) row,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 18),
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
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PlaceholderPanel extends StatelessWidget {
  const _PlaceholderPanel({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 30, 40, 40),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1080),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
