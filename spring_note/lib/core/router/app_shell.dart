import 'package:flutter/material.dart';

import '../../features/home/home_page.dart';
import '../../features/memory/memory_page.dart';
import '../../features/notes/notes_page.dart';
import '../../features/settings/settings_page.dart';
import '../models/local_data_state.dart';
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
                AppSection.home => HomePage(
                  localDataState: widget.localDataState,
                ),
                AppSection.notes => NotesPage(
                  localDataState: widget.localDataState,
                ),
                AppSection.memory => MemoryPage(
                  localDataState: widget.localDataState,
                ),
                AppSection.settings => SettingsPage(
                  localDataState: widget.localDataState,
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
