import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/models/local_data_state.dart';
import '../../core/services/stats_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/context_extensions.dart';
import '../../src/rust/stats.dart' as rust_stats;

class SettingsStatsPanel extends StatefulWidget {
  const SettingsStatsPanel({super.key, required this.localDataState});

  final LocalDataState localDataState;

  @override
  State<SettingsStatsPanel> createState() => _SettingsStatsPanelState();
}

class _SettingsStatsPanelState extends State<SettingsStatsPanel> {
  final StatsService _statsService = const StatsService();
  _StatsRangePreset _rangePreset = _StatsRangePreset.recent30;
  late DateTime _customStart = _dateOnly(
    DateTime.now().subtract(const Duration(days: 29)),
  );
  late DateTime _customEnd = _dateOnly(DateTime.now());
  late Future<_StatsPanelData> _future = _loadStats();

  @override
  void didUpdateWidget(covariant SettingsStatsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.localDataState.dataDirectory !=
        oldWidget.localDataState.dataDirectory) {
      _future = _loadStats();
    }
  }

  Future<_StatsPanelData> _loadStats() async {
    final today = _dateOnly(DateTime.now());
    final range = _rangeFor(_rangePreset, today);
    final results = await Future.wait([
      _statsService.readSnapshot(
        localDataState: widget.localDataState,
        start: range.start,
        end: range.end,
      ),
      _statsService.readSnapshot(
        localDataState: widget.localDataState,
        start: DateTime(today.year - 1, today.month, today.day),
        end: today,
      ),
    ]);
    return _StatsPanelData(
      selected: results[0],
      yearly: results[1],
      range: range,
    );
  }

  _StatsDateRange _rangeFor(_StatsRangePreset preset, DateTime today) {
    return switch (preset) {
      _StatsRangePreset.all => _StatsDateRange(
        start: DateTime(2000),
        end: today,
        label: '全部',
        all: true,
      ),
      _StatsRangePreset.recent30 => _StatsDateRange(
        start: today.subtract(const Duration(days: 29)),
        end: today,
        label: '最近30天',
      ),
      _StatsRangePreset.lastMonth => _lastMonthRange(today),
      _StatsRangePreset.lastQuarter => _lastQuarterRange(today),
      _StatsRangePreset.custom => _StatsDateRange(
        start: _customStart,
        end: _customEnd,
        label:
            '${StatsService.formatDate(_customStart)} 至 ${StatsService.formatDate(_customEnd)}',
      ),
    };
  }

  _StatsDateRange _lastMonthRange(DateTime today) {
    final start = DateTime(today.year, today.month - 1);
    final end = DateTime(today.year, today.month, 0);
    return _StatsDateRange(start: start, end: end, label: '上个月');
  }

  _StatsDateRange _lastQuarterRange(DateTime today) {
    final currentQuarterStartMonth = ((today.month - 1) ~/ 3) * 3 + 1;
    final currentQuarterStart = DateTime(today.year, currentQuarterStartMonth);
    final start = DateTime(
      currentQuarterStart.year,
      currentQuarterStart.month - 3,
    );
    final end = currentQuarterStart.subtract(const Duration(days: 1));
    return _StatsDateRange(start: start, end: end, label: '上个季度');
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  Future<void> _selectRange(_StatsRangePreset preset) async {
    if (preset == _StatsRangePreset.custom) {
      final result = await showDialog<_StatsDateRange>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.48),
        builder: (context) =>
            _StatsCustomRangeDialog(start: _customStart, end: _customEnd),
      );
      if (result == null) {
        return;
      }
      setState(() {
        _rangePreset = preset;
        _customStart = result.start;
        _customEnd = result.end;
        _future = _loadStats();
      });
      return;
    }

    setState(() {
      _rangePreset = preset;
      _future = _loadStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StatsPanelData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final selected = data?.selected ?? StatsService.emptySnapshot;
        final yearly = data?.yearly ?? StatsService.emptySnapshot;
        final range = data?.range ?? _rangeFor(_rangePreset, DateTime.now());
        final loading = snapshot.connectionState != ConnectionState.done;

        return _StatsScrollFrame(
          children: [
            _StatsRangeSelector(
              selected: _rangePreset,
              loading: loading,
              onSelected: _selectRange,
            ),
            _StatsSectionCard(
              title: '年度热力图',
              child: _YearHeatmap(activity: yearly.activity),
            ),
            _StatsSectionCard(
              title: '总览',
              child: _StatsMetricsGrid(snapshot: selected),
            ),
            _StatsSectionCard(
              title: '用量趋势',
              subtitle: range.label,
              child: _UsageTrendChart(snapshot: selected, range: range),
            ),
          ],
        );
      },
    );
  }
}

enum _StatsRangePreset { all, recent30, lastMonth, lastQuarter, custom }

class _StatsDateRange {
  const _StatsDateRange({
    required this.start,
    required this.end,
    required this.label,
    this.all = false,
  });

  final DateTime start;
  final DateTime end;
  final String label;
  final bool all;
}

class _StatsPanelData {
  const _StatsPanelData({
    required this.selected,
    required this.yearly,
    required this.range,
  });

  final rust_stats.StatsSnapshot selected;
  final rust_stats.StatsSnapshot yearly;
  final _StatsDateRange range;
}

class _StatsScrollFrame extends StatelessWidget {
  const _StatsScrollFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 30, 30, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
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

class _StatsRangeSelector extends StatelessWidget {
  const _StatsRangeSelector({
    required this.selected,
    required this.loading,
    required this.onSelected,
  });

  final _StatsRangePreset selected;
  final bool loading;
  final ValueChanged<_StatsRangePreset> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = const [
      (_StatsRangePreset.all, '全部'),
      (_StatsRangePreset.recent30, '最近 30 天'),
      (_StatsRangePreset.lastMonth, '上个月'),
      (_StatsRangePreset.lastQuarter, '上个季度'),
      (_StatsRangePreset.custom, '自定义'),
    ];
    return Row(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              _StatsRangeChip(
                key: ValueKey(item.$1),
                label: item.$2,
                selected: selected == item.$1,
                onTap: () => onSelected(item.$1),
              ),
          ],
        ),
        const Spacer(),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: loading ? 1 : 0,
          child: const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.8),
          ),
        ),
      ],
    );
  }
}

class _StatsRangeChip extends StatefulWidget {
  const _StatsRangeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_StatsRangeChip> createState() => _StatsRangeChipState();
}

class _StatsRangeChipState extends State<_StatsRangeChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;
    final backgroundColor = widget.selected
        ? context.appCardBgHover
        : context.appCardBgHover;
    final contentColor = active
        ? context.appTextPrimary
        : context.appTextTertiary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 34,
          child: Stack(
            alignment: Alignment.center,
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
                          borderRadius: BorderRadius.circular(999),
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
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Text(
                      widget.label,
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: animatedColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1,
                          ) ??
                          TextStyle(
                            color: animatedColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1,
                          ),
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

class _StatsSectionCard extends StatelessWidget {
  const _StatsSectionCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border.all(color: context.appBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: context.appTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
              const Spacer(),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.appTextTertiary,
                    fontSize: 12,
                    height: 1,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 5
            : constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _StatsMetricCard(
                  label: metric.$1,
                  value: _formatCompactNumber(metric.$2),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatsMetricCard extends StatelessWidget {
  const _StatsMetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: context.appCardBgHover,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: context.appTextPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.appTextTertiary,
              fontSize: 11,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _YearHeatmap extends StatefulWidget {
  const _YearHeatmap({required this.activity});

  final List<rust_stats.DailyActivity> activity;

  static List<Color> _colorsFor(BuildContext context) => [
    context.appBgSecondary,
    const Color(0xFFDCFCE7),
    const Color(0xFFBBF7D0),
    const Color(0xFF86EFAC),
    const Color(0xFF4ADE80),
  ];
  static const double _cellSize = 12;
  static const double _gap = 5;

  @override
  State<_YearHeatmap> createState() => _YearHeatmapState();
}

class _YearHeatmapState extends State<_YearHeatmap> {
  final ScrollController _controller = ScrollController();
  final GlobalKey _gridKey = GlobalKey();
  OverlayEntry? _tooltipOverlay;
  int? _hoveredSlotIndex;

  double get _pitch => _YearHeatmap._cellSize + _YearHeatmap._gap;
  double get _gridHeight =>
      (7 * _YearHeatmap._cellSize) + (6 * _YearHeatmap._gap);

  @override
  void didUpdateWidget(covariant _YearHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _alignToLatestAfterLayout();
  }

  @override
  void dispose() {
    _removeTooltipOverlay();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _alignToLatestAfterLayout();
    final heatmapColors = _YearHeatmap._colorsFor(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final heatmapStart = DateTime(today.year - 1, today.month, today.day);
    final totalDays = today.difference(heatmapStart).inDays + 1;
    final startOffset = heatmapStart.weekday % 7;
    final totalWeeks = ((startOffset + totalDays) / 7).ceil();
    final activityByDate = {
      for (final item in widget.activity) item.date: item.count,
    };
    final slots = List<DateTime?>.filled(totalWeeks * 7, null);
    final monthLabels = List<String>.filled(totalWeeks, '');
    final gridWidth =
        (totalWeeks * _YearHeatmap._cellSize) +
        ((totalWeeks - 1) * _YearHeatmap._gap);
    int? lastMonth;

    for (var index = 0; index < totalDays; index++) {
      final date = heatmapStart.add(Duration(days: index));
      final slotIndex = startOffset + index;
      slots[slotIndex] = date;
      final weekIndex = slotIndex ~/ 7;
      if (date.month != lastMonth) {
        monthLabels[weekIndex] = '${date.month}月';
        lastMonth = date.month;
      }
    }

    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 30),
                for (final label in monthLabels)
                  Padding(
                    padding: const EdgeInsets.only(right: _YearHeatmap._gap),
                    child: SizedBox(
                      width: _YearHeatmap._cellSize,
                      height: 20,
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        maxWidth: 42,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            label,
                            softWrap: false,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: context.appTextTertiary,
                                  fontSize: 13,
                                  height: 1,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeatmapWeekdayLabels(textStyle: Theme.of(context).textTheme),
                const SizedBox(width: 8),
                MouseRegion(
                  cursor: _hoveredSlotIndex == null
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  onHover: (event) => _updateHoveredSlotIndex(
                    event.localPosition,
                    totalWeeks,
                    slots,
                  ),
                  onExit: (_) => _clearHoveredSlotIndex(),
                  child: SizedBox(
                    key: _gridKey,
                    width: gridWidth,
                    height: _gridHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var week = 0; week < totalWeeks; week++)
                          for (var row = 0; row < 7; row++)
                            Positioned(
                              left: week * _pitch,
                              top: row * _pitch,
                              child: _HeatmapCell(
                                date: slots[week * 7 + row],
                                countByDate: activityByDate,
                                colors: heatmapColors,
                                hovered: _hoveredSlotIndex == week * 7 + row,
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _updateHoveredSlotIndex(
    Offset position,
    int totalWeeks,
    List<DateTime?> slots,
  ) {
    final nextIndex = _hitTestSlotIndex(position, totalWeeks, slots);
    if (nextIndex == _hoveredSlotIndex) {
      return;
    }
    setState(() => _hoveredSlotIndex = nextIndex);
    if (nextIndex == null) {
      _removeTooltipOverlay();
      return;
    }
    _showTooltipOverlay(nextIndex, slots);
  }

  void _clearHoveredSlotIndex() {
    if (_hoveredSlotIndex == null) {
      return;
    }
    setState(() => _hoveredSlotIndex = null);
    _removeTooltipOverlay();
  }

  int? _hitTestSlotIndex(
    Offset position,
    int totalWeeks,
    List<DateTime?> slots,
  ) {
    final gridWidth =
        (totalWeeks * _YearHeatmap._cellSize) +
        ((totalWeeks - 1) * _YearHeatmap._gap);
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx > gridWidth ||
        position.dy > _gridHeight) {
      return null;
    }

    final columnIndex = (position.dx / _pitch).floor();
    final rowIndex = (position.dy / _pitch).floor();
    if (columnIndex < 0 ||
        columnIndex >= totalWeeks ||
        rowIndex < 0 ||
        rowIndex >= 7) {
      return null;
    }
    final slotIndex = columnIndex * 7 + rowIndex;
    if (slotIndex < 0 ||
        slotIndex >= slots.length ||
        slots[slotIndex] == null) {
      return null;
    }
    return slotIndex;
  }

  void _showTooltipOverlay(int slotIndex, List<DateTime?> slots) {
    final date = slots[slotIndex];
    final gridContext = _gridKey.currentContext;
    final overlay = Overlay.of(context);
    if (date == null || gridContext == null) {
      _removeTooltipOverlay();
      return;
    }

    final gridBox = gridContext.findRenderObject() as RenderBox?;
    if (gridBox == null || !gridBox.hasSize) {
      _removeTooltipOverlay();
      return;
    }

    final dateLabel = StatsService.formatDate(date);
    var count = 0;
    for (final item in widget.activity) {
      if (item.date == dateLabel) {
        count = item.count;
        break;
      }
    }
    final columnIndex = slotIndex ~/ 7;
    final rowIndex = slotIndex % 7;
    final cellCenter = Offset(
      columnIndex * _pitch + (_YearHeatmap._cellSize / 2),
      rowIndex * _pitch,
    );
    final globalCenter = gridBox.localToGlobal(cellCenter);
    final screenWidth = MediaQuery.sizeOf(context).width;
    const tooltipWidth = 196.0;
    const tooltipHeight = 34.0;
    final left = (globalCenter.dx - tooltipWidth / 2)
        .clamp(8.0, screenWidth - tooltipWidth - 8.0)
        .toDouble();
    final top = (globalCenter.dy - tooltipHeight - 8)
        .clamp(8.0, double.infinity)
        .toDouble();

    _removeTooltipOverlay();
    _tooltipOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: left,
          top: top,
          width: tooltipWidth,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: Align(
                alignment: Alignment.center,
                child: _StatsHeatmapTooltip(count: count, dateLabel: dateLabel),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_tooltipOverlay!);
  }

  void _removeTooltipOverlay() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
  }

  void _alignToLatestAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      final maxScrollExtent = _controller.position.maxScrollExtent;
      if (maxScrollExtent <= 0 || _controller.offset == maxScrollExtent) {
        return;
      }
      _controller.jumpTo(maxScrollExtent);
    });
  }
}

class _HeatmapWeekdayLabels extends StatelessWidget {
  const _HeatmapWeekdayLabels({required this.textStyle});

  final TextTheme textStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      child: Column(
        children: [
          for (var index = 0; index < 7; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == 6 ? 0 : _YearHeatmap._gap,
              ),
              child: SizedBox(
                height: _YearHeatmap._cellSize,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    switch (index) {
                      1 => '一',
                      3 => '三',
                      5 => '五',
                      _ => '',
                    },
                    style: textStyle.bodySmall?.copyWith(
                      color: context.appTextTertiary,
                      fontSize: 13,
                      height: 1,
                    ),
                  ),
                ),
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
    required this.countByDate,
    required this.colors,
    required this.hovered,
  });

  final DateTime? date;
  final Map<String, int> countByDate;
  final List<Color> colors;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    if (date == null) {
      return const SizedBox(
        width: _YearHeatmap._cellSize,
        height: _YearHeatmap._cellSize,
      );
    }
    final count = countByDate[StatsService.formatDate(date)] ?? 0;
    return AnimatedScale(
      scale: hovered ? 1.1 : 1,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors[_level(count)],
          borderRadius: BorderRadius.circular(3),
        ),
        child: const SizedBox(
          width: _YearHeatmap._cellSize,
          height: _YearHeatmap._cellSize,
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

class _StatsHeatmapTooltip extends StatelessWidget {
  const _StatsHeatmapTooltip({required this.count, required this.dateLabel});

  final int count;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.appCardBg,
          border: Border.all(color: context.appBorder),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: const Color(0x05000000).withValues(alpha: 0.24),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Text.rich(
          _tooltipMessage(context),
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }

  InlineSpan _tooltipMessage(BuildContext context) {
    final baseStyle = TextStyle(
      color: context.appTextPrimary,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );

    if (count == 0) {
      return TextSpan(
        style: baseStyle,
        children: [
          TextSpan(
            text: 'No contributions on ',
            style: TextStyle(color: context.appTextTertiary),
          ),
          TextSpan(
            text: dateLabel,
            style: TextStyle(
              color: context.appTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return TextSpan(
      style: baseStyle,
      children: [
        TextSpan(
          text: '$count ${count == 1 ? 'commit' : 'commits'}',
          style: TextStyle(
            color: context.appTextPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        TextSpan(
          text: ' on ',
          style: TextStyle(color: context.appTextTertiary),
        ),
        TextSpan(
          text: dateLabel,
          style: TextStyle(
            color: context.appTextSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _UsageTrendChart extends StatefulWidget {
  const _UsageTrendChart({required this.snapshot, required this.range});

  final rust_stats.StatsSnapshot snapshot;
  final _StatsDateRange range;

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
    final series = _buildProviderSeries(widget.snapshot.providerUsage);
    final days = _buildUsageDays(widget.snapshot, series);
    final maxTokens = days.fold<int>(
      1,
      (max, point) => point.totalTokens > max ? point.totalTokens : max,
    );
    final providers = series.providers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Listener(
          onPointerSignal: _handlePointerSignal,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final metrics = _usageDayMetrics(days.length);
              final contentWidth =
                  days.length * metrics.width +
                  math.max(0, days.length - 1) * metrics.gap;
              final trackWidth = math.max(contentWidth, constraints.maxWidth);
              return SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: trackWidth,
                  height: 236,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 39,
                        child: Row(
                          children: [
                            for (var index = 0; index < days.length; index++)
                              Padding(
                                padding: EdgeInsets.only(
                                  right: index == days.length - 1
                                      ? 0
                                      : metrics.gap,
                                ),
                                child: Container(
                                  width: metrics.width,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: context.appCardBgHover,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        bottom: 39,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var index = 0; index < days.length; index++)
                              Padding(
                                padding: EdgeInsets.only(
                                  right: index == days.length - 1
                                      ? 0
                                      : metrics.gap,
                                ),
                                child: _UsageBar(
                                  point: days[index],
                                  maxTokens: maxTokens,
                                  providers: providers,
                                  barWidth: metrics.width,
                                  chartHeight: 197,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            if (providers.isEmpty)
              Text('暂无模型调用记录', style: Theme.of(context).textTheme.bodyMedium)
            else
              for (final provider in providers)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: provider.color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      provider.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.appTextSecondary,
                        fontSize: 12,
                        height: 1,
                      ),
                    ),
                  ],
                ),
          ],
        ),
      ],
    );
  }

  _ProviderSeries _buildProviderSeries(
    List<rust_stats.ProviderTokenUsage> usage,
  ) {
    final totals = <String, int>{};
    for (final item in usage) {
      totals[item.providerName] =
          (totals[item.providerName] ?? 0) + item.tokens;
    }
    final sortedNames = totals.keys.toList()
      ..sort(
        (left, right) => (totals[right] ?? 0).compareTo(totals[left] ?? 0),
      );
    final topNames = sortedNames.take(8).toList();
    final colors = const [
      Color(0xFF2563EB),
      Color(0xFF0F9B8E),
      Color(0xFFF97316),
      Color(0xFF8B5CF6),
      Color(0xFFE11D48),
      Color(0xFF22A65F),
      Color(0xFFD08A00),
      Color(0xFF1598A7),
    ];
    final providers = [
      for (final (index, name) in topNames.indexed)
        _ProviderLegendItem(name: name, color: colors[index % colors.length]),
    ];
    if (sortedNames.length > topNames.length) {
      providers.add(
        const _ProviderLegendItem(name: '其他', color: Color(0xFF94A3B8)),
      );
    }
    return _ProviderSeries(providers);
  }

  List<_DailyUsagePoint> _buildUsageDays(
    rust_stats.StatsSnapshot snapshot,
    _ProviderSeries series,
  ) {
    final usageByDate = {
      for (final item in snapshot.tokenUsage) item.date: item,
    };
    final providerUsageByDate = <String, Map<String, int>>{};
    for (final item in snapshot.providerUsage) {
      final providerName = series.contains(item.providerName)
          ? item.providerName
          : '其他';
      final daily = providerUsageByDate.putIfAbsent(item.date, () => {});
      daily[providerName] = (daily[providerName] ?? 0) + item.tokens;
    }

    final dateStrings = <String>{
      ...usageByDate.keys,
      ...providerUsageByDate.keys,
    };
    if (widget.range.all && dateStrings.isNotEmpty) {
      final sortedDates =
          dateStrings.map(_parseDate).whereType<DateTime>().toList()..sort();
      return [
        for (final date in sortedDates)
          _DailyUsagePoint(
            date: date,
            usage: usageByDate[StatsService.formatDate(date)],
            providerTokens:
                providerUsageByDate[StatsService.formatDate(date)] ?? const {},
          ),
      ];
    }

    final days = <_DailyUsagePoint>[];
    for (
      var date = widget.range.start;
      !date.isAfter(widget.range.end);
      date = date.add(const Duration(days: 1))
    ) {
      final key = StatsService.formatDate(date);
      days.add(
        _DailyUsagePoint(
          date: date,
          usage: usageByDate[key],
          providerTokens: providerUsageByDate[key] ?? const {},
        ),
      );
    }
    return days;
  }

  DateTime? _parseDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !_controller.hasClients ||
        _controller.position.maxScrollExtent <= 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      if (resolvedEvent is! PointerScrollEvent || !_controller.hasClients) {
        return;
      }
      final maxScrollExtent = _controller.position.maxScrollExtent;
      if (maxScrollExtent <= 0) {
        return;
      }
      final delta = resolvedEvent.scrollDelta.dy != 0
          ? resolvedEvent.scrollDelta.dy
          : resolvedEvent.scrollDelta.dx;
      final next = (_controller.offset + delta)
          .clamp(0.0, maxScrollExtent)
          .toDouble();
      _controller.jumpTo(next);
    });
  }
}

class _ProviderSeries {
  const _ProviderSeries(this.providers);

  final List<_ProviderLegendItem> providers;

  bool contains(String provider) {
    return providers.any((item) => item.name == provider);
  }
}

class _UsageDayMetrics {
  const _UsageDayMetrics({required this.width, required this.gap});

  final double width;
  final double gap;
}

_UsageDayMetrics _usageDayMetrics(int totalDays) {
  if (totalDays >= 800) {
    return const _UsageDayMetrics(width: 4, gap: 4);
  }
  if (totalDays >= 365) {
    return const _UsageDayMetrics(width: 5, gap: 5);
  }
  if (totalDays >= 180) {
    return const _UsageDayMetrics(width: 7, gap: 6);
  }
  if (totalDays >= 90) {
    return const _UsageDayMetrics(width: 10, gap: 7);
  }
  return const _UsageDayMetrics(width: 14, gap: 8);
}

class _ProviderLegendItem {
  const _ProviderLegendItem({required this.name, required this.color});

  final String name;
  final Color color;
}

class _DailyUsagePoint {
  const _DailyUsagePoint({
    required this.date,
    required this.providerTokens,
    this.usage,
  });

  final DateTime date;
  final rust_stats.DailyTokenUsage? usage;
  final Map<String, int> providerTokens;

  int get totalTokens {
    final providerTotal = providerTokens.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    return providerTotal > 0 ? providerTotal : usage?.totalTokens ?? 0;
  }
}

class _UsageBar extends StatefulWidget {
  const _UsageBar({
    required this.point,
    required this.maxTokens,
    required this.providers,
    required this.barWidth,
    required this.chartHeight,
  });

  final _DailyUsagePoint point;
  final int maxTokens;
  final List<_ProviderLegendItem> providers;
  final double barWidth;
  final double chartHeight;

  @override
  State<_UsageBar> createState() => _UsageBarState();
}

class _UsageBarState extends State<_UsageBar> {
  final GlobalKey _barKey = GlobalKey();
  OverlayEntry? _tooltipOverlay;
  bool _hovered = false;

  @override
  void dispose() {
    _removeTooltipOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double barHeight = widget.point.totalTokens <= 0
        ? 0.0
        : (widget.point.totalTokens /
                  widget.maxTokens *
                  widget.chartHeight *
                  0.92)
              .clamp(10.0, widget.chartHeight * 0.92)
              .toDouble();
    final visibleBarWidth = math.max(widget.barWidth, 4.0);

    return MouseRegion(
      cursor: widget.point.totalTokens > 0
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) {
        if (widget.point.totalTokens <= 0) {
          return;
        }
        setState(() => _hovered = true);
        _showTooltipOverlay(barHeight);
      },
      onExit: (_) {
        setState(() => _hovered = false);
        _removeTooltipOverlay();
      },
      child: SizedBox(
        key: _barKey,
        width: widget.barWidth,
        height: widget.chartHeight,
        child: widget.point.totalTokens <= 0
            ? const SizedBox.shrink()
            : Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    bottom: -4,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      opacity: _hovered ? 1 : 0,
                      child: Container(
                        width: visibleBarWidth + 8,
                        height: barHeight + 8,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border: Border.all(
                            color: const Color(0xFF94A3B8),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: visibleBarWidth,
                    height: barHeight,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: _segments(),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showTooltipOverlay(double barHeight) {
    final barContext = _barKey.currentContext;
    final overlay = Overlay.of(context);
    if (barContext == null) {
      return;
    }
    final barBox = barContext.findRenderObject() as RenderBox?;
    if (barBox == null || !barBox.hasSize) {
      return;
    }

    final screenSize = MediaQuery.sizeOf(context);
    const tooltipWidth = 232.0;
    final tooltipHeight = _estimateTooltipHeight();
    final barTopCenter = barBox.localToGlobal(
      Offset(widget.barWidth / 2, widget.chartHeight - barHeight),
    );
    final left = (barTopCenter.dx - tooltipWidth / 2)
        .clamp(8.0, screenSize.width - tooltipWidth - 8.0)
        .toDouble();
    final top = (barTopCenter.dy - tooltipHeight - 12)
        .clamp(8.0, screenSize.height - tooltipHeight - 8.0)
        .toDouble();

    _removeTooltipOverlay();
    _tooltipOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: left,
          top: top,
          width: tooltipWidth,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: _UsageBarTooltip(
                point: widget.point,
                providers: widget.providers,
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_tooltipOverlay!);
  }

  double _estimateTooltipHeight() {
    final providerRows = _providerTooltipRows().length;
    final rowCount = providerRows > 0 ? providerRows : 3;
    return 72 + rowCount * 24;
  }

  void _removeTooltipOverlay() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
  }

  List<_UsageTooltipRow> _providerTooltipRows() {
    final rows = <_UsageTooltipRow>[];
    for (final provider in widget.providers) {
      final tokens = widget.point.providerTokens[provider.name] ?? 0;
      if (tokens <= 0) {
        continue;
      }
      rows.add(
        _UsageTooltipRow(
          label: provider.name,
          value: tokens,
          color: provider.color,
        ),
      );
    }
    rows.sort((left, right) => right.value.compareTo(left.value));
    return rows.take(5).toList();
  }

  List<Widget> _segments() {
    if (widget.providers.isEmpty || widget.point.providerTokens.isEmpty) {
      return [Expanded(child: Container(color: const Color(0xFFCBD5E1)))];
    }
    final total = widget.point.providerTokens.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    if (total <= 0) {
      return [];
    }
    final result = <Widget>[];
    for (final provider in widget.providers) {
      final tokens = widget.point.providerTokens[provider.name] ?? 0;
      if (tokens <= 0) {
        continue;
      }
      result.add(
        Expanded(
          flex: tokens,
          child: Container(color: provider.color),
        ),
      );
    }
    return result;
  }
}

class _UsageTooltipRow {
  const _UsageTooltipRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

class _UsageBarTooltip extends StatelessWidget {
  const _UsageBarTooltip({required this.point, required this.providers});

  final _DailyUsagePoint point;
  final List<_ProviderLegendItem> providers;

  @override
  Widget build(BuildContext context) {
    final usage = point.usage;
    final providerRows = _providerRows();
    final rows = providerRows.isNotEmpty
        ? providerRows
        : [
            _UsageTooltipRow(
              label: '输入 Tokens',
              value: usage?.inputTokens ?? 0,
              color: const Color(0xFF94A3B8),
            ),
            _UsageTooltipRow(
              label: '输出 Tokens',
              value: usage?.outputTokens ?? 0,
              color: const Color(0xFFA3A3A3),
            ),
            _UsageTooltipRow(
              label: '缓存 Tokens',
              value: usage?.cachedTokens ?? 0,
              color: const Color(0xFFCBD5E1),
            ),
          ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border.all(color: context.appBorder),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0x05000000).withValues(alpha: 0.22),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  StatsService.formatDate(point.date),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.appTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
              Text(
                '${_formatCompactNumber(point.totalTokens)} tokens',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.appTextTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: context.appBorder),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: row.color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      row.label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.appTextSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _formatCompactNumber(row.value),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.appTextTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<_UsageTooltipRow> _providerRows() {
    final rows = <_UsageTooltipRow>[];
    for (final provider in providers) {
      final tokens = point.providerTokens[provider.name] ?? 0;
      if (tokens <= 0) {
        continue;
      }
      rows.add(
        _UsageTooltipRow(
          label: provider.name,
          value: tokens,
          color: provider.color,
        ),
      );
    }
    rows.sort((left, right) => right.value.compareTo(left.value));
    return rows.take(5).toList();
  }
}

class _StatsCustomRangeDialog extends StatefulWidget {
  const _StatsCustomRangeDialog({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  @override
  State<_StatsCustomRangeDialog> createState() =>
      _StatsCustomRangeDialogState();
}

class _StatsCustomRangeDialogState extends State<_StatsCustomRangeDialog> {
  late DateTime _start = widget.start;
  late DateTime _end = widget.end;
  _StatsDateFieldRole? _activeDateField;

  Future<void> _pickStart() async {
    setState(() => _activeDateField = _StatsDateFieldRole.start);
    final result = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (context) => _StatsCalendarDialog(initialDate: _start),
    );
    if (!mounted) {
      return;
    }
    if (result == null) {
      setState(() => _activeDateField = null);
      return;
    }
    setState(() {
      _activeDateField = null;
      _start = result;
      if (_end.isBefore(_start)) {
        _end = _start;
      }
    });
  }

  Future<void> _pickEnd() async {
    setState(() => _activeDateField = _StatsDateFieldRole.end);
    final result = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (context) => _StatsCalendarDialog(initialDate: _end),
    );
    if (!mounted) {
      return;
    }
    if (result == null) {
      setState(() => _activeDateField = null);
      return;
    }
    setState(() {
      _activeDateField = null;
      _end = result;
      if (_start.isAfter(_end)) {
        _start = _end;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.appCardBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 540,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '自定义时间段',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                      height: 1,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _StatsDateField(
                      label: '开始',
                      date: _start,
                      active: _activeDateField == _StatsDateFieldRole.start,
                      onTap: _pickStart,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatsDateField(
                      label: '结束',
                      date: _end,
                      active: _activeDateField == _StatsDateFieldRole.end,
                      onTap: _pickEnd,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _StatsDialogButton(
                      label: '取消',
                      filled: false,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatsDialogButton(
                      label: '应用',
                      filled: true,
                      onTap: () => Navigator.of(context).pop(
                        _StatsDateRange(
                          start: _start,
                          end: _end,
                          label:
                              '${StatsService.formatDate(_start)} 至 ${StatsService.formatDate(_end)}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _StatsDateFieldRole { start, end }

class _StatsDateField extends StatefulWidget {
  const _StatsDateField({
    required this.label,
    required this.date,
    required this.active,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_StatsDateField> createState() => _StatsDateFieldState();
}

class _StatsDateFieldState extends State<_StatsDateField> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active || _hovered || _pressed;
    final overlayColor = _pressed
        ? context.appCardBgHover
        : (widget.active ? context.appCardBg : context.appCardBgHover);
    final labelColor = active
        ? context.appTextSecondary
        : context.appTextTertiary;
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
        child: SizedBox(
          height: 72,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.appCardBgHover,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  opacity: active ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: overlayColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: labelColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ) ??
                          TextStyle(
                            color: labelColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      StatsService.formatDate(widget.date),
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: context.appTextPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ) ??
                          TextStyle(
                            color: context.appTextPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsDialogButton extends StatefulWidget {
  const _StatsDialogButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  State<_StatsDialogButton> createState() => _StatsDialogButtonState();
}

class _StatsDialogButtonState extends State<_StatsDialogButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.filled
        ? (_pressed
              ? context.appTextSecondary
              : (_hovered
                    ? context.appTextPrimary.withValues(alpha: 0.88)
                    : context.appTextPrimary))
        : (_pressed
              ? context.appCardBgHover
              : (_hovered ? context.appCardBgHover : context.appCardBgHover));
    final foreground = widget.filled ? Colors.white : context.appTextPrimary;
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOutCubic,
            style:
                Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ) ??
                TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

class _StatsCalendarDialog extends StatefulWidget {
  const _StatsCalendarDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_StatsCalendarDialog> createState() => _StatsCalendarDialogState();
}

class _StatsCalendarDialogState extends State<_StatsCalendarDialog> {
  late final DateTime _selected = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
    widget.initialDate.day,
  );
  late DateTime _visibleMonth = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
  );

  @override
  Widget build(BuildContext context) {
    final dates = _visibleDates(_visibleMonth);
    return Dialog(
      backgroundColor: context.appCardBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 440,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _CalendarIconButton(
                    icon: Icons.chevron_left_rounded,
                    onTap: () => setState(
                      () => _visibleMonth = DateTime(
                        _visibleMonth.year,
                        _visibleMonth.month - 1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.appCardBgHover,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      '${_visibleMonth.year}-${_visibleMonth.month.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: context.appTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _CalendarIconButton(
                    icon: Icons.chevron_right_rounded,
                    onTap: () => setState(
                      () => _visibleMonth = DateTime(
                        _visibleMonth.year,
                        _visibleMonth.month + 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final label in const [
                    '周一',
                    '周二',
                    '周三',
                    '周四',
                    '周五',
                    '周六',
                    '周日',
                  ])
                    Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.appTextTertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: dates.length,
                itemBuilder: (context, index) {
                  final date = dates[index];
                  return _CalendarDateCell(
                    date: date,
                    selected: _sameDate(date, _selected),
                    muted: date.month != _visibleMonth.month,
                    onTap: () => Navigator.of(context).pop(date),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<DateTime> _visibleDates(DateTime month) {
    final firstDay = DateTime(month.year, month.month);
    final gridStart = firstDay.subtract(Duration(days: firstDay.weekday - 1));
    return List.generate(42, (index) => gridStart.add(Duration(days: index)));
  }

  bool _sameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class _CalendarIconButton extends StatefulWidget {
  const _CalendarIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_CalendarIconButton> createState() => _CalendarIconButtonState();
}

class _CalendarIconButtonState extends State<_CalendarIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _pressed;
    final backgroundColor = _pressed
        ? context.appCardBgHover
        : context.appCardBgHover;
    final iconColor = _pressed
        ? context.appTextPrimary
        : (_hovered ? context.appTextPrimary : context.appTextSecondary);
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
        child: SizedBox(
          width: 34,
          height: 34,
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
              Icon(widget.icon, size: 22, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarDateCell extends StatefulWidget {
  const _CalendarDateCell({
    required this.date,
    required this.selected,
    required this.muted,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool muted;
  final VoidCallback onTap;

  @override
  State<_CalendarDateCell> createState() => _CalendarDateCellState();
}

class _CalendarDateCellState extends State<_CalendarDateCell> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered || _pressed;
    final backgroundColor = widget.selected
        ? (_pressed
              ? context.appCardBgHover
              : (_hovered ? context.appCardBg : context.appCardBgHover))
        : (_pressed
              ? context.appCardBgHover
              : (_hovered ? context.appCardBgHover : Colors.transparent));
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
        child: Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    opacity: active ? 1 : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
                Text(
                  widget.date.day.toString(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: widget.muted
                        ? context.appTextTertiary
                        : (active
                              ? context.appTextPrimary
                              : context.appTextSecondary),
                    fontSize: 14,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    height: 1,
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

String _formatCompactNumber(int value) {
  if (value.abs() >= 1000000) {
    return '${_trimFixed(value / 1000000)}M';
  }
  if (value.abs() >= 1000) {
    return '${_trimFixed(value / 1000)}k';
  }
  return value.toString();
}

String _trimFixed(double value) {
  final fixed = value.toStringAsFixed(value >= 10 ? 0 : 1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}
