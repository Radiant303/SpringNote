import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/models/app_config.dart';
import '../../core/models/local_data_state.dart';
import '../../core/models/model_config.dart';
import '../../core/models/model_reference.dart';
import '../../core/models/provider_config.dart';
import '../../core/services/ai_client_service.dart';
import '../../core/services/external_link_service.dart';
import '../../core/services/local_data_service.dart';
import '../../core/services/platform_feature_support.dart';
import '../../core/services/stats_service.dart';
import '../../core/services/system_font_service.dart';
import '../../core/theme/app_theme.dart';
import '../../src/rust/stats.dart' as rust_stats;
import 'settings_stats_panel.dart';

enum _SettingsSection {
  preferences('偏好设置', _SettingsNavIconType.monitor),
  providers('供应商', _SettingsNavIconType.boxes),
  models('默认模型', _SettingsNavIconType.heart),
  hotkeys('快捷键', _SettingsNavIconType.keyboard),
  stats('统计', _SettingsNavIconType.chart),
  about('关于', _SettingsNavIconType.info);

  const _SettingsSection(this.label, this.icon);

  final String label;
  final _SettingsNavIconType icon;
}

enum _SettingsNavIconType { monitor, boxes, heart, keyboard, chart, info }

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.localDataState,
    this.localDataService = const LocalDataService(),
    this.aiClientService = const AiClientService(),
    this.onConfigChanged,
    this.onLocalDataStateChanged,
  });

  final LocalDataState localDataState;
  final LocalDataService localDataService;
  final AiClientService aiClientService;
  final ValueChanged<AppConfig>? onConfigChanged;
  final ValueChanged<LocalDataState>? onLocalDataStateChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _SettingsSection _section = _SettingsSection.preferences;
  late AppConfig _config = widget.localDataState.config;
  String? _selectedProviderId;
  bool _saving = false;
  String? _settingsError;

  ProviderConfig? get _selectedProvider {
    if (_config.providers.isEmpty) {
      return null;
    }
    return _config.providers.firstWhere(
      (provider) => provider.id == _selectedProviderId,
      orElse: () => _config.providers.first,
    );
  }

  List<_ProviderModelOption> get _allModels {
    return [
      for (final provider in _config.providers)
        for (final model in provider.models)
          _ProviderModelOption(provider: provider, model: model),
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
    try {
      await widget.localDataService.saveConfig(config);
      widget.onConfigChanged?.call(config);
      if (mounted) {
        setState(() {
          _saving = false;
          _settingsError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _settingsError = error.toString();
        });
      }
    }
  }

  Future<void> _migrateDataDirectory(String? targetDirectory) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _settingsError = null;
    });
    try {
      final state = await widget.localDataService.migrateDataDirectory(
        currentState: widget.localDataState.copyWith(config: _config),
        targetDirectory: targetDirectory,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _config = state.config;
        _saving = false;
      });
      widget.onLocalDataStateChanged?.call(state);
      if (mounted) {
        await _showDataMigrationCompleteDialog();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _settingsError = error.toString();
        });
      }
    }
  }

  Future<void> _showDataMigrationCompleteDialog() {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, _, _) => const _DataMigrationCompleteDialog(),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.975, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
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
    final removedModelRefs = _config.providers
        .where((provider) => provider.id == id)
        .expand((provider) => provider.models)
        .map(
          (model) =>
              ModelReference.encode(providerId: id, modelId: model.modelId),
        )
        .toSet();
    final providers = _config.providers
        .where((provider) => provider.id != id)
        .toList();
    final defaultModels = Map<String, String?>.from(_config.defaultModels);
    for (final entry in defaultModels.entries.toList()) {
      final modelRef = ModelReference.parse(entry.value);
      if (modelRef?.providerId == id ||
          (modelRef?.providerId == null &&
              removedModelIds.contains(modelRef?.modelId)) ||
          removedModelRefs.contains(entry.value)) {
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
    final currentProvider = _config.providers.firstWhere(
      (item) => item.id == provider.id,
      orElse: () => provider,
    );
    final exists = currentProvider.models.any(
      (item) => item.modelId == model.modelId,
    );
    final models = exists
        ? [
            for (final item in currentProvider.models)
              if (item.modelId == model.modelId) model else item,
          ]
        : [...currentProvider.models, model];
    await _updateProvider(currentProvider.copyWith(models: models));
  }

  Future<void> _deleteModel(ProviderConfig provider, String modelId) async {
    final currentProvider = _config.providers.firstWhere(
      (item) => item.id == provider.id,
      orElse: () => provider,
    );
    final models = currentProvider.models
        .where((model) => model.modelId != modelId)
        .toList();
    final defaultModels = Map<String, String?>.from(_config.defaultModels);
    for (final entry in defaultModels.entries.toList()) {
      final modelRef = ModelReference.parse(entry.value);
      if (modelRef?.matches(providerId: currentProvider.id, modelId: modelId) ??
          false) {
        defaultModels[entry.key] = null;
      }
    }
    final providers = [
      for (final item in _config.providers)
        if (item.id == currentProvider.id)
          currentProvider.copyWith(models: models)
        else
          item,
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
              border: Border(right: BorderSide(color: Color(0xFFEEEEEE))),
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
                    onTap: () {
                      if (_section == section) {
                        return;
                      }
                      setState(() => _section = section);
                    },
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
        dataDirectory: widget.localDataState.dataDirectory,
        configPath: widget.localDataState.configPath,
        appDataDir: widget.localDataState.dataDirectory,
        aiClientService: widget.aiClientService,
        saving: _saving,
        errorMessage: _settingsError,
        onDataDirectoryChanged: _migrateDataDirectory,
      ),
      _SettingsSection.providers => _ProvidersPanel(
        appDataDir: widget.localDataState.dataDirectory,
        apiLogEnabled: _config.apiLogEnabled,
        aiClientService: widget.aiClientService,
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
      _SettingsSection.stats => SettingsStatsPanel(
        localDataState: widget.localDataState.copyWith(config: _config),
      ),
      _SettingsSection.about => const _AboutPanel(),
    };
  }
}

class _SettingsNavItem extends StatefulWidget {
  const _SettingsNavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final _SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<_SettingsNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;
    final contentColor = active ? AppTheme.text : const Color(0xFF6E6E6E);
    final backgroundColor = widget.selected
        ? const Color(0xFFE2E2E2)
        : const Color(0xFFF5F5F5);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            height: 36,
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: contentColor),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, color, _) {
                    final animatedColor = color ?? contentColor;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          _SettingsNavLucideIcon(
                            type: widget.section.icon,
                            size: 17,
                            color: animatedColor,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            widget.section.label,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: animatedColor,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
        ? const Color(0xFFE2E2E2)
        : const Color(0xFFF5F5F5);
    final active = widget.selected || _hovered;
    final contentColor = active ? AppTheme.text : const Color(0xFF6E6E6E);
    final avatarBackgroundColor = active
        ? const Color(0xFFDCDCDC)
        : const Color(0xFFEDEDED);

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

class _SettingsNavLucideIcon extends StatelessWidget {
  const _SettingsNavLucideIcon({
    required this.type,
    required this.size,
    required this.color,
  });

  final _SettingsNavIconType type;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CustomPaint(
        size: Size.square(size),
        painter: _SettingsNavLucidePainter(type: type, color: color),
      ),
    );
  }
}

class _SettingsNavLucidePainter extends CustomPainter {
  const _SettingsNavLucidePainter({required this.type, required this.color});

  final _SettingsNavIconType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24;
    final sy = size.height / 24;
    final strokeScale = sx < sy ? sx : sy;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.05 * strokeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset point(double x, double y) => Offset(x * sx, y * sy);
    Rect rect(double left, double top, double width, double height) =>
        Rect.fromLTWH(left * sx, top * sy, width * sx, height * sy);
    RRect roundedRect(double left, double top, double width, double height) {
      return RRect.fromRectAndRadius(
        rect(left, top, width, height),
        Radius.circular(2 * strokeScale),
      );
    }

    Path path(List<Offset> points, {bool close = false}) {
      final result = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        result.lineTo(point.dx, point.dy);
      }
      if (close) {
        result.close();
      }
      return result;
    }

    void drawCube(double cx, double cy, double r) {
      final top = point(cx, cy - r);
      final rightTop = point(cx + r * 1.18, cy - r * 0.34);
      final rightBottom = point(cx + r * 1.18, cy + r * 0.9);
      final bottom = point(cx, cy + r * 1.55);
      final leftBottom = point(cx - r * 1.18, cy + r * 0.9);
      final leftTop = point(cx - r * 1.18, cy - r * 0.34);
      final center = point(cx, cy + r * 0.28);

      canvas.drawPath(
        path([
          top,
          rightTop,
          rightBottom,
          bottom,
          leftBottom,
          leftTop,
        ], close: true),
        paint,
      );
      canvas.drawLine(top, center, paint);
      canvas.drawLine(leftTop, center, paint);
      canvas.drawLine(rightTop, center, paint);
      canvas.drawLine(center, bottom, paint);
    }

    switch (type) {
      case _SettingsNavIconType.monitor:
        canvas.drawRRect(roundedRect(3.5, 4.5, 17, 12), paint);
        canvas.drawLine(point(12, 16.5), point(12, 20), paint);
        canvas.drawLine(point(8.5, 20), point(15.5, 20), paint);
        break;
      case _SettingsNavIconType.boxes:
        drawCube(12, 5.8, 2.55);
        drawCube(7.5, 13.4, 2.55);
        drawCube(16.5, 13.4, 2.55);
        break;
      case _SettingsNavIconType.heart:
        final heart = Path()
          ..moveTo(point(12, 20.2).dx, point(12, 20.2).dy)
          ..cubicTo(
            point(5.1, 15.2).dx,
            point(5.1, 15.2).dy,
            point(3.7, 11.5).dx,
            point(3.7, 11.5).dy,
            point(3.7, 8.6).dx,
            point(3.7, 8.6).dy,
          )
          ..cubicTo(
            point(3.7, 5.6).dx,
            point(3.7, 5.6).dy,
            point(6, 3.9).dx,
            point(6, 3.9).dy,
            point(8.5, 3.9).dx,
            point(8.5, 3.9).dy,
          )
          ..cubicTo(
            point(10.1, 3.9).dx,
            point(10.1, 3.9).dy,
            point(11.3, 4.8).dx,
            point(11.3, 4.8).dy,
            point(12, 6).dx,
            point(12, 6).dy,
          )
          ..cubicTo(
            point(12.7, 4.8).dx,
            point(12.7, 4.8).dy,
            point(13.9, 3.9).dx,
            point(13.9, 3.9).dy,
            point(15.5, 3.9).dx,
            point(15.5, 3.9).dy,
          )
          ..cubicTo(
            point(18, 3.9).dx,
            point(18, 3.9).dy,
            point(20.3, 5.6).dx,
            point(20.3, 5.6).dy,
            point(20.3, 8.6).dx,
            point(20.3, 8.6).dy,
          )
          ..cubicTo(
            point(20.3, 11.5).dx,
            point(20.3, 11.5).dy,
            point(18.9, 15.2).dx,
            point(18.9, 15.2).dy,
            point(12, 20.2).dx,
            point(12, 20.2).dy,
          );
        canvas.drawPath(heart, paint);
        break;
      case _SettingsNavIconType.keyboard:
        canvas.drawRRect(roundedRect(3.5, 6, 17, 12), paint);
        for (final y in [10.0, 13.2]) {
          for (final x in [7.1, 10.4, 13.7, 17.0]) {
            canvas.drawCircle(point(x, y), 0.36 * strokeScale, paint);
          }
        }
        canvas.drawLine(point(8, 16), point(16, 16), paint);
        break;
      case _SettingsNavIconType.chart:
        canvas.drawLine(point(4, 20), point(20, 20), paint);
        canvas.drawRRect(roundedRect(5.5, 12.5, 3.2, 7.5), paint);
        canvas.drawRRect(roundedRect(10.4, 7.5, 3.2, 12.5), paint);
        canvas.drawRRect(roundedRect(15.3, 4.5, 3.2, 15.5), paint);
        break;
      case _SettingsNavIconType.info:
        final badge = Path()..addOval(rect(4.8, 4.8, 14.4, 14.4));
        canvas.drawPath(badge, paint);
        canvas.drawCircle(point(12, 7.8), 0.42 * strokeScale, paint);
        canvas.drawLine(point(12, 11), point(12, 16.5), paint);
        canvas.drawLine(point(10.9, 11), point(12, 11), paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SettingsNavLucidePainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}

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
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Color(0xFFEEEEEE))),
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: 12),
            const SizedBox(height: 2),
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
            _ProtocolField(
              value: provider.protocol,
              onChanged: (value) {
                widget.onProviderChanged(provider.copyWith(protocol: value));
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
      backgroundColor: Colors.white,
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
                  color: AppTheme.text,
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
                      color: AppTheme.text,
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
                        activeThumbColor: Colors.white,
                        activeTrackColor: Colors.black,
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: const Color(0xFFD8D8D8),
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
            color: _hovered ? const Color(0xFFEDEDED) : const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDCDCDC)),
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
                    color: AppTheme.text,
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
      return const SizedBox(
        key: ValueKey('provider-connection-testing'),
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
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
      backgroundColor: Colors.white,
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
                          ? const Color(0xFFE2E2E2)
                          : const Color(0xFFF5F5F5),
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
                                    ? AppTheme.text
                                    : AppTheme.textMuted,
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
                        child: const Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: AppTheme.text,
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
        color: const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Icon(
        Icons.auto_awesome_outlined,
        size: size * 0.62,
        color: AppTheme.textMuted,
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
              ? const Color(0xFF4F4F4F)
              : (_hovered ? const Color(0xFF2A2A2A) : Colors.black)
        : (_hovered && enabled ? const Color(0xFFF5F5F5) : Colors.white);
    final foregroundColor = widget.filled ? Colors.white : AppTheme.text;
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
                : Border.all(color: const Color(0xFF8A8A8A)),
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
      backgroundColor: Colors.white,
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
                              ?.copyWith(color: AppTheme.text),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '选择要添加到当前提供商的模型',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.textSubtle),
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
                    : ListView.builder(
                        key: const ValueKey('provider-model-groups'),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          final expanded =
                              searching || _expandedGroups.contains(group.name);
                          return _ProviderModelGroupSection(
                            group: group,
                            expanded: expanded,
                            hoveredGroup: _hoveredGroup == group.name,
                            selectedModelIds: _selectedModelIds,
                            busyModelIds: _busyModelIds,
                            hoveredModelId: _hoveredModelId,
                            onGroupHoverChanged: (hovered) {
                              setState(() {
                                if (hovered) {
                                  _hoveredGroup = group.name;
                                } else if (_hoveredGroup == group.name) {
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
                          );
                        },
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
        ? const Color(0xFFE8E8E8)
        : widget.hovered
        ? const Color(0xFFEDEDED)
        : const Color(0xFFF5F5F5);
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
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            size: 19,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.name,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: AppTheme.text,
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
                            color: Colors.white.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${widget.count}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: AppTheme.textSubtle,
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
                          ? const Color(0xFFE2E2E2)
                          : const Color(0xFFF5F5F5),
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
                                    ? AppTheme.text
                                    : AppTheme.textMuted,
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
        color: selected ? AppTheme.text : const Color(0xFFEDEDED),
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
                    selected ? Colors.white : AppTheme.textMuted,
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
                  color: selected ? Colors.white : AppTheme.text,
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
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF666666)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '正在获取模型...',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSubtle),
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
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSubtle),
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
        ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSubtle),
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
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSubtle),
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
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
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
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF555555),
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
                        color: const Color(0xFFF2F2F2),
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

class _HotkeysPanel extends StatelessWidget {
  const _HotkeysPanel({required this.config, required this.onChanged});

  final AppConfig config;
  final ValueChanged<AppConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final toggleWindow = config.hotkeys['toggleWindow'] ?? '';
    final hotkeysSupported = PlatformFeatureSupport.supportsGlobalHotkeys;
    final toggleWindowEnabled =
        hotkeysSupported && toggleWindow.trim().isNotEmpty;
    final submitShortcut = Platform.isMacOS ? 'Cmd+Enter' : 'Ctrl+Enter';
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
              enabled: hotkeysSupported,
              description: hotkeysSupported ? null : _platformFeatureMessage(),
              validator: _validateGlobalHotkey,
              onChanged: hotkeysSupported
                  ? (value) {
                      final hotkeys = Map<String, String?>.from(config.hotkeys);
                      hotkeys['toggleWindow'] = value;
                      onChanged(config.copyWith(hotkeys: hotkeys));
                    }
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '重置',
                    onPressed: hotkeysSupported
                        ? () {
                            final hotkeys = Map<String, String?>.from(
                              config.hotkeys,
                            );
                            hotkeys['toggleWindow'] = 'Ctrl+Shift+S';
                            onChanged(config.copyWith(hotkeys: hotkeys));
                          }
                        : null,
                    icon: const Icon(Icons.restart_alt_rounded, size: 17),
                  ),
                  IconButton(
                    tooltip: '清除',
                    onPressed: hotkeysSupported
                        ? () {
                            final hotkeys = Map<String, String?>.from(
                              config.hotkeys,
                            );
                            hotkeys['toggleWindow'] = '';
                            onChanged(config.copyWith(hotkeys: hotkeys));
                          }
                        : null,
                    icon: const Icon(Icons.close_rounded, size: 17),
                  ),
                  Switch(
                    value: toggleWindowEnabled,
                    onChanged: hotkeysSupported
                        ? (enabled) {
                            final hotkeys = Map<String, String?>.from(
                              config.hotkeys,
                            );
                            hotkeys['toggleWindow'] = enabled
                                ? (toggleWindow.trim().isEmpty
                                      ? 'Ctrl+Shift+S'
                                      : toggleWindow.trim())
                                : '';
                            onChanged(config.copyWith(hotkeys: hotkeys));
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
        _SettingsCard(
          title: '输入快捷键',
          children: [
            _ShortcutSettingRow(label: '首页快速输入', shortcut: submitShortcut),
            _ShortcutSettingRow(label: '回忆书对话输入', shortcut: submitShortcut),
          ],
        ),
      ],
    );
  }
}

String? _validateGlobalHotkey(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || _isValidGlobalHotkey(trimmed)) {
    return null;
  }
  return '请输入类似 Ctrl+Shift+S 的组合键';
}

bool _isValidGlobalHotkey(String value) {
  final tokens = value
      .split('+')
      .map((token) => token.trim().toUpperCase())
      .where((token) => token.isNotEmpty)
      .toList();
  if (tokens.length < 2) {
    return false;
  }

  var hasModifier = false;
  var keyCount = 0;
  for (final token in tokens) {
    if (_isGlobalHotkeyModifier(token)) {
      hasModifier = true;
      continue;
    }
    if (!_isGlobalHotkeyKey(token)) {
      return false;
    }
    keyCount += 1;
    if (keyCount > 1) {
      return false;
    }
  }

  return hasModifier && keyCount == 1;
}

bool _isGlobalHotkeyModifier(String token) {
  return switch (token) {
    'CTRL' ||
    'CONTROL' ||
    'SHIFT' ||
    'ALT' ||
    'OPTION' ||
    'WIN' ||
    'WINDOWS' ||
    'META' ||
    'CMD' ||
    'COMMAND' ||
    'SUPER' => true,
    _ => false,
  };
}

bool _isGlobalHotkeyKey(String token) {
  if (token.length == 1) {
    final code = token.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 48 && code <= 57);
  }

  if (token.startsWith('F')) {
    final number = int.tryParse(token.substring(1));
    final maxFunctionKey = Platform.isMacOS ? 20 : 24;
    if (number != null && number >= 1 && number <= maxFunctionKey) {
      return true;
    }
  }

  final commonKeys = {
    'SPACE',
    'TAB',
    'ENTER',
    'RETURN',
    'ESC',
    'ESCAPE',
    'BACKSPACE',
    'DELETE',
    'DEL',
    'HOME',
    'END',
    'PAGEUP',
    'PGUP',
    'PAGEDOWN',
    'PGDN',
    'UP',
    'DOWN',
    'LEFT',
    'RIGHT',
  };
  if (!Platform.isMacOS) {
    commonKeys.addAll({'INSERT', 'INS'});
  }
  return commonKeys.contains(token);
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
                  backgroundColor: const Color(0xFFF5F5F5),
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
    Color(0xFFEDEDED),
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
                  backgroundColor: const Color(0xFFF5F5F5),
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
                          ? const Color(0xFFE0E0E0)
                          : const Color(0xFF666666),
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

  static const _websiteUrl = 'https://radiant303.github.io/SpringNote';
  static const _githubUrl = 'https://github.com/Radiant303/SpringNote';
  static const _licenseUrl =
      'https://github.com/Radiant303/SpringNote/blob/main/LICENSE';
  static const _qqGroupUrl = 'https://qm.qq.com/q/4gWWKvwhP2';
  static const _externalLinkService = ExternalLinkService();

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
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: Image.asset(
                  'windows/runner/resources/index.png',
                  width: 30,
                  height: 30,
                  filterQuality: FilterQuality.medium,
                ),
              ),
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
        _AboutListCard(
          rows: [
            const _PubspecVersionRow(),
            const _PlatformInfoRow(),
            _AboutListRow(
              icon: _AboutRowIconType.globe,
              label: '官网',
              onTap: () => _externalLinkService.open(_websiteUrl),
            ),
            _AboutListRow(
              icon: _AboutRowIconType.github,
              label: 'GitHub',
              onTap: () => _externalLinkService.open(_githubUrl),
            ),
            _AboutListRow(
              icon: _AboutRowIconType.license,
              label: '许可证',
              onTap: () => _externalLinkService.open(_licenseUrl),
            ),
            _AboutListRow(
              icon: _AboutRowIconType.qq,
              label: '加入QQ群',
              onTap: () => _externalLinkService.open(_qqGroupUrl),
            ),
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
        ? const Color(0xFFE2E2E2)
        : (_hovered ? const Color(0xFFF3F3F3) : Colors.white);
    final borderColor = selected
        ? const Color(0xFFCFCFCF)
        : const Color(0xFFD5D5D5);
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
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: AppTheme.text,
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
                      color: active ? AppTheme.text : AppTheme.textSubtle,
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
      backgroundColor: Colors.white,
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
                                color: AppTheme.text,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppTheme.textSubtle,
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
            const Divider(height: 1, color: Color(0xFFEDEDED)),
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
                color: AppTheme.text,
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
        ? const Color(0xFFE2E2E2)
        : (_hovered ? const Color(0xFFF1F1F1) : Colors.white);
    final foreground = AppTheme.text;
    final borderColor = selected
        ? const Color(0xFFCFCFCF)
        : const Color(0xFFD5D5D5);
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
            color: background,
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
                color: AppTheme.text,
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
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: AppTheme.text, height: 1.2),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E1E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppTheme.textSubtle,
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
        ? (_hovered ? const Color(0xFF2A2A2A) : Colors.black)
        : (_hovered ? const Color(0xFFF3F3F3) : Colors.white);
    final foreground = widget.filled ? Colors.white : AppTheme.text;
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
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: widget.filled
                ? null
                : Border.all(color: const Color(0xFFD7D7D7)),
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
              color: active ? const Color(0xFFEDEDED) : Colors.transparent,
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
                color: active ? AppTheme.text : AppTheme.textSubtle,
              ),
            ),
          ),
        ),
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
          IconButton(
            tooltip: '重置字体',
            onPressed: widget.value == 'system'
                ? null
                : () => widget.onChanged('system'),
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
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
          height: 38,
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

class _AboutListCard extends StatelessWidget {
  const _AboutListCard({required this.rows});

  final List<Widget> rows;

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
                Text('关于', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEDEDED)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  rows[index],
                  if (index != rows.length - 1)
                    const Padding(
                      padding: EdgeInsets.only(left: 34),
                      child: Divider(height: 1, color: Color(0xFFEDEDED)),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _AboutRowIconType { code, system, globe, github, license, qq }

class _PubspecVersionRow extends StatelessWidget {
  const _PubspecVersionRow();

  static Future<String> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version.trim().isEmpty
          ? '1.0.0'
          : packageInfo.version.trim();
    } catch (_) {
      return '1.0.0';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _loadVersion(),
      builder: (context, snapshot) {
        return _AboutListRow(
          icon: _AboutRowIconType.code,
          label: '版本',
          value: snapshot.data ?? '1.0.0',
        );
      },
    );
  }
}

class _PlatformInfoRow extends StatelessWidget {
  const _PlatformInfoRow();

  String get _platformLabel {
    if (Platform.isWindows) {
      return 'Windows';
    }
    if (Platform.isLinux) {
      return 'Linux';
    }
    if (Platform.isMacOS) {
      return 'Mac';
    }
    return '未知';
  }

  @override
  Widget build(BuildContext context) {
    return _AboutListRow(
      icon: _AboutRowIconType.system,
      label: '系统',
      value: _platformLabel,
    );
  }
}

class _AboutListRow extends StatefulWidget {
  const _AboutListRow({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
  });

  final _AboutRowIconType icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  State<_AboutListRow> createState() => _AboutListRowState();
}

class _AboutListRowState extends State<_AboutListRow> {
  bool _hovered = false;

  bool get _clickable => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final active = _clickable && _hovered;
    final contentColor = active ? AppTheme.text : const Color(0xFF303030);
    final trailingColor = active ? AppTheme.textMuted : const Color(0xFF777777);

    return MouseRegion(
      cursor: _clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (_clickable) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (_clickable) {
          setState(() => _hovered = false);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 50,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned.fill(
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
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: contentColor),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (context, color, _) {
                  final animatedColor = color ?? contentColor;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        _AboutRowIcon(
                          type: widget.icon,
                          size: 20,
                          color: animatedColor,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            widget.label,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: animatedColor,
                                  fontSize: 14.5,
                                  height: 1.2,
                                ),
                          ),
                        ),
                        if (widget.value != null)
                          Text(
                            widget.value!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: trailingColor,
                                  fontSize: 13,
                                  height: 1.2,
                                ),
                          )
                        else
                          _AboutLinkChevron(size: 16, color: trailingColor),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutRowIcon extends StatelessWidget {
  const _AboutRowIcon({
    required this.type,
    required this.size,
    required this.color,
  });

  final _AboutRowIconType type;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AboutRowIconPainter(type: type, color: color),
    );
  }
}

class _AboutRowIconPainter extends CustomPainter {
  const _AboutRowIconPainter({required this.type, required this.color});

  final _AboutRowIconType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24;
    final sy = size.height / 24;
    final strokeScale = sx < sy ? sx : sy;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9 * strokeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    Offset p(double x, double y) => Offset(x * sx, y * sy);
    RRect rr(double x, double y, double w, double h, double r) {
      return RRect.fromRectAndRadius(
        Rect.fromLTWH(x * sx, y * sy, w * sx, h * sy),
        Radius.circular(r * strokeScale),
      );
    }

    switch (type) {
      case _AboutRowIconType.code:
        canvas.drawLine(p(10, 7), p(6, 12), paint);
        canvas.drawLine(p(6, 12), p(10, 17), paint);
        canvas.drawLine(p(14, 7), p(18, 12), paint);
        canvas.drawLine(p(18, 12), p(14, 17), paint);
        break;
      case _AboutRowIconType.system:
        canvas.drawRRect(rr(5, 4, 14, 12, 2), paint);
        canvas.drawLine(p(9, 20), p(15, 20), paint);
        canvas.drawLine(p(12, 16), p(12, 20), paint);
        break;
      case _AboutRowIconType.globe:
        canvas.drawCircle(p(12, 12), 8 * strokeScale, paint);
        canvas.drawOval(
          Rect.fromCenter(center: p(12, 12), width: 8 * sx, height: 16 * sy),
          paint,
        );
        canvas.drawLine(p(4, 12), p(20, 12), paint);
        canvas.drawLine(p(6.2, 8), p(17.8, 8), paint);
        canvas.drawLine(p(6.2, 16), p(17.8, 16), paint);
        break;
      case _AboutRowIconType.github:
        final path = Path()
          ..moveTo(12 * sx, 3.8 * sy)
          ..cubicTo(7.5 * sx, 3.8 * sy, 4 * sx, 7.3 * sy, 4 * sx, 11.9 * sy)
          ..cubicTo(4 * sx, 15.5 * sy, 6.3 * sx, 18.2 * sy, 9.6 * sx, 19.2 * sy)
          ..lineTo(9.6 * sx, 16.9 * sy)
          ..cubicTo(
            8.2 * sx,
            17.2 * sy,
            7.3 * sx,
            16.7 * sy,
            6.7 * sx,
            15.4 * sy,
          )
          ..cubicTo(
            6.4 * sx,
            14.8 * sy,
            5.9 * sx,
            14.4 * sy,
            5.4 * sx,
            14.2 * sy,
          )
          ..cubicTo(6.3 * sx, 14 * sy, 7 * sx, 14.3 * sy, 7.6 * sx, 15.1 * sy)
          ..cubicTo(
            8.2 * sx,
            15.9 * sy,
            8.9 * sx,
            16.1 * sy,
            9.7 * sx,
            15.9 * sy,
          )
          ..cubicTo(
            9.9 * sx,
            15.4 * sy,
            10.2 * sx,
            15 * sy,
            10.6 * sx,
            14.7 * sy,
          )
          ..cubicTo(8 * sx, 14.3 * sy, 6.9 * sx, 13.2 * sy, 6.9 * sx, 11 * sy)
          ..cubicTo(6.9 * sx, 9.9 * sy, 7.3 * sx, 9 * sy, 8 * sx, 8.3 * sy)
          ..cubicTo(7.8 * sx, 7.8 * sy, 7.6 * sx, 6.8 * sy, 8.1 * sx, 5.5 * sy)
          ..cubicTo(8.1 * sx, 5.5 * sy, 9.2 * sx, 5.2 * sy, 10.8 * sx, 6.4 * sy)
          ..cubicTo(
            11.6 * sx,
            6.2 * sy,
            12.4 * sx,
            6.2 * sy,
            13.2 * sx,
            6.4 * sy,
          )
          ..cubicTo(
            14.8 * sx,
            5.2 * sy,
            15.9 * sx,
            5.5 * sy,
            15.9 * sx,
            5.5 * sy,
          )
          ..cubicTo(16.4 * sx, 6.8 * sy, 16.2 * sx, 7.8 * sy, 16 * sx, 8.3 * sy)
          ..cubicTo(16.7 * sx, 9 * sy, 17.1 * sx, 9.9 * sy, 17.1 * sx, 11 * sy)
          ..cubicTo(
            17.1 * sx,
            13.2 * sy,
            16 * sx,
            14.3 * sy,
            13.4 * sx,
            14.7 * sy,
          )
          ..cubicTo(
            13.9 * sx,
            15.1 * sy,
            14.2 * sx,
            15.8 * sy,
            14.2 * sx,
            16.9 * sy,
          )
          ..lineTo(14.2 * sx, 19.2 * sy)
          ..cubicTo(
            17.6 * sx,
            18.1 * sy,
            20 * sx,
            15.5 * sy,
            20 * sx,
            11.9 * sy,
          )
          ..cubicTo(20 * sx, 7.3 * sy, 16.5 * sx, 3.8 * sy, 12 * sx, 3.8 * sy)
          ..close();
        canvas.drawPath(path, fillPaint);
        break;
      case _AboutRowIconType.license:
        final docPath = Path()
          ..moveTo(7 * sx, 3.5 * sy)
          ..lineTo(14 * sx, 3.5 * sy)
          ..lineTo(18 * sx, 7.5 * sy)
          ..lineTo(18 * sx, 20.5 * sy)
          ..lineTo(7 * sx, 20.5 * sy)
          ..close();
        canvas.drawPath(docPath, paint);
        canvas.drawLine(p(14, 3.5), p(14, 7.5), paint);
        canvas.drawLine(p(14, 7.5), p(18, 7.5), paint);
        canvas.drawLine(p(9.5, 11.5), p(15.5, 11.5), paint);
        canvas.drawLine(p(9.5, 15), p(14, 15), paint);
        break;
      case _AboutRowIconType.qq:
        canvas.drawRRect(rr(4.5, 5.5, 15, 11.5, 3.4), paint);
        final tail = Path()
          ..moveTo(9.2 * sx, 16.8 * sy)
          ..lineTo(7.4 * sx, 20 * sy)
          ..lineTo(11.8 * sx, 16.8 * sy);
        canvas.drawPath(tail, paint);
        canvas.drawCircle(p(9, 11.2), 0.9 * strokeScale, fillPaint);
        canvas.drawCircle(p(12, 11.2), 0.9 * strokeScale, fillPaint);
        canvas.drawCircle(p(15, 11.2), 0.9 * strokeScale, fillPaint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _AboutRowIconPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}

class _AboutLinkChevron extends StatelessWidget {
  const _AboutLinkChevron({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AboutLinkChevronPainter(color: color),
    );
  }
}

class _AboutLinkChevronPainter extends CustomPainter {
  const _AboutLinkChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.38, size.height * 0.22)
      ..lineTo(size.width * 0.66, size.height * 0.5)
      ..lineTo(size.width * 0.38, size.height * 0.78);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AboutLinkChevronPainter oldDelegate) {
    return oldDelegate.color != color;
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
