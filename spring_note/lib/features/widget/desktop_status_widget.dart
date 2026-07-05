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
        final colors = AppTheme.colors(context);
        final progress = (levelProgressState.experiencePercent / 100).clamp(
          0.0,
          1.0,
        );
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
                color: colors.surface,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.16),
                    blurRadius: 24,
                    offset: Offset(0, 4),
                  ),
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.08),
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
                        'Lv.${levelProgressState.level} 实习生 (${levelProgressState.experiencePercent}%)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSubtle,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(1),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 2,
                          color: colors.textSubtle,
                          backgroundColor: colors.surfaceMuted,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    state.coins.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: colors.text,
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
                              ? '+${controller.coinRatePerSecond.toStringAsFixed(3)} coin/s'
                              : '+0.000 coin/s',
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
                          color: colors.textMuted,
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
    final colors = AppTheme.colors(context);
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: running ? const Color(0xFF10B981) : colors.textSubtle,
        shape: BoxShape.circle,
      ),
    );
  }
}
