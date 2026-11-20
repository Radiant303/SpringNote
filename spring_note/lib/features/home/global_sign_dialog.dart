import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/models/global_sign_item.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';

/// 返回 null 表示 AI 不可用、已走本地兜底（弹窗关闭，首页展示提示）；
/// 否则返回刷新后的最新全局签列表，弹窗原地更新。
typedef GlobalSignConfirmCallback =
    Future<List<GlobalSignItem>?> Function(
      List<GlobalSignItem> editedItems,
      List<GlobalSignItem> doneItems,
      List<GlobalSignItem> cancelledItems,
    );

/// 彻底删除（不经过 AI、不写入日报），由主页负责落盘。
typedef GlobalSignDeleteCallback = Future<void> Function(GlobalSignItem item);

class GlobalSignDialog extends StatefulWidget {
  const GlobalSignDialog({
    super.key,
    required this.items,
    required this.onConfirm,
    required this.onDeleteItem,
  });

  final List<GlobalSignItem> items;
  final GlobalSignConfirmCallback onConfirm;
  final GlobalSignDeleteCallback onDeleteItem;

  @override
  State<GlobalSignDialog> createState() => _GlobalSignDialogState();
}

class _GlobalSignDialogState extends State<GlobalSignDialog> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _doneIds = {};
  final Set<String> _cancelledIds = {};
  late List<GlobalSignItem> _items;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _items = _sortedByLatest(widget.items);
    _rebuildControllers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _disposeControllers();
    super.dispose();
  }

  List<GlobalSignItem> _sortedByLatest(List<GlobalSignItem> items) {
    return List.of(items)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void _disposeControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }

  void _rebuildControllers() {
    _disposeControllers();
    for (final item in _items) {
      _controllers[item.id] = TextEditingController(text: item.content);
    }
  }

  bool get _hasChanges {
    if (_doneIds.isNotEmpty || _cancelledIds.isNotEmpty) {
      return true;
    }
    for (final item in _items) {
      if ((_controllers[item.id]?.text.trim() ?? '') != item.content) {
        return true;
      }
    }
    return false;
  }

  void _toggleDone(String id) {
    setState(() {
      if (!_doneIds.remove(id)) {
        _doneIds.add(id);
        _cancelledIds.remove(id);
      }
    });
  }

  void _toggleCancelled(String id) {
    setState(() {
      if (!_cancelledIds.remove(id)) {
        _cancelledIds.add(id);
        _doneIds.remove(id);
      }
    });
  }

  Future<void> _hardDelete(GlobalSignItem item) async {
    if (_confirming) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (context) => const _GlobalSignHardDeleteDialog(),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await widget.onDeleteItem(item);
    if (!mounted) {
      return;
    }
    setState(() {
      _doneIds.remove(item.id);
      _cancelledIds.remove(item.id);
      _controllers.remove(item.id)?.dispose();
      _items.removeWhere((entry) => entry.id == item.id);
    });
  }

  Future<void> _confirm() async {
    if (!_hasChanges || _confirming) {
      return;
    }
    setState(() => _confirming = true);
    final editedItems = [
      for (final item in _items)
        item.copyWith(
          content: _controllers[item.id]?.text.trim() ?? item.content,
        ),
    ];
    final doneItems = [
      for (final item in editedItems)
        if (_doneIds.contains(item.id)) item,
    ];
    final cancelledItems = [
      for (final item in editedItems)
        if (_cancelledIds.contains(item.id)) item,
    ];
    final refreshed = await widget.onConfirm(
      editedItems,
      doneItems,
      cancelledItems,
    );
    if (!mounted) {
      return;
    }
    if (refreshed == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _confirming = false;
      _items = _sortedByLatest(refreshed);
      _doneIds.clear();
      _cancelledIds.clear();
      _rebuildControllers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final dialogHeight = math.min(
      520.0,
      MediaQuery.sizeOf(context).height * 0.68,
    );

    return Dialog(
      key: const ValueKey('global-sign-dialog'),
      backgroundColor: AppTheme.dialogSurface(context),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 620,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n(context).homeGlobalSign,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colors.text,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: IconButton(
                      key: const ValueKey('global-sign-close'),
                      onPressed: _confirming
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.divider),
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Text(
                        l10n(context).homeEmptyHint,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSubtle,
                        ),
                      ),
                    )
                  : ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: Scrollbar(
                        controller: _scrollController,
                        interactive: true,
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
                          itemCount: _items.length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1, color: colors.divider),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return _GlobalSignItemRow(
                              key: ValueKey('global-sign-item-${item.id}'),
                              item: item,
                              controller: _controllers[item.id]!,
                              done: _doneIds.contains(item.id),
                              cancelled: _cancelledIds.contains(item.id),
                              enabled: !_confirming,
                              onToggleDone: () => _toggleDone(item.id),
                              onToggleCancelled: () =>
                                  _toggleCancelled(item.id),
                              onHardDelete: () => _hardDelete(item),
                              onChanged: (_) => setState(() {}),
                            );
                          },
                        ),
                      ),
                    ),
            ),
            Divider(height: 1, color: colors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _hasChanges
                          ? l10n(context).homeGlobalSignUnconfirmedChanges
                          : l10n(context).homeGlobalSignConfirmHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSubtle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _GlobalSignConfirmButton(
                    enabled: _hasChanges && !_confirming,
                    busy: _confirming,
                    onTap: _confirm,
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

class _GlobalSignItemRow extends StatelessWidget {
  const _GlobalSignItemRow({
    super.key,
    required this.item,
    required this.controller,
    required this.done,
    required this.cancelled,
    required this.enabled,
    required this.onToggleDone,
    required this.onToggleCancelled,
    required this.onHardDelete,
    required this.onChanged,
  });

  final GlobalSignItem item;
  final TextEditingController controller;
  final bool done;
  final bool cancelled;
  final bool enabled;
  final VoidCallback onToggleDone;
  final VoidCallback onToggleCancelled;
  final VoidCallback onHardDelete;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Opacity(
      opacity: cancelled ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    enabled: enabled && !cancelled,
                    onChanged: onChanged,
                    maxLines: null,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: done || cancelled
                          ? colors.textSubtle
                          : colors.text,
                      decoration: done ? TextDecoration.lineThrough : null,
                      height: 1.5,
                    ),
                    cursorColor: colors.textMuted,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      hoverColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatSignTime(item.updatedAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSubtle,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _GlobalSignItemAction(
              key: ValueKey('global-sign-done-${item.id}'),
              tooltip: done
                  ? l10n(context).homeGlobalSignTooltipUndoComplete
                  : l10n(context).homeGlobalSignTooltipComplete,
              icon: done
                  ? Icons.check_circle_rounded
                  : Icons.check_circle_outline_rounded,
              active: done,
              onTap: enabled ? onToggleDone : null,
            ),
            _GlobalSignItemAction(
              key: ValueKey('global-sign-cancel-${item.id}'),
              tooltip: cancelled
                  ? l10n(context).homeGlobalSignTooltipUndoCancel
                  : l10n(context).homeGlobalSignTooltipCancel,
              icon: cancelled ? Icons.undo_rounded : Icons.close_rounded,
              active: cancelled,
              onTap: enabled ? onToggleCancelled : null,
            ),
            _GlobalSignItemAction(
              key: ValueKey('global-sign-delete-${item.id}'),
              tooltip: l10n(context).homeGlobalSignTooltipDelete,
              icon: Icons.delete_outline_rounded,
              active: false,
              onTap: enabled ? onHardDelete : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalSignItemAction extends StatelessWidget {
  const _GlobalSignItemAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        size: 18,
        color: active ? colors.text : colors.textSubtle,
      ),
    );
  }
}

class _GlobalSignConfirmButton extends StatelessWidget {
  const _GlobalSignConfirmButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final background = enabled ? colors.text : colors.surfaceMuted;
    final foreground = enabled ? colors.surface : colors.textSubtle;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        key: const ValueKey('global-sign-confirm'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: AppTheme.continuousBoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              : Text(
                  l10n(context).actionConfirm,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

class _GlobalSignHardDeleteDialog extends StatelessWidget {
  const _GlobalSignHardDeleteDialog();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Dialog(
      key: const ValueKey('global-sign-hard-delete-dialog'),
      backgroundColor: AppTheme.dialogSurface(context),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 360,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n(context).homeGlobalSignDeleteConfirmTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n(context).homeGlobalSignDeleteConfirmMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _GlobalSignDialogButton(
                    key: const ValueKey('global-sign-hard-delete-cancel'),
                    label: l10n(context).actionCancel,
                    filled: false,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 10),
                  _GlobalSignDialogButton(
                    key: const ValueKey('global-sign-hard-delete-confirm'),
                    label: l10n(context).actionDelete,
                    filled: true,
                    onTap: () => Navigator.of(context).pop(true),
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

class _GlobalSignDialogButton extends StatelessWidget {
  const _GlobalSignDialogButton({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: AppTheme.continuousBoxDecoration(
            color: filled ? colors.text : Colors.transparent,
            border: Border.all(color: filled ? colors.text : colors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: filled ? colors.surface : colors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

String _formatSignTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
