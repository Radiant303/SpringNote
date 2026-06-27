import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/home/home_page.dart';
import '../../features/memory/memory_page.dart';
import '../../features/notes/notes_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/widget/desktop_status_widget.dart';
import '../models/app_config.dart';
import '../models/desktop_widget_position.dart';
import '../models/local_data_state.dart';
import '../models/note_external_update.dart';
import '../models/note_file.dart';
import '../services/auto_start_service.dart';
import '../services/desktop_widget_controller.dart';
import '../services/desktop_window_controller.dart';
import '../services/desktop_widget_window_bridge.dart';
import '../services/global_hotkey_service.dart';
import '../services/level_progress_controller.dart';
import '../services/local_data_service.dart';
import '../services/startup_report_generation_service.dart';
import '../services/tray_service.dart';
import '../services/update_check_service.dart';
import '../theme/app_theme.dart';

enum AppSection { home, notes, memory, settings }

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.localDataState,
    this.startupReportGenerationService =
        const StartupReportGenerationService(),
    this.updateCheckService = const UpdateCheckService(),
    this.localDataService = const LocalDataService(),
    this.onConfigChanged,
  });

  final LocalDataState localDataState;
  final StartupReportGenerationService startupReportGenerationService;
  final UpdateCheckService updateCheckService;
  final LocalDataService localDataService;
  final ValueChanged<AppConfig>? onConfigChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WindowListener {
  AppSection _section = AppSection.home;
  late LocalDataState _localDataState = widget.localDataState;
  late final DesktopWidgetController _desktopWidgetController =
      DesktopWidgetController()..attach(_localDataState);
  late final DesktopWidgetWindowBridge _desktopWidgetWindow =
      DesktopWidgetWindowBridge();
  final AutoStartService _autoStartService = const AutoStartService();
  final GlobalHotkeyService _globalHotkeyService = const GlobalHotkeyService();
  final TrayService _trayService = const TrayService();
  late final LevelProgressController _levelProgressController =
      LevelProgressController()..attach(_localDataState);
  late final ValueNotifier<NoteExternalUpdate?> _noteExternalUpdate =
      ValueNotifier(null);
  UpdateCheckResult _updateCheckResult = UpdateCheckResult.idle;
  int _noteExternalUpdateRevision = 0;
  Timer? _desktopWidgetPositionSaveTimer;
  AppConfig? _pendingDesktopWidgetPositionConfig;
  bool _destroyingWindow = false;

  @override
  void initState() {
    super.initState();
    if (DesktopWindowController.supportsWindowManager) {
      windowManager.addListener(this);
      unawaited(_setPreventClose(true));
    }
    _desktopWidgetController.addListener(_syncDesktopWidgetWindow);
    _levelProgressController.addListener(_handleLevelProgressChanged);
    unawaited(
      _desktopWidgetWindow.initialize(
        onToggle: _desktopWidgetController.toggle,
        onOpenHome: _openHomeFromDesktopWidget,
        onPositionChanged: _handleDesktopWidgetPositionChanged,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncDesktopWidgetWindow();
      _syncAutoStart(_localDataState.config);
      _syncTray(_localDataState.config);
      _syncGlobalHotkey(_localDataState.config);
      unawaited(_runStartupReportGeneration(_localDataState));
      unawaited(_runUpdateCheck(_localDataState.config));
    });
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.localDataState != oldWidget.localDataState) {
      _localDataState = widget.localDataState;
      _desktopWidgetController.attach(_localDataState);
      _levelProgressController.attach(_localDataState);
      _syncDesktopWidgetWindow();
      _syncAutoStart(_localDataState.config);
      _syncTray(_localDataState.config);
      _syncGlobalHotkey(_localDataState.config);
      unawaited(_runStartupReportGeneration(_localDataState));
      unawaited(_runUpdateCheck(_localDataState.config));
    }
  }

  @override
  void dispose() {
    if (DesktopWindowController.supportsWindowManager) {
      windowManager.removeListener(this);
      unawaited(_setPreventClose(false));
    }
    _desktopWidgetController.removeListener(_syncDesktopWidgetWindow);
    _levelProgressController.removeListener(_handleLevelProgressChanged);
    _flushDesktopWidgetPositionSave();
    unawaited(_globalHotkeyService.unregisterToggleWindowHotkey());
    unawaited(_trayService.dispose());
    unawaited(_desktopWidgetWindow.dispose());
    _noteExternalUpdate.dispose();
    _desktopWidgetController.dispose();
    _levelProgressController.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (_destroyingWindow) {
      return;
    }
    _destroyingWindow = true;
    unawaited(_flushAndDestroyWindow());
  }

  Future<void> _flushAndDestroyWindow() async {
    try {
      await _desktopWidgetController.flush();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'spring_note',
          context: ErrorDescription('flushing work stats before window close'),
        ),
      );
    } finally {
      try {
        await windowManager.destroy();
      } catch (error, stackTrace) {
        _destroyingWindow = false;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'spring_note',
            context: ErrorDescription(
              'destroying window after work stats flush',
            ),
          ),
        );
      }
    }
  }

  Future<void> _setPreventClose(bool value) async {
    try {
      await windowManager.setPreventClose(value);
    } on MissingPluginException {
      // Window manager can be unavailable in tests.
    } on PlatformException {
      // Window manager can be unavailable during shutdown races.
    } on UnsupportedError {
      // Window manager can be unavailable in tests or during shutdown races.
    }
  }

  void _openHomeFromDesktopWidget() {
    if (!mounted) {
      return;
    }
    _selectSection(AppSection.home);
  }

  void _handleDesktopWidgetPositionChanged(DesktopWidgetPosition position) {
    if (!mounted) {
      return;
    }
    final config = _localDataState.config;
    if (config.desktopWidgetPosition == position) {
      return;
    }
    final nextConfig = config.copyWith(desktopWidgetPosition: position);
    setState(() {
      _localDataState = _localDataState.copyWith(config: nextConfig);
    });
    widget.onConfigChanged?.call(nextConfig);
    _scheduleDesktopWidgetPositionSave(nextConfig);
  }

  void _scheduleDesktopWidgetPositionSave(AppConfig config) {
    _pendingDesktopWidgetPositionConfig = config;
    _desktopWidgetPositionSaveTimer?.cancel();
    _desktopWidgetPositionSaveTimer = Timer(
      const Duration(milliseconds: 200),
      _flushDesktopWidgetPositionSave,
    );
  }

  void _flushDesktopWidgetPositionSave() {
    final config = _pendingDesktopWidgetPositionConfig;
    if (config == null) {
      return;
    }
    _pendingDesktopWidgetPositionConfig = null;
    _desktopWidgetPositionSaveTimer?.cancel();
    _desktopWidgetPositionSaveTimer = null;
    unawaited(_saveDesktopWidgetPosition(config));
  }

  Future<void> _saveDesktopWidgetPosition(AppConfig config) async {
    try {
      await widget.localDataService.saveConfig(config);
    } catch (_) {
      // Position persistence is best-effort and should not interrupt dragging.
    }
  }

  void _selectSection(AppSection section) {
    if (_section == section) {
      return;
    }
    setState(() => _section = section);
  }

  void _handleLevelProgressChanged() {
    if (mounted) {
      setState(() {});
    }
    _syncDesktopWidgetWindow();
  }

  void _handleLocalDataStateChanged(LocalDataState state) {
    setState(() {
      _localDataState = state;
      _desktopWidgetController.attach(_localDataState);
      _levelProgressController.attach(_localDataState);
    });
    widget.onConfigChanged?.call(state.config);
    _syncDesktopWidgetWindow();
    _syncAutoStart(state.config);
    _syncTray(state.config);
    _syncGlobalHotkey(state.config);
    unawaited(_runStartupReportGeneration(state));
    unawaited(_runUpdateCheck(state.config));
  }

  void _notifyNoteSaved(NoteKind kind, String path) {
    _noteExternalUpdate.value = NoteExternalUpdate(
      kind: kind,
      path: path,
      revision: ++_noteExternalUpdateRevision,
    );
  }

  void _syncGlobalHotkey(AppConfig config) {
    unawaited(
      _globalHotkeyService.setToggleWindowHotkey(
        config.hotkeys['toggleWindow'],
      ),
    );
  }

  void _syncAutoStart(AppConfig config) {
    unawaited(_autoStartService.setEnabled(config.autoStart));
  }

  void _syncTray(AppConfig config) {
    unawaited(_trayService.sync(config));
  }

  Future<void> _runStartupReportGeneration(
    LocalDataState localDataState,
  ) async {
    try {
      final reports = await widget.startupReportGenerationService
          .generateMissingReports(localDataState: localDataState);
      if (!mounted ||
          localDataState.dataDirectory != _localDataState.dataDirectory) {
        return;
      }
      for (final report in reports) {
        _notifyNoteSaved(report.kind, report.path);
      }
    } catch (_) {
      // Startup report generation is opportunistic and must not block the app.
    }
  }

  Future<void> _runUpdateCheck(AppConfig config) async {
    if (!config.showUpdates) {
      if (mounted) {
        setState(() => _updateCheckResult = UpdateCheckResult.idle);
      }
      return;
    }

    final result = await widget.updateCheckService.check();
    if (!mounted || config != _localDataState.config) {
      return;
    }
    setState(() => _updateCheckResult = result);
  }

  void _syncDesktopWidgetWindow() {
    if (!_desktopWidgetWindow.isSupported) {
      return;
    }
    if (!_localDataState.config.showDesktopWidget) {
      unawaited(_desktopWidgetWindow.hide());
      return;
    }

    final state = _desktopWidgetController.state;
    final config = _localDataState.config;
    final progress = (_levelProgressController.state.experiencePercent / 100)
        .clamp(0.0, 1.0);
    unawaited(
      _desktopWidgetWindow.showOrUpdate(
        DesktopWidgetWindowSnapshot(
          running: state.running,
          workSeconds: state.workSeconds,
          coins: state.coins,
          coinRatePerSecond: _desktopWidgetController.coinRatePerSecond,
          level: _levelProgressController.state.level,
          experiencePercent: _levelProgressController.state.experiencePercent,
          progress: progress,
          appFont: config.appFont,
          fontScaleFactor: AppTheme.fontScaleFactor(config.fontScale),
          position: config.desktopWidgetPosition,
          orbMode: config.desktopWidgetOrbMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              GlobalSidebar(
                selectedSection: _section,
                onSectionSelected: _selectSection,
              ),
              Expanded(
                child: IndexedStack(
                  index: _section.index,
                  children: [
                    HomePage(
                      localDataState: _localDataState,
                      desktopWidgetController: _desktopWidgetController,
                      levelProgressController: _levelProgressController,
                      updateCheckResult: _updateCheckResult,
                      onDailyNoteSaved: (path) =>
                          _notifyNoteSaved(NoteKind.daily, path),
                    ),
                    NotesPage(
                      localDataState: _localDataState,
                      externalNoteUpdate: _noteExternalUpdate,
                    ),
                    MemoryPage(localDataState: _localDataState),
                    SettingsPage(
                      localDataState: _localDataState,
                      onConfigChanged: (config) {
                        final state = _localDataState.copyWith(config: config);
                        _handleLocalDataStateChanged(state);
                      },
                      onLocalDataStateChanged: _handleLocalDataStateChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_localDataState.config.showDesktopWidget &&
              !_desktopWidgetWindow.isSupported)
            Positioned(
              right: 26,
              bottom: 24,
              child: DesktopStatusWidget(
                controller: _desktopWidgetController,
                levelProgressState: _levelProgressController.state,
                onOpenHome: _openHomeFromDesktopWidget,
              ),
            ),
        ],
      ),
    );
  }
}

class GlobalSidebar extends StatelessWidget {
  const GlobalSidebar({
    super.key,
    required this.selectedSection,
    required this.onSectionSelected,
  });

  final AppSection selectedSection;
  final ValueChanged<AppSection> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      color: AppTheme.sidebar,
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          _SidebarButton(
            icon: _SidebarIconType.layoutDashboard,
            tooltip: '首页',
            selected: selectedSection == AppSection.home,
            onPressed: () => onSectionSelected(AppSection.home),
          ),
          const SizedBox(height: 8),
          _SidebarButton(
            icon: _SidebarIconType.stickyNote,
            tooltip: '便签',
            selected: selectedSection == AppSection.notes,
            onPressed: () => onSectionSelected(AppSection.notes),
          ),
          const SizedBox(height: 8),
          _SidebarButton(
            icon: _SidebarIconType.bookOpen,
            tooltip: '回忆书',
            selected: selectedSection == AppSection.memory,
            onPressed: () => onSectionSelected(AppSection.memory),
          ),
          const Spacer(),
          _SidebarButton(
            icon: _SidebarIconType.settings,
            tooltip: '设置',
            selected: selectedSection == AppSection.settings,
            onPressed: () => onSectionSelected(AppSection.settings),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatefulWidget {
  const _SidebarButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final _SidebarIconType icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;
    final backgroundColor = widget.selected
        ? const Color(0xFFE2E2E2)
        : const Color(0xFFF5F5F5);
    final iconColor = active ? AppTheme.text : AppTheme.textSubtle;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
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
                _SidebarLucideIcon(
                  type: widget.icon,
                  size: 16,
                  color: iconColor,
                ),
                Opacity(
                  opacity: 0,
                  child: Icon(_legacyMaterialIcon(widget.icon), size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _legacyMaterialIcon(_SidebarIconType icon) {
  return switch (icon) {
    _SidebarIconType.layoutDashboard => Icons.dashboard_outlined,
    _SidebarIconType.stickyNote => Icons.sticky_note_2_outlined,
    _SidebarIconType.bookOpen => Icons.menu_book_outlined,
    _SidebarIconType.settings => Icons.settings_outlined,
  };
}

enum _SidebarIconType { layoutDashboard, stickyNote, bookOpen, settings }

class _SidebarLucideIcon extends StatelessWidget {
  const _SidebarLucideIcon({
    required this.type,
    required this.size,
    required this.color,
  });

  final _SidebarIconType type;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CustomPaint(
        size: Size.square(size),
        painter: _SidebarLucidePainter(type: type, color: color),
      ),
    );
  }
}

class _SidebarLucidePainter extends CustomPainter {
  const _SidebarLucidePainter({required this.type, required this.color});

  final _SidebarIconType type;
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
    RRect roundedRect(double x, double y, double w, double h, double radius) {
      return RRect.fromRectAndRadius(
        Rect.fromLTWH(x * sx, y * sy, w * sx, h * sy),
        Radius.circular(radius * strokeScale),
      );
    }

    switch (type) {
      case _SidebarIconType.layoutDashboard:
        canvas.drawRRect(roundedRect(3, 3, 7, 9, 1), paint);
        canvas.drawRRect(roundedRect(14, 3, 7, 5, 1), paint);
        canvas.drawRRect(roundedRect(14, 12, 7, 9, 1), paint);
        canvas.drawRRect(roundedRect(3, 16, 7, 5, 1), paint);
        break;
      case _SidebarIconType.stickyNote:
        final notePath = Path()
          ..moveTo(16 * sx, 3 * sy)
          ..lineTo(5 * sx, 3 * sy)
          ..cubicTo(3.9 * sx, 3 * sy, 3 * sx, 3.9 * sy, 3 * sx, 5 * sy)
          ..lineTo(3 * sx, 19 * sy)
          ..cubicTo(3 * sx, 20.1 * sy, 3.9 * sx, 21 * sy, 5 * sx, 21 * sy)
          ..lineTo(19 * sx, 21 * sy)
          ..cubicTo(20.1 * sx, 21 * sy, 21 * sx, 20.1 * sy, 21 * sx, 19 * sy)
          ..lineTo(21 * sx, 8 * sy)
          ..lineTo(16 * sx, 3 * sy)
          ..close();
        canvas.drawPath(notePath, paint);
        final foldPath = Path()
          ..moveTo(15 * sx, 3 * sy)
          ..lineTo(15 * sx, 8 * sy)
          ..cubicTo(15 * sx, 8.55 * sy, 15.45 * sx, 9 * sy, 16 * sx, 9 * sy)
          ..lineTo(21 * sx, 9 * sy);
        canvas.drawPath(foldPath, paint);
        break;
      case _SidebarIconType.bookOpen:
        final bookPath = Path()
          ..moveTo(12 * sx, 7 * sy)
          ..lineTo(12 * sx, 21 * sy)
          ..moveTo(3 * sx, 18 * sy)
          ..cubicTo(2.45 * sx, 18 * sy, 2 * sx, 17.55 * sy, 2 * sx, 17 * sy)
          ..lineTo(2 * sx, 4 * sy)
          ..cubicTo(2 * sx, 3.45 * sy, 2.45 * sx, 3 * sy, 3 * sx, 3 * sy)
          ..lineTo(8 * sx, 3 * sy)
          ..cubicTo(10.2 * sx, 3 * sy, 12 * sx, 4.8 * sy, 12 * sx, 7 * sy)
          ..cubicTo(12 * sx, 4.8 * sy, 13.8 * sx, 3 * sy, 16 * sx, 3 * sy)
          ..lineTo(21 * sx, 3 * sy)
          ..cubicTo(21.55 * sx, 3 * sy, 22 * sx, 3.45 * sy, 22 * sx, 4 * sy)
          ..lineTo(22 * sx, 17 * sy)
          ..cubicTo(22 * sx, 17.55 * sy, 21.55 * sx, 18 * sy, 21 * sx, 18 * sy)
          ..lineTo(15 * sx, 18 * sy)
          ..cubicTo(13.35 * sx, 18 * sy, 12 * sx, 19.35 * sy, 12 * sx, 21 * sy)
          ..cubicTo(12 * sx, 19.35 * sy, 10.65 * sx, 18 * sy, 9 * sx, 18 * sy)
          ..lineTo(3 * sx, 18 * sy);
        canvas.drawPath(bookPath, paint);
        break;
      case _SidebarIconType.settings:
        final settingsPath = Path()
          ..moveTo(12.22 * sx, 2 * sy)
          ..lineTo(11.78 * sx, 2 * sy)
          ..cubicTo(10.68 * sx, 2 * sy, 9.78 * sx, 2.9 * sy, 9.78 * sx, 4 * sy)
          ..lineTo(9.78 * sx, 4.18 * sy)
          ..cubicTo(
            9.78 * sx,
            4.89 * sy,
            9.4 * sx,
            5.54 * sy,
            8.78 * sx,
            5.91 * sy,
          )
          ..lineTo(8.35 * sx, 6.16 * sy)
          ..cubicTo(
            7.73 * sx,
            6.52 * sy,
            6.97 * sx,
            6.52 * sy,
            6.35 * sx,
            6.16 * sy,
          )
          ..lineTo(6.2 * sx, 6.08 * sy)
          ..cubicTo(
            5.25 * sx,
            5.53 * sy,
            4.03 * sx,
            5.86 * sy,
            3.48 * sx,
            6.81 * sy,
          )
          ..lineTo(3.26 * sx, 7.19 * sy)
          ..cubicTo(
            2.71 * sx,
            8.14 * sy,
            3.04 * sx,
            9.36 * sy,
            3.99 * sx,
            9.91 * sy,
          )
          ..lineTo(4.14 * sx, 10 * sy)
          ..cubicTo(
            4.76 * sx,
            10.36 * sy,
            5.14 * sx,
            11.02 * sy,
            5.14 * sx,
            11.74 * sy,
          )
          ..lineTo(5.14 * sx, 12.25 * sy)
          ..cubicTo(
            5.14 * sx,
            12.98 * sy,
            4.76 * sx,
            13.64 * sy,
            4.13 * sx,
            14 * sy,
          )
          ..lineTo(3.98 * sx, 14.09 * sy)
          ..cubicTo(
            3.03 * sx,
            14.64 * sy,
            2.7 * sx,
            15.86 * sy,
            3.25 * sx,
            16.81 * sy,
          )
          ..lineTo(3.47 * sx, 17.19 * sy)
          ..cubicTo(
            4.02 * sx,
            18.14 * sy,
            5.24 * sx,
            18.47 * sy,
            6.19 * sx,
            17.92 * sy,
          )
          ..lineTo(6.34 * sx, 17.84 * sy)
          ..cubicTo(
            6.96 * sx,
            17.48 * sy,
            7.72 * sx,
            17.48 * sy,
            8.34 * sx,
            17.84 * sy,
          )
          ..lineTo(8.77 * sx, 18.09 * sy)
          ..cubicTo(
            9.39 * sx,
            18.45 * sy,
            9.77 * sx,
            19.11 * sy,
            9.77 * sx,
            19.82 * sy,
          )
          ..lineTo(9.77 * sx, 20 * sy)
          ..cubicTo(
            9.77 * sx,
            21.1 * sy,
            10.67 * sx,
            22 * sy,
            11.77 * sx,
            22 * sy,
          )
          ..lineTo(12.21 * sx, 22 * sy)
          ..cubicTo(
            13.31 * sx,
            22 * sy,
            14.21 * sx,
            21.1 * sy,
            14.21 * sx,
            20 * sy,
          )
          ..lineTo(14.21 * sx, 19.82 * sy)
          ..cubicTo(
            14.21 * sx,
            19.11 * sy,
            14.59 * sx,
            18.46 * sy,
            15.21 * sx,
            18.09 * sy,
          )
          ..lineTo(15.64 * sx, 17.84 * sy)
          ..cubicTo(
            16.26 * sx,
            17.48 * sy,
            17.02 * sx,
            17.48 * sy,
            17.64 * sx,
            17.84 * sy,
          )
          ..lineTo(17.79 * sx, 17.92 * sy)
          ..cubicTo(
            18.74 * sx,
            18.47 * sy,
            19.96 * sx,
            18.14 * sy,
            20.51 * sx,
            17.19 * sy,
          )
          ..lineTo(20.73 * sx, 16.8 * sy)
          ..cubicTo(
            21.28 * sx,
            15.85 * sy,
            20.95 * sx,
            14.63 * sy,
            20 * sx,
            14.08 * sy,
          )
          ..lineTo(19.85 * sx, 14 * sy)
          ..cubicTo(
            19.23 * sx,
            13.64 * sy,
            18.85 * sx,
            12.98 * sy,
            18.85 * sx,
            12.25 * sy,
          )
          ..lineTo(18.85 * sx, 11.75 * sy)
          ..cubicTo(
            18.85 * sx,
            11.02 * sy,
            19.23 * sx,
            10.36 * sy,
            19.86 * sx,
            10 * sy,
          )
          ..lineTo(20.01 * sx, 9.91 * sy)
          ..cubicTo(
            20.96 * sx,
            9.36 * sy,
            21.29 * sx,
            8.14 * sy,
            20.74 * sx,
            7.19 * sy,
          )
          ..lineTo(20.52 * sx, 6.81 * sy)
          ..cubicTo(
            19.97 * sx,
            5.86 * sy,
            18.75 * sx,
            5.53 * sy,
            17.8 * sx,
            6.08 * sy,
          )
          ..lineTo(17.65 * sx, 6.16 * sy)
          ..cubicTo(
            17.03 * sx,
            6.52 * sy,
            16.27 * sx,
            6.52 * sy,
            15.65 * sx,
            6.16 * sy,
          )
          ..lineTo(15.22 * sx, 5.91 * sy)
          ..cubicTo(
            14.6 * sx,
            5.55 * sy,
            14.22 * sx,
            4.89 * sy,
            14.22 * sx,
            4.18 * sy,
          )
          ..lineTo(14.22 * sx, 4 * sy)
          ..cubicTo(
            14.22 * sx,
            2.9 * sy,
            13.32 * sx,
            2 * sy,
            12.22 * sx,
            2 * sy,
          );
        canvas.drawPath(settingsPath, paint);
        canvas.drawCircle(point(12, 12), 3 * strokeScale, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SidebarLucidePainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}
