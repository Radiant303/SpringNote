import 'package:flutter/material.dart';

import '../../core/services/desktop_widget_controller.dart';
import '../../core/services/level_progress_controller.dart';
import '../../core/theme/app_theme.dart';

class DesktopStatusWidget extends StatelessWidget {
  const DesktopStatusWidget({
    super.key,
    required this.controller,
    required this.levelProgressState,
    required this.onOpenHome,
  });

  final DesktopWidgetController controller;
  final LevelProgressState levelProgressState;
  final VoidCallback onOpenHome;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final progress = ((state.workSeconds / (8 * 3600)).clamp(0.0, 1.0));
        return GestureDetector(
          onTap: controller.toggle,
          onSecondaryTap: onOpenHome,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: 260,
              height: 140,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0x0A000000)),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 24,
                    offset: Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Color(0x05000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.running
                            ? 'Lv.${levelProgressState.level} 实习生 · 工作中'
                            : 'Lv.${levelProgressState.level} 实习生 · 已暂停',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSubtle,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'EXP ${levelProgressState.experiencePercent}% · 今日有效 ${levelProgressState.todayValidSubmissions}/10',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSubtle,
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(1),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 2,
                          color: const Color(0xFFCBD5E1),
                          backgroundColor: const Color(0xFFF1F5F9),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    state.coins.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: AppTheme.text,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: -1.5,
                      height: 1,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          state.running
                              ? '+${controller.coinRatePerSecond.toStringAsFixed(3)}/s'
                              : '+0.000/s',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: const Color(0xFF10B981),
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _StatusDot(running: state.running),
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(state.workSeconds),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.running});

  final bool running;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: running ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
        shape: BoxShape.circle,
      ),
    );
  }
}
