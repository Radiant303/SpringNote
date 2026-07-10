part of 'settings_page.dart';

class _StoragePanel extends StatefulWidget {
  const _StoragePanel({
    required this.localDataState,
    required this.cleanupService,
    required this.initialScan,
    required this.onScanChanged,
  });

  final LocalDataState localDataState;
  final NoteImageCleanupService cleanupService;
  final NoteImageCleanupScan? initialScan;
  final ValueChanged<NoteImageCleanupScan> onScanChanged;

  @override
  State<_StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends State<_StoragePanel> {
  late NoteImageCleanupScan? _scan;
  late bool _scanning;
  bool _cleaning = false;
  String? _message;
  bool _messageIsError = false;
  int _operationGeneration = 0;

  bool get _busy => _scanning || _cleaning;

  @override
  void initState() {
    super.initState();
    _scan = widget.initialScan;
    _scanning = _scan == null;
    if (_scanning) {
      unawaited(_loadScan(updateLoadingState: false));
    }
  }

  @override
  void didUpdateWidget(covariant _StoragePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.localDataState.dataDirectory !=
        oldWidget.localDataState.dataDirectory) {
      _operationGeneration++;
      _scan = widget.initialScan;
      _scanning = _scan == null;
      _cleaning = false;
      _message = null;
      _messageIsError = false;
      if (_scanning) {
        unawaited(_loadScan(updateLoadingState: false));
      }
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
        _messageIsError = false;
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
      widget.onScanChanged(scan);
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

    final selectedPaths = await showDialog<List<String>>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (context) => _UnusedImagesConfirmDialog(
        scan: scan,
        dataDirectory: widget.localDataState.dataDirectory,
      ),
    );
    if (!mounted || selectedPaths == null || selectedPaths.isEmpty) {
      return;
    }

    final generation = ++_operationGeneration;
    setState(() {
      _cleaning = true;
      _message = null;
      _messageIsError = false;
    });
    try {
      final result = await widget.cleanupService.deleteUnusedImages(
        localDataState: widget.localDataState,
        candidateRelativePaths: selectedPaths,
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
      widget.onScanChanged(refreshed);
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

  String _statusText() {
    if (_cleaning) {
      return '正在清理';
    }
    if (_message case final message?) {
      return message;
    }
    return _scanning ? '正在扫描' : '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final scan = _scan;
    final canClean = !_busy && scan != null && scan.unusedImages.isNotEmpty;
    final statusText = _statusText();
    final referencedSize = scan == null
        ? 0
        : (scan.totalSizeBytes - scan.unusedSizeBytes).clamp(
            0,
            scan.totalSizeBytes,
          );

    return _SettingsScrollFrame(
      maxWidth: 820,
      children: [
        _SettingsCard(
          title: '图片附件',
          trailing: _StorageActionButton(
            key: const ValueKey('storage-rescan-button'),
            label: '重新扫描',
            width: 96,
            enabled: !_busy,
            onTap: _loadScan,
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (scan == null)
                    _StorageScanState(scanning: _scanning)
                  else
                    _StorageOverview(
                      totalCount: scan.totalImageCount,
                      totalSize: scan.totalSizeBytes,
                      referencedCount: scan.referencedImageCount,
                      referencedSize: referencedSize,
                      unusedCount: scan.unusedImageCount,
                      unusedSize: scan.unusedSizeBytes,
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (statusText.isEmpty)
                        const Spacer()
                      else
                        Expanded(
                          child: Text(
                            statusText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: _messageIsError
                                      ? Theme.of(context).colorScheme.error
                                      : colors.textSubtle,
                                  height: 1.35,
                                ),
                          ),
                        ),
                      const SizedBox(width: 18),
                      _StorageActionButton(
                        key: const ValueKey('storage-clean-button'),
                        label: '清理图片',
                        width: 108,
                        filled: true,
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

class _StorageScanState extends StatelessWidget {
  const _StorageScanState({required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 98),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.image_search_outlined, size: 21, color: colors.textSubtle),
          const SizedBox(width: 11),
          Text(
            scanning ? '正在扫描' : '暂无统计信息',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSubtle),
          ),
        ],
      ),
    );
  }
}

class _StorageOverview extends StatelessWidget {
  const _StorageOverview({
    required this.totalCount,
    required this.totalSize,
    required this.referencedCount,
    required this.referencedSize,
    required this.unusedCount,
    required this.unusedSize,
  });

  final int totalCount;
  final int totalSize;
  final int referencedCount;
  final int referencedSize;
  final int unusedCount;
  final int unusedSize;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _StorageMetric(
        label: '全部图片',
        value: totalCount.toString(),
        detail: _formatStorageBytes(totalSize),
        icon: _SettingsNavIconType.image,
        iconKey: const ValueKey('storage-total-image-icon'),
        valueKey: const ValueKey('storage-total-image-count'),
      ),
      _StorageMetric(
        label: '仍在使用',
        value: referencedCount.toString(),
        detail: _formatStorageBytes(referencedSize),
        icon: _SettingsNavIconType.layers,
        iconKey: const ValueKey('storage-referenced-image-icon'),
        valueKey: const ValueKey('storage-referenced-image-count'),
      ),
      _StorageMetric(
        label: '可以清理',
        value: unusedCount.toString(),
        detail: _formatStorageBytes(unusedSize),
        icon: _SettingsNavIconType.trash,
        iconKey: const ValueKey('storage-unused-image-icon'),
        valueKey: const ValueKey('storage-unused-image-count'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                metrics[index],
                if (index != metrics.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < metrics.length; index++) ...[
              Expanded(child: metrics[index]),
              if (index != metrics.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _StorageMetric extends StatelessWidget {
  const _StorageMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.iconKey,
    required this.valueKey,
  });

  final String label;
  final String value;
  final String detail;
  final _SettingsNavIconType icon;
  final Key iconKey;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      height: 72,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: colors.surfaceHover,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          _SettingsNavLucideIcon(
            key: iconKey,
            type: icon,
            size: 20,
            color: colors.textSubtle,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      key: valueKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: colors.text,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.textSubtle,
                                fontSize: 11,
                                height: 1,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSubtle,
                    fontSize: 11,
                    height: 1,
                  ),
                ),
              ],
            ),
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
  });

  final String label;
  final double width;
  final bool enabled;
  final bool filled;
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
        : widget.filled
        ? colors.text
        : colors.surfaceMuted;
    final background = active
        ? Color.lerp(baseBackground, colors.surface, _pressed ? 0.18 : 0.10)!
        : baseBackground;
    final foreground = !widget.enabled
        ? colors.textSubtle.withValues(alpha: 0.68)
        : widget.filled
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
              color: widget.filled ? Colors.transparent : colors.border,
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Center(
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
        ),
      ),
    );
  }
}

class _UnusedImagesConfirmDialog extends StatefulWidget {
  const _UnusedImagesConfirmDialog({
    required this.scan,
    required this.dataDirectory,
  });

  final NoteImageCleanupScan scan;
  final String dataDirectory;

  @override
  State<_UnusedImagesConfirmDialog> createState() =>
      _UnusedImagesConfirmDialogState();
}

class _UnusedImagesConfirmDialogState
    extends State<_UnusedImagesConfirmDialog> {
  late final ScrollController _scrollController = ScrollController();
  late final Set<String> _selectedPaths = widget.scan.unusedImages
      .map((image) => image.relativePath)
      .toSet();
  late String _previewPath = widget.scan.unusedImages.first.relativePath;
  String? _hoveredImagePath;
  bool _submitting = false;

  bool get _allSelected =>
      _selectedPaths.length == widget.scan.unusedImages.length;

  NoteImageCleanupEntry get _previewImage =>
      widget.scan.unusedImages.firstWhere(
        (image) => image.relativePath == _previewPath,
        orElse: () => widget.scan.unusedImages.first,
      );

  int get _selectedSize => widget.scan.unusedImages
      .where((image) => _selectedPaths.contains(image.relativePath))
      .fold(0, (total, image) => total + image.sizeBytes);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selectedPaths.clear();
      } else {
        _selectedPaths.addAll(
          widget.scan.unusedImages.map((image) => image.relativePath),
        );
      }
    });
  }

  void _setSelected(String path, bool selected) {
    setState(() {
      if (selected) {
        _selectedPaths.add(path);
      } else {
        _selectedPaths.remove(path);
      }
    });
  }

  void _setHoveredImage(String path, bool hovered) {
    setState(() {
      if (hovered) {
        _hoveredImagePath = path;
      } else if (_hoveredImagePath == path) {
        _hoveredImagePath = null;
      }
    });
  }

  void _confirm() {
    if (_submitting || _selectedPaths.isEmpty) {
      return;
    }
    _submitting = true;
    Navigator.of(context).pop([
      for (final image in widget.scan.unusedImages)
        if (_selectedPaths.contains(image.relativePath)) image.relativePath,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final previewImage = _previewImage;
    return Dialog(
      backgroundColor: AppTheme.dialogSurface(context),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 860,
        height: 590,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 17, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '清理图片',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.text,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.divider),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 370,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 12, 9),
                          child: Row(
                            children: [
                              Text(
                                '未使用 ${widget.scan.unusedImageCount}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: colors.text),
                              ),
                              const Spacer(),
                              _StorageTextButton(
                                label: _allSelected ? '取消全选' : '全选',
                                onTap: _toggleAll,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Scrollbar(
                            key: const ValueKey(
                              'storage-unused-images-scrollbar',
                            ),
                            controller: _scrollController,
                            interactive: true,
                            child: ListView.separated(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                              itemCount: widget.scan.unusedImages.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final image = widget.scan.unusedImages[index];
                                return _UnusedImageRow(
                                  key: ValueKey(
                                    'storage-image-row-${image.relativePath}',
                                  ),
                                  image: image,
                                  dataDirectory: widget.dataDirectory,
                                  selected: _selectedPaths.contains(
                                    image.relativePath,
                                  ),
                                  previewed: image.relativePath == _previewPath,
                                  hovered:
                                      image.relativePath == _hoveredImagePath,
                                  onHoverChanged: (hovered) => _setHoveredImage(
                                    image.relativePath,
                                    hovered,
                                  ),
                                  onPreview: () => setState(
                                    () => _previewPath = image.relativePath,
                                  ),
                                  onSelected: (selected) => _setSelected(
                                    image.relativePath,
                                    selected,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: colors.divider,
                  ),
                  Expanded(
                    child: _StoragePreviewPane(
                      image: previewImage,
                      dataDirectory: widget.dataDirectory,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 17),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.divider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已选 ${_selectedPaths.length} · '
                      '${_formatStorageBytes(_selectedSize)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSubtle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _StorageActionButton(
                    label: '取消',
                    width: 82,
                    enabled: !_submitting,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  _StorageActionButton(
                    key: const ValueKey('storage-confirm-clean-button'),
                    label: '确认删除',
                    width: 104,
                    enabled: !_submitting && _selectedPaths.isNotEmpty,
                    filled: true,
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

class _StorageTextButton extends StatefulWidget {
  const _StorageTextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_StorageTextButton> createState() => _StorageTextButtonState();
}

class _StorageTextButtonState extends State<_StorageTextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.text,
              fontSize: 12.5,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _UnusedImageRow extends StatelessWidget {
  const _UnusedImageRow({
    super.key,
    required this.image,
    required this.dataDirectory,
    required this.selected,
    required this.previewed,
    required this.hovered,
    required this.onHoverChanged,
    required this.onPreview,
    required this.onSelected,
  });

  final NoteImageCleanupEntry image;
  final String dataDirectory;
  final bool selected;
  final bool previewed;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onPreview;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final active = previewed || hovered;
    final background = previewed ? colors.surfacePressed : colors.surfaceHover;
    final file = _storageImageFile(dataDirectory, image.relativePath);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPreview,
        child: SizedBox(
          height: 62,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  opacity: active ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
                  child: Row(
                    children: [
                      Checkbox(
                        key: ValueKey(
                          'storage-image-select-${image.relativePath}',
                        ),
                        value: selected,
                        onChanged: (value) => onSelected(value ?? false),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                        side: BorderSide(
                          color: colors.textSubtle.withValues(alpha: 0.72),
                          width: 1.4,
                        ),
                        checkColor: colors.onAccent,
                        fillColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return colors.text;
                          }
                          return colors.surface;
                        }),
                        overlayColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                      ),
                      const SizedBox(width: 3),
                      RepaintBoundary(
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: colors.surfaceMuted,
                            border: Border.all(color: colors.border),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _StorageLocalImage(
                            file: file,
                            thumbnail: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              image.relativePath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: colors.text, height: 1.2),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatStorageBytes(image.sizeBytes),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colors.textSubtle,
                                    fontSize: 11.5,
                                    height: 1.1,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _StoragePreviewPane extends StatelessWidget {
  const _StoragePreviewPane({required this.image, required this.dataDirectory});

  final NoteImageCleanupEntry image;
  final String dataDirectory;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final displayPath = 'images/${image.relativePath}';
    final file = _storageImageFile(dataDirectory, image.relativePath);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 13, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '预览',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.text),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              key: const ValueKey('storage-image-preview'),
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _StorageLocalImage(file: file, thumbnail: false),
              ),
            ),
          ),
          const SizedBox(height: 11),
          Text(
            displayPath,
            key: const ValueKey('storage-image-preview-path'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.text, height: 1.2),
          ),
          const SizedBox(height: 5),
          Text(
            _formatStorageBytes(image.sizeBytes),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSubtle,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageLocalImage extends StatelessWidget {
  const _StorageLocalImage({required this.file, required this.thumbnail});

  final File? file;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    final file = this.file;
    if (file == null) {
      return _StorageImageFallback(thumbnail: thumbnail);
    }
    if (file.path.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(
        file,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => _StorageImageFallback(thumbnail: thumbnail),
        errorBuilder: (_, _, _) => _StorageImageFallback(thumbnail: thumbnail),
      );
    }
    return Image.file(
      file,
      fit: BoxFit.contain,
      cacheWidth: thumbnail ? 96 : 1400,
      filterQuality: thumbnail ? FilterQuality.low : FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _StorageImageFallback(thumbnail: thumbnail),
    );
  }
}

class _StorageImageFallback extends StatelessWidget {
  const _StorageImageFallback({required this.thumbnail});

  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    if (thumbnail) {
      return Center(
        child: Icon(Icons.image_outlined, size: 18, color: colors.textSubtle),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 30, color: colors.textSubtle),
          const SizedBox(height: 8),
          Text(
            '无法预览这张图片',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSubtle),
          ),
        ],
      ),
    );
  }
}

File? _storageImageFile(String dataDirectory, String relativePath) {
  final root = dataDirectory.trim();
  final normalized = relativePath.trim().replaceAll('\\', '/');
  if (root.isEmpty || normalized.isEmpty || normalized.startsWith('/')) {
    return null;
  }
  final parts = normalized.split('/');
  if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    return null;
  }

  var path = root;
  for (final part in ['notes', 'images', ...parts]) {
    path = _joinStoragePath(path, part);
  }
  return File(path);
}

String _joinStoragePath(String left, String right) {
  if (left.endsWith('/') || left.endsWith('\\')) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
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
