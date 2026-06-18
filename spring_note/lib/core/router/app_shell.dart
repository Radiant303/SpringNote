import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/home/home_page.dart';
import '../../features/memory/memory_page.dart';
import '../../features/notes/notes_page.dart';
import '../../features/settings/settings_page.dart';
import '../models/local_data_state.dart';
import '../services/stats_service.dart';
import '../theme/app_theme.dart';

enum AppSection { home, notes, memory, settings }

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.localDataState});

  final LocalDataState localDataState;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _workTick = Duration(minutes: 1);

  AppSection _section = AppSection.home;
  late LocalDataState _localDataState = widget.localDataState;
  final StatsService _statsService = const StatsService();
  Timer? _workTimer;

  @override
  void initState() {
    super.initState();
    _startWorkTimer();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.localDataState != oldWidget.localDataState) {
      _localDataState = widget.localDataState;
    }
  }

  @override
  void dispose() {
    _workTimer?.cancel();
    super.dispose();
  }

  void _startWorkTimer() {
    _workTimer = Timer.periodic(_workTick, (_) => _recordWorkTick());
  }

  Future<void> _recordWorkTick() async {
    final workHours = _localDataState.config.dailyWorkHours;
    final secondsPerDay = (workHours <= 0 ? 8 : workHours) * 3600;
    final coins =
        _localDataState.config.dailySalary *
        _workTick.inSeconds /
        secondsPerDay;
    await _statsService.recordWorkTime(
      appDataDir: _localDataState.dataDirectory,
      workSeconds: _workTick.inSeconds,
      coins: coins,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          GlobalSidebar(
            selectedSection: _section,
            onSectionSelected: (section) => setState(() => _section = section),
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(_section),
              child: switch (_section) {
                AppSection.home => HomePage(localDataState: _localDataState),
                AppSection.notes => NotesPage(localDataState: _localDataState),
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
                    });
                  },
                ),
              },
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
