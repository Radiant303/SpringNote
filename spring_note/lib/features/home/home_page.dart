import 'package:flutter/material.dart';

import '../../core/models/local_data_state.dart';
import '../../core/models/structured_work_note.dart';
import '../../core/services/ai_client_service.dart';
import '../../core/services/daily_note_service.dart';
import '../../core/services/desktop_widget_controller.dart';
import '../../core/services/home_overview_service.dart';
import '../../core/services/level_progress_controller.dart';
import '../../core/services/mock_ai_service.dart';
import '../../core/services/stats_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../src/rust/stats.dart' as rust_stats;

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.localDataState,
    this.mockAiService = const MockAiService(),
    this.dailyNoteService = const DailyNoteService(),
    this.homeOverviewService = const HomeOverviewService(),
    this.aiClientService = const AiClientService(),
    this.statsService = const StatsService(),
    this.desktopWidgetController,
    this.levelProgressController,
  });

  final LocalDataState localDataState;
  final MockAiService mockAiService;
  final DailyNoteService dailyNoteService;
  final HomeOverviewService homeOverviewService;
  final AiClientService aiClientService;
  final StatsService statsService;
  final DesktopWidgetController? desktopWidgetController;
  final LevelProgressController? levelProgressController;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  DesktopWidgetController? _ownedDesktopWidgetController;
  LevelProgressController? _ownedLevelProgressController;

  StructuredWorkNote _overview = const StructuredWorkNote(
    rawInput: '',
    completed: [],
    issues: [],
    plans: [],
  );
  bool _isSubmitting = false;
  String? _lastSavedPath;
  String? _aiNotice;
  rust_stats.StatsSnapshot _todayStats = StatsService.emptySnapshot;
  rust_stats.StatsSnapshot _activityStats = StatsService.emptySnapshot;

  DesktopWidgetController get _desktopWidgetController =>
      widget.desktopWidgetController ?? _ownedDesktopWidgetController!;
  LevelProgressController get _levelProgressController =>
      widget.levelProgressController ?? _ownedLevelProgressController!;

  @override
  void initState() {
    super.initState();
    _ensureDesktopWidgetController();
    _ensureLevelProgressController();
    _desktopWidgetController.addListener(_handleDesktopWidgetChanged);
    _levelProgressController.addListener(_handleLevelProgressChanged);
    _loadTodayOverview();
    _loadHomeStats();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.desktopWidgetController != oldWidget.desktopWidgetController) {
      final oldController =
          oldWidget.desktopWidgetController ?? _ownedDesktopWidgetController;
      oldController?.removeListener(_handleDesktopWidgetChanged);
      _ensureDesktopWidgetController();
      _desktopWidgetController.addListener(_handleDesktopWidgetChanged);
    }
    if (widget.levelProgressController != oldWidget.levelProgressController) {
      final oldController =
          oldWidget.levelProgressController ?? _ownedLevelProgressController;
      oldController?.removeListener(_handleLevelProgressChanged);
      _ensureLevelProgressController();
      _levelProgressController.addListener(_handleLevelProgressChanged);
    }
    if (widget.localDataState.dataDirectory !=
        oldWidget.localDataState.dataDirectory) {
      if (widget.desktopWidgetController == null) {
        _ownedDesktopWidgetController?.attach(widget.localDataState);
      }
      if (widget.levelProgressController == null) {
        _ownedLevelProgressController?.attach(widget.localDataState);
      }
      _loadTodayOverview();
      _loadHomeStats();
    }
  }

  @override
  void dispose() {
    _desktopWidgetController.removeListener(_handleDesktopWidgetChanged);
    _levelProgressController.removeListener(_handleLevelProgressChanged);
    _ownedDesktopWidgetController?.dispose();
    _ownedLevelProgressController?.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _ensureDesktopWidgetController() {
    if (widget.desktopWidgetController != null) {
      _ownedDesktopWidgetController?.dispose();
      _ownedDesktopWidgetController = null;
      return;
    }
    _ownedDesktopWidgetController ??= DesktopWidgetController()
      ..attach(widget.localDataState);
  }

  void _ensureLevelProgressController() {
    if (widget.levelProgressController != null) {
      _ownedLevelProgressController?.dispose();
      _ownedLevelProgressController = null;
      return;
    }
    _ownedLevelProgressController ??= LevelProgressController()
      ..attach(widget.localDataState);
  }

  void _handleDesktopWidgetChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleLevelProgressChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadTodayOverview() async {
    try {
      final overview = await widget.homeOverviewService.readOverview(
        appDataDir: widget.localDataState.dataDirectory,
        date: DateTime.now(),
      );
      if (mounted) {
        setState(() => _overview = overview);
      }
    } catch (_) {
      // Overview JSON is a UI cache; malformed or unavailable files should not
      // block daily note writing.
    }
  }

  Future<void> _loadHomeStats() async {
    final today = DateTime.now();
    final activityStart = today.subtract(const Duration(days: 97));
    final results = await Future.wait([
      widget.statsService.readSnapshot(
        localDataState: widget.localDataState,
        start: today,
        end: today,
      ),
      widget.statsService.readSnapshot(
        localDataState: widget.localDataState,
        start: activityStart,
        end: today,
      ),
    ]);
    if (mounted) {
      setState(() {
        _todayStats = results[0];
        _activityStats = results[1];
      });
    }
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final now = DateTime.now();
      final configuredModel = widget
          .localDataState
          .config
          .defaultModels['intelligentGenerationModel'];
      final hasConfiguredModel =
          configuredModel != null && configuredModel.trim().isNotEmpty;
      var aiFailed = false;

      StructuredWorkNote? aiStructured;
      try {
        aiStructured = await widget.aiClientService.generateStructuredNote(
          appDataDir: widget.localDataState.dataDirectory,
          config: widget.localDataState.config,
          input: input,
        );
      } catch (_) {
        aiFailed = true;
      }
      final structured =
          aiStructured ?? widget.mockAiService.structureWorkNote(input);

      String? aiMergedMarkdown;
      try {
        final existingMarkdown = await widget.dailyNoteService
            .readDailyMarkdown(
              dailyNotesDirectory: widget.localDataState.dailyNotesDirectory,
              date: now,
            );
        aiMergedMarkdown = await widget.aiClientService.mergeDailyMarkdown(
          appDataDir: widget.localDataState.dataDirectory,
          config: widget.localDataState.config,
          existingMarkdown: existingMarkdown,
          note: structured,
          date: now,
        );
      } catch (_) {
        aiFailed = true;
      }

      final savedPath = await widget.dailyNoteService.mergeStructuredNote(
        dailyNotesDirectory: widget.localDataState.dailyNotesDirectory,
        date: now,
        note: structured,
        mergedMarkdown: aiMergedMarkdown,
      );
      await widget.statsService.recordHomeGeneration(
        appDataDir: widget.localDataState.dataDirectory,
      );
      StructuredWorkNote nextOverview;
      try {
        nextOverview = await widget.homeOverviewService.mergeAndSaveOverview(
          appDataDir: widget.localDataState.dataDirectory,
          date: now,
          current: _overview,
          incoming: structured,
        );
      } catch (_) {
        nextOverview = _mergeOverview(_overview, structured);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _overview = nextOverview;
        _lastSavedPath = savedPath;
        _aiNotice = aiFailed || !hasConfiguredModel || aiMergedMarkdown == null
            ? '未配置可用模型或 AI 返回不可用，本次已使用本地 mock / 简单合并。'
            : null;
        _controller.clear();
      });
      await _levelProgressController.recordValidSubmission();
      await _loadHomeStats();
      _focusNode.requestFocus();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  StructuredWorkNote _mergeOverview(
    StructuredWorkNote current,
    StructuredWorkNote incoming,
  ) {
    return StructuredWorkNote(
      rawInput: incoming.rawInput,
      completed: [...incoming.completed, ...current.completed],
      issues: [...incoming.issues, ...current.issues],
      plans: [...incoming.plans, ...current.plans],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SpringNotePageScaffold(
      title: '首页',
      actions: [
        IconButton(
          tooltip: '更多',
          onPressed: () {},
          icon: const Icon(Icons.more_horiz_rounded),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
        children: [
          _TodayHeroCard(
            todayStats: _todayStats,
            activityStats: _activityStats,
            desktopWidgetState: _desktopWidgetController.state,
            coinRatePerSecond: _desktopWidgetController.coinRatePerSecond,
            levelProgressState: _levelProgressController.state,
          ),
          const SizedBox(height: 20),
          _QuickCaptureCard(
            controller: _controller,
            focusNode: _focusNode,
            isSubmitting: _isSubmitting,
            onSubmit: _submit,
          ),
          const SizedBox(height: 20),
          _OverviewGrid(overview: _overview),
          if (_lastSavedPath != null) ...[
            const SizedBox(height: 16),
            _SavedPathBanner(path: _lastSavedPath!),
          ],
          if (_aiNotice != null) ...[
            const SizedBox(height: 12),
            _AiNoticeBanner(message: _aiNotice!),
          ],
        ],
      ),
    );
  }
}

class _TodayHeroCard extends StatelessWidget {
  const _TodayHeroCard({
    required this.todayStats,
    required this.activityStats,
    required this.desktopWidgetState,
    required this.coinRatePerSecond,
    required this.levelProgressState,
  });

  final rust_stats.StatsSnapshot todayStats;
  final rust_stats.StatsSnapshot activityStats;
  final DesktopWidgetState desktopWidgetState;
  final double coinRatePerSecond;
  final LevelProgressState levelProgressState;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(30),
      borderRadius: 26,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 820;

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IncomeSummary(
                  stats: todayStats,
                  desktopWidgetState: desktopWidgetState,
                  coinRatePerSecond: coinRatePerSecond,
                  levelProgressState: levelProgressState,
                ),
                const SizedBox(height: 28),
                _ActivityPreview(stats: activityStats),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _IncomeSummary(
                  stats: todayStats,
                  desktopWidgetState: desktopWidgetState,
                  coinRatePerSecond: coinRatePerSecond,
                  levelProgressState: levelProgressState,
                ),
              ),
              const SizedBox(width: 36),
              const SizedBox(
                height: 118,
                child: VerticalDivider(color: Color(0xFFF1F5F9)),
              ),
              const SizedBox(width: 36),
              Expanded(child: _ActivityPreview(stats: activityStats)),
            ],
          );
        },
      ),
    );
  }
}

class _IncomeSummary extends StatelessWidget {
  const _IncomeSummary({
    required this.stats,
    required this.desktopWidgetState,
    required this.coinRatePerSecond,
    required this.levelProgressState,
  });

  final rust_stats.StatsSnapshot stats;
  final DesktopWidgetState desktopWidgetState;
  final double coinRatePerSecond;
  final LevelProgressState levelProgressState;

  @override
  Widget build(BuildContext context) {
    final progress = (levelProgressState.experiencePercent / 100).clamp(
      0.0,
      1.0,
    );
    final progressLabel = '${levelProgressState.experiencePercent}%';
    final coins = desktopWidgetState.coins;
    final rate = desktopWidgetState.running ? coinRatePerSecond : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 74,
          height: 74,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 5,
                backgroundColor: const Color(0xFFEFF6FF),
                color: const Color(0xFF3B82F6),
              ),
              Text(
                progressLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 28),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日收益', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'LEVEL ${levelProgressState.level.toString().padLeft(2, '0')} · EXP ${levelProgressState.experiencePercent}%',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF3B82F6),
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  coins.round().toString(),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                    height: 0.95,
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+${rate.toStringAsFixed(3)} c/s',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF059669),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatWorkDuration(desktopWidgetState.workSeconds)} · 今日有效 ${levelProgressState.todayValidSubmissions}/10 次',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ],
    );
  }

  String _formatWorkDuration(int seconds) {
    if (seconds <= 0) {
      return '尚未记录工作时长';
    }
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '已工作 ${hours}h ${minutes}m';
    }
    return '已工作 ${minutes}m';
  }
}

class _ActivityPreview extends StatelessWidget {
  const _ActivityPreview({required this.stats});

  final rust_stats.StatsSnapshot stats;

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
    final activityByDate = {
      for (final item in stats.activity) item.date: item.count,
    };
    final weekCount = List.generate(7, (index) {
      final date = today.subtract(Duration(days: 6 - index));
      return activityByDate[StatsService.formatDate(date)] ?? 0;
    }).fold<int>(0, (sum, count) => sum + count);
    final streak = _calculateStreak(today, activityByDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'ACTIVITY INPUT',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSubtle,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const Spacer(),
            Text(
              '最近活跃',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF10B981)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: List.generate(98, (index) {
            final date = today.subtract(Duration(days: 97 - index));
            final dateLabel = StatsService.formatDate(date);
            final count = activityByDate[dateLabel] ?? 0;
            final color = _colors[_activityLevel(count)];
            return Tooltip(
              message: '$dateLabel：$count 次记录',
              child: _HeatCell(color: color),
            );
          }),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 22,
          runSpacing: 8,
          children: [
            _ActivityMetric(label: '本周新增', value: '$weekCount 次'),
            _ActivityMetric(label: '连续记录', value: '$streak 天'),
            _ActivityMetric(label: '上次同步', value: '刚刚'),
          ],
        ),
      ],
    );
  }

  int _activityLevel(int count) {
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

  int _calculateStreak(DateTime today, Map<String, int> activityByDate) {
    var streak = 0;
    for (var index = 0; index < 366; index++) {
      final date = today.subtract(Duration(days: index));
      final count = activityByDate[StatsService.formatDate(date)] ?? 0;
      if (count <= 0) {
        break;
      }
      streak++;
    }
    return streak;
  }
}

class _ActivityMetric extends StatelessWidget {
  const _ActivityMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$label: ',
        children: [
          TextSpan(
            text: value,
            style: const TextStyle(
              color: AppTheme.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: const SizedBox(width: 12, height: 12),
    );
  }
}

class _QuickCaptureCard extends StatelessWidget {
  const _QuickCaptureCard({
    required this.controller,
    required this.focusNode,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      borderRadius: 22,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final characterCount = controller.text.characters.length;
          final canSubmit = controller.text.trim().isNotEmpty && !isSubmitting;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !isSubmitting,
                minLines: 3,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '写下你的想法，AI 将自动整理并生成结构化内容...',
                  filled: true,
                  fillColor: Color(0xFFF8FAFC),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFFF1F5F9)),
              Row(
                children: [
                  const _ToolIcon(icon: Icons.image_outlined, tooltip: '上传图片'),
                  const SizedBox(width: 6),
                  const _ToolIcon(
                    icon: Icons.attach_file_rounded,
                    tooltip: '添加文件',
                  ),
                  const SizedBox(width: 6),
                  const _ToolIcon(
                    icon: Icons.alternate_email_rounded,
                    tooltip: '提及',
                  ),
                  const Spacer(),
                  Text(
                    '$characterCount 字',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 14),
                  FilledButton.icon(
                    onPressed: canSubmit ? onSubmit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.text,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      disabledForegroundColor: AppTheme.textSubtle,
                      minimumSize: const Size(118, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome_rounded, size: 15),
                    label: Text(isSubmitting ? '整理中' : '智能生成'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: null,
        icon: Icon(icon),
        color: AppTheme.textSubtle,
        disabledColor: AppTheme.textSubtle,
        iconSize: 18,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFF8FAFC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.overview});

  final StructuredWorkNote overview;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _OverviewCard(
        eyebrow: 'Completed · 完成事项',
        title: '完成事项',
        accentColor: AppTheme.textSubtle,
        items: overview.completed,
        emptyText: '提交随手记录后显示完成事项',
      ),
      _OverviewCard(
        eyebrow: 'Issues · 问题记录',
        title: '问题记录',
        accentColor: const Color(0xFFF87171),
        items: overview.issues,
        emptyText: '提交随手记录后显示问题记录',
      ),
      _OverviewCard(
        eyebrow: 'Next Steps · 明日计划',
        title: '明日计划',
        accentColor: AppTheme.textSubtle,
        items: overview.plans,
        emptyText: '提交随手记录后显示明日计划',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;

        if (narrow) {
          return Column(
            children: cards
                .map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: card,
                  ),
                )
                .toList(),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 16),
            Expanded(child: cards[1]),
            const SizedBox(width: 16),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.eyebrow,
    required this.title,
    required this.accentColor,
    required this.items,
    required this.emptyText,
  });

  final String eyebrow;
  final String title;
  final Color accentColor;
  final List<String> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(3).toList();

    return SoftCard(
      padding: const EdgeInsets.all(26),
      borderRadius: 22,
      child: Column(
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
                      eyebrow,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (visibleItems.isEmpty)
                      Text(
                        emptyText,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else
                      for (final item in visibleItems)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text(
                            item,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: visibleItems.first == item
                                      ? AppTheme.text
                                      : AppTheme.textMuted,
                                ),
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Text(
                items.length.toString().padLeft(2, '0'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            visibleItems.length < items.length
                ? '还有 ${items.length - visibleItems.length} 条'
                : title,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSubtle),
          ),
        ],
      ),
    );
  }
}

class _SavedPathBanner extends StatelessWidget {
  const _SavedPathBanner({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        border: Border.all(color: const Color(0xFFD1FAE5)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: Color(0xFF059669),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '已写入当日日报：$path',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF047857)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiNoticeBanner extends StatelessWidget {
  const _AiNoticeBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xFFD97706),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }
}
