import 'package:flutter/material.dart';

import '../../core/models/local_data_state.dart';
import '../../core/models/structured_work_note.dart';
import '../../core/services/daily_note_service.dart';
import '../../core/services/mock_ai_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_scaffold.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.localDataState,
    this.mockAiService = const MockAiService(),
    this.dailyNoteService = const DailyNoteService(),
  });

  final LocalDataState localDataState;
  final MockAiService mockAiService;
  final DailyNoteService dailyNoteService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  StructuredWorkNote _overview = const StructuredWorkNote(
    rawInput: '',
    completed: [],
    issues: [],
    plans: [],
  );
  bool _isSubmitting = false;
  String? _lastSavedPath;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final structured = widget.mockAiService.structureWorkNote(input);
      final savedPath = await widget.dailyNoteService.mergeStructuredNote(
        dailyNotesDirectory: widget.localDataState.dailyNotesDirectory,
        date: DateTime.now(),
        note: structured,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _overview = _mergeOverview(_overview, structured);
        _lastSavedPath = savedPath;
        _controller.clear();
      });
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
          const _TodayHeroCard(),
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
        ],
      ),
    );
  }
}

class _TodayHeroCard extends StatelessWidget {
  const _TodayHeroCard();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(30),
      borderRadius: 26,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 820;

          if (narrow) {
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IncomeSummary(),
                SizedBox(height: 28),
                _ActivityPreview(),
              ],
            );
          }

          return const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _IncomeSummary()),
              SizedBox(width: 36),
              SizedBox(
                height: 118,
                child: VerticalDivider(color: Color(0xFFF1F5F9)),
              ),
              SizedBox(width: 36),
              Expanded(child: _ActivityPreview()),
            ],
          );
        },
      ),
    );
  }
}

class _IncomeSummary extends StatelessWidget {
  const _IncomeSummary();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 74,
          height: 74,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: 0.75,
                strokeWidth: 5,
                backgroundColor: const Color(0xFFEFF6FF),
                color: const Color(0xFF3B82F6),
              ),
              Text(
                '75%',
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
              'LEVEL 04',
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
                  '128',
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
                      '+0.12 c/s',
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
              '累计总收益 14,250 coins',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ],
    );
  }
}

class _ActivityPreview extends StatelessWidget {
  const _ActivityPreview();

  static const _colors = [
    Color(0xFFF1F5F9),
    Color(0xFFDCFCE7),
    Color(0xFFBBF7D0),
    Color(0xFF86EFAC),
    Color(0xFF4ADE80),
  ];

  @override
  Widget build(BuildContext context) {
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
            final color = _colors[_activityLevel(index)];
            return _HeatCell(color: color);
          }),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 22,
          runSpacing: 8,
          children: [
            _ActivityMetric(label: '本周新增', value: '0 篇'),
            _ActivityMetric(label: '连续记录', value: '0 天'),
            _ActivityMetric(label: '上次同步', value: '刚刚'),
          ],
        ),
      ],
    );
  }

  int _activityLevel(int index) {
    if (index % 29 == 0) {
      return 4;
    }
    if (index % 13 == 0) {
      return 3;
    }
    if (index % 7 == 0) {
      return 2;
    }
    if (index % 5 == 0) {
      return 1;
    }
    return 0;
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
