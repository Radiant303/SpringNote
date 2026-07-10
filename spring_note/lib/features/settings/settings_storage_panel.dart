part of 'settings_page.dart';

class _StoragePanel extends StatefulWidget {
  const _StoragePanel({
    required this.localDataState,
    required this.cleanupService,
  });

  final LocalDataState localDataState;
  final NoteImageCleanupService cleanupService;

  @override
  State<_StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends State<_StoragePanel> {
  NoteImageCleanupScan? _scan;
  bool _scanning = true;
  bool _cleaning = false;
  String? _message;
  bool _messageIsError = false;
  int _operationGeneration = 0;

  bool get _busy => _scanning || _cleaning;

  @override
  void initState() {
    super.initState();
    unawaited(_loadScan(updateLoadingState: false));
  }

  @override
  void didUpdateWidget(covariant _StoragePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.localDataState.dataDirectory !=
        oldWidget.localDataState.dataDirectory) {
      setState(() {
        _scan = null;
        _scanning = true;
        _cleaning = false;
        _message = null;
      });
      unawaited(_loadScan(updateLoadingState: false));
    }
  }

  @override
  void dispose() {
    _operationGeneration++;
    super.dispose();
  }

  Future<void> _loadScan({bool updateLoadingState = true}) async {
    if (_busy && updateLoadingState) {
      return;
    }
    final generation = ++_operationGeneration;
    if (updateLoadingState) {
      setState(() {
        _scanning = true;
        _message = null;
      });
    }

    try {
      final scan = await widget.cleanupService.scan(widget.localDataState);
      if (!mounted || generation != _operationGeneration) {
        return;
      }
      setState(() {
        _scan = scan;
        _scanning = false;
        _message = null;
        _messageIsError = false;
      });
    } catch (error) {
      if (!mounted || generation != _operationGeneration) {
        return;
      }
      setState(() {
        _scanning = false;
        _message = '扫描失败：$error';
        _messageIsError = true;
      });
    }
  }

  Future<void> _cleanUnusedImages() async {
    final scan = _scan;
    if (_busy || scan == null || scan.unusedImages.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (context) => _UnusedImagesConfirmDialog(scan: scan),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    final generation = ++_operationGeneration;
    setState(() {
      _cleaning = true;
      _message = null;
    });
    try {
      final result = await widget.cleanupService.deleteUnusedImages(
        localDataState: widget.localDataState,
        candidateRelativePaths: scan.unusedImages.map(
          (image) => image.relativePath,
        ),
      );
      final refreshed = await widget.cleanupService.scan(widget.localDataState);
      if (!mounted || generation != _operationGeneration) {
        return;
      }
      setState(() {
        _scan = refreshed;
        _cleaning = false;
        _message = _cleanupMessage(result);
        _messageIsError = result.failedImages.isNotEmpty;
      });
    } catch (error) {
      if (!mounted || generation != _operationGeneration) {
        return;
      }
      setState(() {
        _cleaning = false;
        _message = '清理失败：$error';
        _messageIsError = true;
      });
    }
  }

  String _cleanupMessage(NoteImageCleanupDeleteResult result) {
    if (result.failedImages.isNotEmpty) {
      return '已清理 ${result.deletedCount} 张，'
          '${result.failedImages.length} 张删除失败。';
    }
    if (result.deletedCount == 0 && result.skippedCount > 0) {
      return '图片引用已发生变化，没有删除任何文件。';
    }
    if (result.skippedCount > 0) {
      return '已清理 ${result.deletedCount} 张图片，'
          '${result.skippedCount} 张因引用变化已保留。';
    }
    return '已清理 ${result.deletedCount} 张图片，释放 '
        '${_formatStorageBytes(result.deletedSizeBytes)}。';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final scan = _scan;
    final canClean = !_busy && scan != null && scan.unusedImages.isNotEmpty;
    final referencedSize = scan == null
        ? null
        : scan.totalSizeBytes - scan.unusedSizeBytes;

    return _SettingsScrollFrame(
      maxWidth: 900,
      children: [
        _SettingsCard(
          title: '图片附件',
          trailing: _StorageActionButton(
            key: const ValueKey('storage-rescan-button'),
            label: '重新扫描',
            width: 108,
            loading: _scanning,
            enabled: !_busy,
            onTap: _loadScan,
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '扫描日报、周报和月报中的图片引用，仅清理 notes/images 内未被引用的图片。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSubtle,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StorageMetricTile(
                          label: '全部图片',
                          value: scan?.totalImageCount.toString() ?? '—',
                          detail: scan == null
                              ? '正在读取'
                              : _formatStorageBytes(scan.totalSizeBytes),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StorageMetricTile(
                          label: '仍在使用',
                          value: scan?.referencedImageCount.toString() ?? '—',
                          detail: referencedSize == null
                              ? '正在检查'
                              : _formatStorageBytes(referencedSize),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StorageMetricTile(
                          label: '可以清理',
                          value: scan?.unusedImageCount.toString() ?? '—',
                          detail: scan == null
                              ? '正在检查'
                              : _formatStorageBytes(scan.unusedSizeBytes),
                          highlighted: (scan?.unusedImageCount ?? 0) > 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: AnimatedOpacity(
                              opacity: _message == null ? 0 : 1,
                              duration: const Duration(milliseconds: 160),
                              child: Text(
                                _message ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: _messageIsError
                                          ? const Color(0xFFEF4444)
                                          : colors.textSubtle,
                                      height: 1.35,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      _StorageActionButton(
                        key: const ValueKey('storage-clean-button'),
                        label: scan?.unusedImages.isEmpty ?? true
                            ? '无需清理'
                            : '清理未使用图片',
                        width: 144,
                        filled: true,
                        destructive: canClean,
                        loading: _cleaning,
                        enabled: canClean,
                        onTap: _cleanUnusedImages,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StorageMetricTile extends StatelessWidget {
  const _StorageMetricTile({
    required this.label,
    required this.value,
    required this.detail,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final String detail;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final highlight = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE58B7E)
        : const Color(0xFFD3604F);
    return Container(
      constraints: const BoxConstraints(minHeight: 102),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: highlighted
            ? highlight.withValues(alpha: 0.08)
            : colors.surfaceMuted,
        border: Border.all(
          color: highlighted
              ? highlight.withValues(alpha: 0.28)
              : colors.border,
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textSubtle,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: highlighted ? highlight : colors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSubtle,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StorageActionButton extends StatefulWidget {
  const _StorageActionButton({
    super.key,
    required this.label,
    required this.width,
    required this.enabled,
    required this.onTap,
    this.filled = false,
    this.destructive = false,
    this.loading = false,
  });

  final String label;
  final double width;
  final bool enabled;
  final bool filled;
  final bool destructive;
  final bool loading;
  final VoidCallback onTap;

  @override
  State<_StorageActionButton> createState() => _StorageActionButtonState();
}

class _StorageActionButtonState extends State<_StorageActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant _StorageActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && (_hovered || _pressed)) {
      _hovered = false;
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final active = widget.enabled && (_hovered || _pressed);
    final baseBackground = !widget.enabled
        ? colors.surfaceMuted
        : widget.destructive
        ? const Color(0xFFEF4444)
        : widget.filled
        ? colors.text
        : colors.surfaceMuted;
    final background = active
        ? Color.lerp(baseBackground, colors.surface, _pressed ? 0.18 : 0.10)!
        : baseBackground;
    final foreground = !widget.enabled
        ? colors.textSubtle.withValues(alpha: 0.68)
        : (widget.destructive || widget.filled)
        ? colors.onAccent
        : colors.text;

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) {
        if (widget.enabled) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapCancel: widget.enabled
            ? () => setState(() => _pressed = false)
            : null,
        onTapUp: widget.enabled
            ? (_) => setState(() => _pressed = false)
            : null,
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          width: widget.width,
          height: 38,
          decoration: BoxDecoration(
            color: background,
            border: Border.all(
              color: widget.filled || widget.destructive
                  ? Colors.transparent
                  : colors.border,
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: widget.loading ? 0 : 1,
                duration: const Duration(milliseconds: 120),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontSize: 13,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: widget.loading ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: TickerMode(
                  enabled: widget.loading,
                  child: SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: foreground,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnusedImagesConfirmDialog extends StatefulWidget {
  const _UnusedImagesConfirmDialog({required this.scan});

  final NoteImageCleanupScan scan;

  @override
  State<_UnusedImagesConfirmDialog> createState() =>
      _UnusedImagesConfirmDialogState();
}

class _UnusedImagesConfirmDialogState
    extends State<_UnusedImagesConfirmDialog> {
  late final ScrollController _scrollController = ScrollController();
  bool _submitting = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _close(bool confirmed) {
    if (_submitting) {
      return;
    }
    _submitting = true;
    Navigator.of(context).pop(confirmed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final listHeight = (widget.scan.unusedImages.length * 52.0)
        .clamp(72.0, 286.0)
        .toDouble();
    return Dialog(
      backgroundColor: AppTheme.dialogSurface(context),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '清理未使用图片',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colors.text,
                      fontSize: 18,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '将永久删除 ${widget.scan.unusedImageCount} 张图片，释放 '
                    '${_formatStorageBytes(widget.scan.unusedSizeBytes)}。'
                    '删除前会再次检查引用。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSubtle,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 26),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(15),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: listHeight,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: widget.scan.unusedImages.length > 5,
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    itemCount: widget.scan.unusedImages.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, thickness: 1, color: colors.divider),
                    itemBuilder: (context, index) {
                      final image = widget.scan.unusedImages[index];
                      return _UnusedImageRow(image: image);
                    },
                  ),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 20),
              padding: const EdgeInsets.fromLTRB(26, 15, 26, 19),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.divider)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _StorageActionButton(
                    label: '取消',
                    width: 88,
                    enabled: !_submitting,
                    onTap: () => _close(false),
                  ),
                  const SizedBox(width: 10),
                  _StorageActionButton(
                    key: const ValueKey('storage-confirm-clean-button'),
                    label: '确认清理',
                    width: 108,
                    enabled: !_submitting,
                    filled: true,
                    destructive: true,
                    onTap: () => _close(true),
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

class _UnusedImageRow extends StatelessWidget {
  const _UnusedImageRow({required this.image});

  final NoteImageCleanupEntry image;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final displayPath = 'images/${image.relativePath}';
    return SizedBox(
      height: 51,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.image_outlined, size: 18, color: colors.textSubtle),
            const SizedBox(width: 10),
            Expanded(
              child: Tooltip(
                message: displayPath,
                child: Text(
                  displayPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.text,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              _formatStorageBytes(image.sizeBytes),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSubtle,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatStorageBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
