import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/home/home_page.dart';
import '../../features/memory/memory_page.dart';
import '../../features/notes/notes_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/widget/desktop_status_widget.dart';
import '../models/local_data_state.dart';
import '../services/desktop_widget_controller.dart';
import '../services/desktop_widget_window_bridge.dart';
import '../services/level_progress_controller.dart';
import '../theme/app_theme.dart';

enum AppSection { home, notes, memory, settings }

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.localDataState});

  final LocalDataState localDataState;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection _section = AppSection.home;
  late LocalDataState _localDataState = widget.localDataState;
  late final DesktopWidgetController _desktopWidgetController =
      DesktopWidgetController()..attach(_localDataState);
  late final DesktopWidgetWindowBridge _desktopWidgetWindow =
      DesktopWidgetWindowBridge();
  late final LevelProgressController _levelProgressController =
      LevelProgressController()..attach(_localDataState);

  @override
  void initState() {
    super.initState();
    _desktopWidgetController.addListener(_syncDesktopWidgetWindow);
    _levelProgressController.addListener(_handleLevelProgressChanged);
    unawaited(
      _desktopWidgetWindow.initialize(
        onToggle: _desktopWidgetController.toggle,
        onOpenHome: _openHomeFromDesktopWidget,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncDesktopWidgetWindow();
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
    }
  }

  @override
  void dispose() {
    _desktopWidgetController.removeListener(_syncDesktopWidgetWindow);
    _levelProgressController.removeListener(_handleLevelProgressChanged);
    unawaited(_desktopWidgetWindow.dispose());
    _desktopWidgetController.dispose();
    _levelProgressController.dispose();
    super.dispose();
  }

  void _openHomeFromDesktopWidget() {
    if (!mounted) {
      return;
    }
    setState(() => _section = AppSection.home);
  }

  void _handleLevelProgressChanged() {
    if (mounted) {
      setState(() {});
    }
    _syncDesktopWidgetWindow();
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
    final workHours = _localDataState.config.dailyWorkHours <= 0
        ? 8.0
        : _localDataState.config.dailyWorkHours;
    final progress = (state.workSeconds / (workHours * 3600)).clamp(0.0, 1.0);
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
                onSectionSelected: (section) =>
                    setState(() => _section = section),
              ),
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey(_section),
                  child: switch (_section) {
                    AppSection.home => HomePage(
                      localDataState: _localDataState,
                      desktopWidgetController: _desktopWidgetController,
                      levelProgressController: _levelProgressController,
                    ),
                    AppSection.notes => NotesPage(
                      localDataState: _localDataState,
                    ),
                    AppSection.memory => MemoryPage(
                      localDataState: _localDataState,
                    ),
                    AppSection.settings => SettingsPage(
                      localDataState: _localDataState,
                      onConfigChanged: (config) {
                        setState(() {
                          _localDataState = _localDataState.copyWith(
                            config: config,
                          );
                          _desktopWidgetController.attach(_localDataState);
                          _levelProgressController.attach(_localDataState);
                        });
                        _syncDesktopWidgetWindow();
                      },
                    ),
                  },
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
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          _SidebarButton(
            icon: Icons.home_rounded,
            tooltip: '首页',
            selected: selectedSection == AppSection.home,
            onPressed: () => onSectionSelected(AppSection.home),
          ),
          const SizedBox(height: 8),
          _SidebarButton(
            icon: Icons.sticky_note_2_outlined,
            tooltip: '便签',
            selected: selectedSection == AppSection.notes,
            onPressed: () => onSectionSelected(AppSection.notes),
          ),
          const SizedBox(height: 8),
          _SidebarButton(
            icon: Icons.auto_stories_outlined,
            tooltip: '回忆书',
            selected: selectedSection == AppSection.memory,
            onPressed: () => onSectionSelected(AppSection.memory),
          ),
          const Spacer(),
          _SidebarButton(
            icon: Icons.settings_outlined,
            tooltip: '设置',
            selected: selectedSection == AppSection.settings,
            onPressed: () => onSectionSelected(AppSection.settings),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected ? AppTheme.surfaceMuted : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 20,
            color: selected ? AppTheme.text : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}
