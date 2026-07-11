import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/attachments/attachment_manager.dart';
import '../../core/attachments/pending_image.dart';

import '../../core/models/local_data_state.dart';
import '../../core/models/structured_work_note.dart';
import '../../core/services/ai_client_service.dart';
import '../../core/services/daily_note_service.dart';
import '../../core/services/desktop_widget_controller.dart';
import '../../core/services/home_overview_service.dart';
import '../../core/services/image_file_types.dart';
import '../../core/services/level_progress_controller.dart';
import '../../core/services/mock_ai_service.dart';
import '../../core/services/pending_image_clipboard_service.dart';
import '../../core/services/pending_image_service.dart';
import '../../core/services/stats_service.dart';
import '../../core/services/update_check_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/update_dialog.dart';
import '../../src/rust/stats.dart' as rust_stats;

typedef HomeAttachmentPicker = Future<List<HomeAttachment>> Function();
typedef HomeImagePicker = Future<List<PendingImage>> Function();

enum HomeAttachmentKind { image, document }

const int _maxHomeImageAttachments = maxAiImageInputs;
const int _maxHomeImageAttachmentBytes = maxAiImageInputBytes;

class HomeAttachment {
  const HomeAttachment({
    required this.path,
    required this.name,
    required this.kind,
  });

  final String path;
  final String name;
  final HomeAttachmentKind kind;

  HomeAttachment copyWith({
    String? path,
    String? name,
    HomeAttachmentKind? kind,
  }) {
    return HomeAttachment(
      path: path ?? this.path,
      name: name ?? this.name,
      kind: kind ?? this.kind,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.localDataState,
    this.mockAiService = const MockAiService(),
    this.dailyNoteService = const DailyNoteService(),
    this.homeOverviewService = const HomeOverviewService(),
    this.aiClientService = const AiClientService(),
    this.pendingImageClipboardService = const PendingImageClipboardService(),
    this.pendingImageService = const PendingImageService(),
    this.attachmentManager,
    this.statsService = const StatsService(),
    this.desktopWidgetController,
    this.levelProgressController,
    this.updateCheckResult = UpdateCheckResult.idle,
    this.updateCheckService,
    this.imageAttachmentPicker,
    this.documentAttachmentPicker,
    this.onDailyNoteSaved,
    this.startupCloudSyncMessage,
  });

  final LocalDataState localDataState;
  final MockAiService mockAiService;
  final DailyNoteService dailyNoteService;
  final HomeOverviewService homeOverviewService;
  final AiClientService aiClientService;
  final PendingImageClipboardService pendingImageClipboardService;
  final PendingImageService pendingImageService;
  final AttachmentManager? attachmentManager;
  final StatsService statsService;
  final DesktopWidgetController? desktopWidgetController;
  final LevelProgressController? levelProgressController;
  final UpdateCheckResult updateCheckResult;
  final UpdateCheckService? updateCheckService;
  final HomeImagePicker? imageAttachmentPicker;
  final HomeAttachmentPicker? documentAttachmentPicker;
  final ValueChanged<String>? onDailyNoteSaved;
  final String? startupCloudSyncMessage;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final AttachmentManager _attachmentManager;
  DesktopWidgetController? _ownedDesktopWidgetController;
  LevelProgressController? _ownedLevelProgressController;
  List<HomeAttachment> _attachments = const [];

  StructuredWorkNote _overview = const StructuredWorkNote(
    rawInput: '',
    completed: [],
    issues: [],
    plans: [],
  );
  bool _isSubmitting = false;
  bool _isPastingImages = false;
  String? _lastSavedPath;
  String? _aiNotice;
  String? _attachmentError;
  rust_stats.StatsSnapshot _activityStats = StatsService.emptySnapshot;

  DesktopWidgetController get _desktopWidgetController =>
      widget.desktopWidgetController ?? _ownedDesktopWidgetController!;
  LevelProgressController get _levelProgressController =>
      widget.levelProgressController ?? _ownedLevelProgressController!;

  @override
  void initState() {
    super.initState();
    _attachmentManager = widget.attachmentManager ?? AttachmentManager();
    _ensureDesktopWidgetController();
    _ensureLevelProgressController();
    _loadTodayOverview();
    _loadHomeStats();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.desktopWidgetController != oldWidget.desktopWidgetController) {
      _ensureDesktopWidgetController();
    }
    if (widget.levelProgressController != oldWidget.levelProgressController) {
      _ensureLevelProgressController();
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
    _ownedDesktopWidgetController?.dispose();
    _ownedLevelProgressController?.dispose();
    _attachmentManager.clear();
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
    final activityStart = today.subtract(const Duration(days: 139));
    final activityStats = await widget.statsService.readSnapshot(
      localDataState: widget.localDataState,
      start: activityStart,
      end: today,
    );
    if (mounted) {
      setState(() => _activityStats = activityStats);
    }
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if ((input.isEmpty &&
            _attachments.isEmpty &&
            !_attachmentManager.hasImages) ||
        _isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final now = DateTime.now();
      final notePath = widget.dailyNoteService.dailyNotePath(
        widget.localDataState.dailyNotesDirectory,
        now,
      );
      final savedPendingImages = await widget.pendingImageService
          .saveForDailyNote(
            notePath: notePath,
            images: _attachmentManager.images,
          );
      final modelSupportsImages = widget.aiClientService
          .supportsMultimodalImageInput(widget.localDataState.config);
      final aiImages = modelSupportsImages
          ? _attachmentManager.images
                .where(_canSendImageToAi)
                .map(
                  (image) => AiImageInput.fromBytes(
                    name: image.name,
                    bytes: image.bytes,
                    extension: image.extension,
                  ),
                )
                .toList()
          : const <AiImageInput>[];
      final submissionInput = _inputWithAttachmentSummary(
        input,
        savedPendingImages,
      );
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
          input: submissionInput,
          images: aiImages,
        );
      } catch (_) {
        aiFailed = true;
      }
      final structured =
          aiStructured ??
          widget.mockAiService.structureWorkNote(submissionInput);

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
      widget.onDailyNoteSaved?.call(savedPath);
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
            : savedPendingImages.isNotEmpty && !modelSupportsImages
            ? '当前智能生成模型未标记支持图像输入，图片已保存进日报但未发送给 AI。'
            : null;
        _controller.clear();
        _attachmentManager.clear();
        _attachments = const [];
        _attachmentError = null;
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

  String _inputWithAttachmentSummary(
    String input,
    List<SavedPendingImage> savedPendingImages,
  ) {
    final trimmed = input.trim();
    if (_attachments.isEmpty && savedPendingImages.isEmpty) {
      return trimmed;
    }

    final buffer = StringBuffer();
    if (trimmed.isNotEmpty) {
      buffer
        ..writeln(trimmed)
        ..writeln();
    }
    if (savedPendingImages.isNotEmpty) {
      buffer.writeln('图片：');
      for (final image in savedPendingImages) {
        buffer.writeln('![${image.name}](${image.markdownPath})');
      }
      if (_attachments.isNotEmpty) {
        buffer.writeln();
      }
    }
    if (_attachments.isNotEmpty) {
      buffer.writeln('附件：');
      for (final attachment in _attachments) {
        final type = switch (attachment.kind) {
          HomeAttachmentKind.image => '图片',
          HomeAttachmentKind.document => '文件',
        };
        buffer.writeln('- [$type] ${attachment.name}: ${attachment.path}');
      }
    }
    return buffer.toString().trimRight();
  }

  Future<void> _handlePasteShortcut() async {
    if (_isSubmitting || _isPastingImages) {
      return;
    }

    _isPastingImages = true;
    try {
      final images = await widget.pendingImageClipboardService
          .readPendingImages();
      if (!mounted) {
        return;
      }
      if (images.isNotEmpty) {
        setState(() {
          _attachmentError = _addPendingImages(images);
        });
        _focusNode.requestFocus();
        return;
      }
      await _pasteClipboardText();
    } catch (_) {
      if (mounted) {
        setState(() => _attachmentError = '无法读取剪贴板图片。');
      }
    } finally {
      _isPastingImages = false;
    }
  }

  Future<void> _pasteClipboardText() async {
    final ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      if (mounted) {
        setState(() => _attachmentError = '无法读取剪贴板文字。');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    _insertText(text);
    _focusNode.requestFocus();
  }

  void _insertText(String text) {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, text);
    final offset = start + text.length;
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  Future<void> _pickImageAttachments() async {
    if (_isSubmitting) {
      return;
    }

    try {
      final picked =
          await (widget.imageAttachmentPicker ?? _defaultImagePicker)();
      if (!mounted || picked.isEmpty) {
        return;
      }
      setState(() {
        _attachmentError = _addPendingImages(picked);
      });
    } catch (_) {
      if (mounted) {
        setState(() => _attachmentError = '无法添加图片，请重新选择文件。');
      }
    }
  }

  Future<void> _pickDocumentAttachments() {
    return _pickAttachments(
      widget.documentAttachmentPicker ?? _defaultDocumentAttachmentPicker,
    );
  }

  Future<void> _pickAttachments(HomeAttachmentPicker picker) async {
    if (_isSubmitting) {
      return;
    }

    try {
      final picked = await picker();
      if (!mounted || picked.isEmpty) {
        return;
      }
      final seenPaths = _attachments.map((item) => item.path).toSet();
      final nextAttachments = [..._attachments];
      for (final attachment in picked) {
        if (attachment.path.trim().isEmpty) {
          continue;
        }
        if (seenPaths.add(attachment.path)) {
          nextAttachments.add(attachment);
        }
      }
      setState(() {
        _attachments = nextAttachments;
        _attachmentError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _attachmentError = '无法添加附件，请重新选择文件。');
      }
    }
  }

  String? _addPendingImages(List<PendingImage> images) {
    var added = 0;
    var skippedForLimit = 0;
    final oversizedNames = <String>[];
    final unsupportedAiNames = <String>[];

    for (final image in images) {
      if (image.bytes.isEmpty) {
        continue;
      }
      if (image.bytes.length > _maxHomeImageAttachmentBytes) {
        oversizedNames.add(image.name);
        continue;
      }
      if (_attachmentManager.images.length >= _maxHomeImageAttachments) {
        skippedForLimit++;
        continue;
      }

      _attachmentManager.addImage(
        bytes: image.bytes,
        name: image.name,
        extension: image.extension,
      );
      added++;
      if (!_canSendImageToAi(image)) {
        unsupportedAiNames.add(image.name);
      }
    }

    final messages = <String>[];
    if (oversizedNames.isNotEmpty) {
      messages.add(
        '单张图片不能超过 ${_formatBytes(_maxHomeImageAttachmentBytes)}：'
        '${_formatNameList(oversizedNames)}。',
      );
    }
    if (skippedForLimit > 0) {
      messages.add(
        '最多添加 $_maxHomeImageAttachments 张图片，已忽略 $skippedForLimit 张。',
      );
    }
    if (unsupportedAiNames.isNotEmpty) {
      messages.add(
        '这些图片会保存进日报，但不会发送给 AI：'
        '${_formatNameList(unsupportedAiNames)}。',
      );
    }
    if (added == 0 && messages.isEmpty) {
      messages.add('没有可添加的图片。');
    }
    return messages.isEmpty ? null : messages.join('\n');
  }

  bool _canSendImageToAi(PendingImage image) {
    if (!isSupportedAiImageExtension(image.extension)) {
      return false;
    }
    final aiImage = AiImageInput.fromBytes(
      name: image.name,
      bytes: image.bytes,
      extension: image.extension,
    );
    return isSupportedAiImageInput(aiImage);
  }

  String _formatBytes(int bytes) {
    final megabytes = bytes / (1024 * 1024);
    if (megabytes == megabytes.roundToDouble()) {
      return '${megabytes.toInt()} MB';
    }
    return '${megabytes.toStringAsFixed(1)} MB';
  }

  String _formatNameList(List<String> names) {
    const maxNames = 3;
    final visible = names.take(maxNames).join('、');
    final remaining = names.length - maxNames;
    return remaining > 0 ? '$visible 等 $remaining 张' : visible;
  }

  Future<List<PendingImage>> _defaultImagePicker() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: [
            'png',
            'jpg',
            'jpeg',
            'gif',
            'webp',
            'heic',
            'bmp',
            'svg',
            'jfif',
          ],
          mimeTypes: ['image/*'],
          uniformTypeIdentifiers: ['public.image'],
          webWildCards: ['image/*'],
        ),
      ],
      confirmButtonText: '选择图片',
    );

    final images = <PendingImage>[];
    for (final file in files) {
      final name = _attachmentName(file);
      final extension =
          allowedImageExtension(name) ?? allowedImageExtension(file.path);
      if (extension == null) {
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        continue;
      }
      images.add(
        PendingImage(
          id: 'picked-image-${images.length}',
          bytes: bytes,
          name: name,
          extension: extension.replaceFirst('.', ''),
        ),
      );
    }
    return images;
  }

  Future<List<HomeAttachment>> _defaultDocumentAttachmentPicker() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Documents',
          extensions: [
            'pdf',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'ppt',
            'pptx',
            'txt',
            'md',
            'csv',
            'json',
            'rtf',
          ],
        ),
      ],
      confirmButtonText: '选择文件',
    );
    return files
        .map(
          (file) => HomeAttachment(
            path: file.path,
            name: _attachmentName(file),
            kind: HomeAttachmentKind.document,
          ),
        )
        .toList();
  }

  String _attachmentName(XFile file) {
    final name = file.name.trim();
    if (name.isNotEmpty) {
      return name;
    }
    return _fileName(file.path);
  }

  String _fileName(String path) {
    final name = p.basename(path).trim();
    return name.isEmpty ? path : name;
  }

  void _removeAttachment(HomeAttachment attachment) {
    setState(() {
      _attachments = _attachments
          .where((item) => item.path != attachment.path)
          .toList();
    });
  }

  void _removePendingImage(PendingImage image) {
    setState(() => _attachmentManager.removeImage(image.id));
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
    final colors = AppTheme.colors(context);
    return Material(
      color: colors.sidebar,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1184),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(48, 32, 48, 40),
            children: [
              Row(
                children: [
                  Text('首页', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  SpringNoteIconButton(
                    tooltip: '更多',
                    onPressed: () {},
                    icon: Icons.more_horiz,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _TodayHeroCard(
                activityStats: _activityStats,
                desktopWidgetController: _desktopWidgetController,
                levelProgressController: _levelProgressController,
              ),
              const SizedBox(height: 32),
              _QuickCaptureCard(
                controller: _controller,
                focusNode: _focusNode,
                isSubmitting: _isSubmitting,
                attachments: _attachments,
                pendingImages: _attachmentManager.images,
                attachmentError: _attachmentError,
                onPasteShortcut: () {
                  _handlePasteShortcut();
                },
                onPickImages: _pickImageAttachments,
                onPickDocuments: _pickDocumentAttachments,
                onRemoveAttachment: _removeAttachment,
                onRemovePendingImage: _removePendingImage,
                onSubmit: _submit,
              ),
              const SizedBox(height: 32),
              _OverviewGrid(overview: _overview),
              if (_lastSavedPath != null) ...[
                const SizedBox(height: 16),
                _SavedPathBanner(path: _lastSavedPath!),
              ],
              if (_aiNotice != null) ...[
                const SizedBox(height: 12),
                _AiNoticeBanner(message: _aiNotice!),
              ],
              if (widget.updateCheckResult.status !=
                  UpdateCheckStatus.idle) ...[
                const SizedBox(height: 12),
                _UpdateNoticeBanner(
                  result: widget.updateCheckResult,
                  updateCheckService: widget.updateCheckService,
                ),
              ],
              if (widget.startupCloudSyncMessage != null) ...[
                const SizedBox(height: 12),
                _CloudSyncIssueBanner(message: widget.startupCloudSyncMessage!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayHeroCard extends StatelessWidget {
  const _TodayHeroCard({
    required this.activityStats,
    required this.desktopWidgetController,
    required this.levelProgressController,
  });

  final rust_stats.StatsSnapshot activityStats;
  final DesktopWidgetController desktopWidgetController;
  final LevelProgressController levelProgressController;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SoftCard(
      padding: const EdgeInsets.all(32),
      borderRadius: 26,
      borderColor: dark ? null : const Color(0x99E0E0E0),
      boxShadow: dark
          ? null
          : const [
              BoxShadow(
                color: Color(0x05000000),
                blurRadius: 30,
                offset: Offset(0, 4),
              ),
              BoxShadow(
                color: Color(0x05000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 860;

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LiveIncomeSummary(
                  desktopWidgetController: desktopWidgetController,
                  levelProgressController: levelProgressController,
                  totalCoins: activityStats.summary.coins,
                ),
                const SizedBox(height: 28),
                _ActivityPreview(stats: activityStats, withDivider: false),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _LiveIncomeSummary(
                  desktopWidgetController: desktopWidgetController,
                  levelProgressController: levelProgressController,
                  totalCoins: activityStats.summary.coins,
                ),
              ),
              const SizedBox(width: 48),
              _ActivityPreview(stats: activityStats),
            ],
          );
        },
      ),
    );
  }
}

class _LiveIncomeSummary extends StatelessWidget {
  const _LiveIncomeSummary({
    required this.desktopWidgetController,
    required this.levelProgressController,
    required this.totalCoins,
  });

  final DesktopWidgetController desktopWidgetController;
  final LevelProgressController levelProgressController;
  final double totalCoins;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: desktopWidgetController,
      builder: (context, _) {
        return AnimatedBuilder(
          animation: levelProgressController,
          builder: (context, _) {
            return _IncomeSummary(
              desktopWidgetState: desktopWidgetController.state,
              coinRatePerSecond: desktopWidgetController.coinRatePerSecond,
              levelProgressState: levelProgressController.state,
              totalCoins: totalCoins,
            );
          },
        );
      },
    );
  }
}

class _IncomeSummary extends StatelessWidget {
  const _IncomeSummary({
    required this.desktopWidgetState,
    required this.coinRatePerSecond,
    required this.levelProgressState,
    required this.totalCoins,
  });

  final DesktopWidgetState desktopWidgetState;
  final double coinRatePerSecond;
  final LevelProgressState levelProgressState;
  final double totalCoins;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final progress = (levelProgressState.experiencePercent / 100).clamp(
      0.0,
      1.0,
    );
    final progressLabel = '${levelProgressState.experiencePercent}%';
    final coins = desktopWidgetState.coins;
    final rate = desktopWidgetState.running ? coinRatePerSecond : 0.0;
    final visibleTotalCoins = totalCoins > coins ? totalCoins : coins;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'LEVEL ${levelProgressState.level.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSubtle,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size.square(64),
                    painter: _LevelRingPainter(
                      progress: progress,
                      backgroundColor: colors.surfaceMuted,
                      progressColor: colors.textSubtle,
                    ),
                  ),
                  Text(
                    progressLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 48),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EARNINGS TODAY',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSubtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      coins.round().toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontSize: 56,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                            letterSpacing: -3.2,
                            height: 1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: dark
                          ? const Color(0xFF0B3024)
                          : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.trending_up_rounded,
                          size: 12,
                          color: dark
                              ? const Color(0xFF34D399)
                              : const Color(0xFF059669),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '+${_formatRate(rate)} c/s',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: dark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF059669),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  text: '累计总收益 ',
                  children: [
                    TextSpan(
                      text: _formatCoinAmount(visibleTotalCoins),
                      style: TextStyle(
                        color: colors.textSubtle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(text: ' coins'),
                  ],
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSubtle,
                  fontSize: 12,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatRate(double value) {
    return value.abs() < 1
        ? value.toStringAsFixed(2)
        : value.toStringAsFixed(3);
  }

  String _formatCoinAmount(double value) {
    final text = value.round().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < text.length; index++) {
      if (index > 0 && (text.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(text[index]);
    }
    return buffer.toString();
  }
}

class _LevelRingPainter extends CustomPainter {
  const _LevelRingPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
  });

  final double progress;
  final Color backgroundColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect.deflate(4),
      0,
      6.283185307179586,
      false,
      backgroundPaint,
    );
    canvas.drawArc(
      rect.deflate(4),
      -1.5707963267948966,
      6.283185307179586 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LevelRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.progressColor != progressColor;
  }
}

class _ActivityPreview extends StatelessWidget {
  const _ActivityPreview({required this.stats, this.withDivider = true});

  final rust_stats.StatsSnapshot stats;
  final bool withDivider;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final today = DateTime.now();
    final activityByDate = {
      for (final item in stats.activity) item.date: item.count,
    };
    final weekCount = List.generate(7, (index) {
      final date = today.subtract(Duration(days: 6 - index));
      return activityByDate[StatsService.formatDate(date)] ?? 0;
    }).fold<int>(0, (sum, count) => sum + count);
    final streak = _calculateStreak(today, activityByDate);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'ACTIVITY INPUT',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSubtle,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            Text(
              '最近活跃',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: dark ? const Color(0xFF34D399) : const Color(0xFF10B981),
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ActivityHeatmap(
          today: today,
          activityByDate: activityByDate,
          colors: AppTheme.activityHeatmapColors(context),
          activityLevel: _activityLevel,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActivityMetric(label: '本周总结', value: '$weekCount 次'),
                const SizedBox(width: 24),
                _ActivityMetric(label: '连续记录', value: '$streak 天'),
                const SizedBox(width: 24),
                _ActivityMetric(
                  label: '上次同步',
                  value: '刚刚',
                  valueColor: colors.textSubtle,
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (!withDivider) {
      return content;
    }

    return Container(
      width: 392,
      padding: const EdgeInsets.only(left: 32),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.divider)),
      ),
      child: content,
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
  const _ActivityMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Text.rich(
      TextSpan(
        text: '$label: ',
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              color: valueColor ?? colors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: colors.textSubtle, fontSize: 12),
    );
  }
}

class _ActivityHeatmap extends StatefulWidget {
  const _ActivityHeatmap({
    required this.today,
    required this.activityByDate,
    required this.colors,
    required this.activityLevel,
  });

  static const _dayCount = 140;
  static const _rowCount = 7;

  final DateTime today;
  final Map<String, int> activityByDate;
  final List<Color> colors;
  final int Function(int count) activityLevel;

  @override
  State<_ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<_ActivityHeatmap> {
  static const _cellSize = 13.0;
  static const _gap = 3.0;

  int? _hoveredDayIndex;

  double get _pitch => _cellSize + _gap;
  double get _heatmapHeight =>
      (_ActivityHeatmap._rowCount * _cellSize) +
      ((_ActivityHeatmap._rowCount - 1) * _gap);

  @override
  Widget build(BuildContext context) {
    final start = widget.today.subtract(
      const Duration(days: _ActivityHeatmap._dayCount - 1),
    );
    final columns = (_ActivityHeatmap._dayCount / _ActivityHeatmap._rowCount)
        .ceil();
    final width = (columns * _cellSize) + ((columns - 1) * _gap);

    return MouseRegion(
      cursor: _hoveredDayIndex == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onHover: (event) => _updateHoveredIndex(event.localPosition, columns),
      onExit: (_) => _clearHoveredIndex(),
      child: SizedBox(
        width: width,
        height: _heatmapHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(columns, (columnIndex) {
                return Padding(
                  padding: EdgeInsets.only(
                    right: columnIndex == columns - 1 ? 0 : _gap,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_ActivityHeatmap._rowCount, (
                      rowIndex,
                    ) {
                      final dayIndex =
                          columnIndex * _ActivityHeatmap._rowCount + rowIndex;
                      if (dayIndex >= _ActivityHeatmap._dayCount) {
                        return const SizedBox(
                          width: _cellSize,
                          height: _cellSize,
                        );
                      }
                      final date = start.add(Duration(days: dayIndex));
                      final dateLabel = StatsService.formatDate(date);
                      final count = widget.activityByDate[dateLabel] ?? 0;
                      final color = widget.colors[widget.activityLevel(count)];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: rowIndex == _ActivityHeatmap._rowCount - 1
                              ? 0
                              : _gap,
                        ),
                        child: _HeatCell(
                          color: color,
                          hovered: _hoveredDayIndex == dayIndex,
                          delay: Duration(milliseconds: 300 + dayIndex * 4),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
            if (_hoveredDayIndex != null)
              _buildTooltip(start, _hoveredDayIndex!),
          ],
        ),
      ),
    );
  }

  Widget _buildTooltip(DateTime start, int dayIndex) {
    final date = start.add(Duration(days: dayIndex));
    final dateLabel = StatsService.formatDate(date);
    final count = widget.activityByDate[dateLabel] ?? 0;
    final columnIndex = dayIndex ~/ _ActivityHeatmap._rowCount;
    final rowIndex = dayIndex % _ActivityHeatmap._rowCount;
    final cellLeft = columnIndex * _pitch;
    final cellTop = rowIndex * _pitch;

    return Positioned(
      left: cellLeft + (_cellSize / 2),
      bottom: _heatmapHeight - cellTop + 8,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: _HeatmapTooltip(count: count, dateLabel: dateLabel),
      ),
    );
  }

  void _updateHoveredIndex(Offset position, int columns) {
    final nextIndex = _hitTestDayIndex(position, columns);
    if (nextIndex == _hoveredDayIndex) {
      return;
    }
    setState(() => _hoveredDayIndex = nextIndex);
  }

  void _clearHoveredIndex() {
    if (_hoveredDayIndex == null) {
      return;
    }
    setState(() => _hoveredDayIndex = null);
  }

  int? _hitTestDayIndex(Offset position, int columns) {
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx > (columns * _cellSize) + ((columns - 1) * _gap) ||
        position.dy > _heatmapHeight) {
      return null;
    }

    final columnIndex = (position.dx / _pitch).floor();
    final rowIndex = (position.dy / _pitch).floor();
    if (columnIndex < 0 ||
        columnIndex >= columns ||
        rowIndex < 0 ||
        rowIndex >= _ActivityHeatmap._rowCount) {
      return null;
    }

    final dayIndex = columnIndex * _ActivityHeatmap._rowCount + rowIndex;
    if (dayIndex >= _ActivityHeatmap._dayCount) {
      return null;
    }
    return dayIndex;
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.color,
    required this.hovered,
    required this.delay,
  });

  final Color color;
  final bool hovered;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final delayMs = delay.inMilliseconds;
    final totalMs = delayMs + 300;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      builder: (context, value, child) {
        final elapsed = value * totalMs;
        final delayedProgress = ((elapsed - delayMs) / 300).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(delayedProgress);
        return Opacity(
          opacity: eased,
          child: Transform.scale(scale: 0.4 + 0.6 * eased, child: child),
        );
      },
      child: AnimatedScale(
        scale: hovered ? 1.1 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2.5),
          ),
          child: const SizedBox(width: 13, height: 13),
        ),
      ),
    );
  }
}

class _HeatmapTooltip extends StatelessWidget {
  const _HeatmapTooltip({required this.count, required this.dateLabel});

  final int count;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.24),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Text.rich(
          _tooltipMessage(colors),
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }

  InlineSpan _tooltipMessage(SpringThemeColors colors) {
    final baseStyle = TextStyle(
      color: colors.text,
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
            style: TextStyle(color: colors.textSubtle),
          ),
          TextSpan(
            text: dateLabel,
            style: TextStyle(
              color: colors.textMuted,
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
          style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
        ),
        TextSpan(
          text: ' on ',
          style: TextStyle(color: colors.textSubtle),
        ),
        TextSpan(
          text: dateLabel,
          style: TextStyle(
            color: colors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _QuickCaptureCard extends StatelessWidget {
  const _QuickCaptureCard({
    required this.controller,
    required this.focusNode,
    required this.isSubmitting,
    required this.attachments,
    required this.pendingImages,
    required this.attachmentError,
    required this.onPasteShortcut,
    required this.onPickImages,
    required this.onPickDocuments,
    required this.onRemoveAttachment,
    required this.onRemovePendingImage,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSubmitting;
  final List<HomeAttachment> attachments;
  final List<PendingImage> pendingImages;
  final String? attachmentError;
  final VoidCallback onPasteShortcut;
  final VoidCallback onPickImages;
  final VoidCallback onPickDocuments;
  final ValueChanged<HomeAttachment> onRemoveAttachment;
  final ValueChanged<PendingImage> onRemovePendingImage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, child) {
        final colors = AppTheme.colors(context);
        final dark = Theme.of(context).brightness == Brightness.dark;
        final focused = focusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: dark
                ? (focused ? colors.inputFocusedFill : colors.inputFill)
                : (focused ? const Color(0xE6F5F5F5) : const Color(0x99F5F5F5)),
            border: Border.all(
              color: dark
                  ? (focused ? colors.textSubtle : colors.border)
                  : (focused
                        ? const Color(0xCCCFCFCF)
                        : const Color(0x99E0E0E0)),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        );
      },
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final colors = AppTheme.colors(context);
          final dark = Theme.of(context).brightness == Brightness.dark;
          final characterCount = controller.text.characters.length;
          final canSubmit =
              (controller.text.trim().isNotEmpty ||
                  attachments.isNotEmpty ||
                  pendingImages.isNotEmpty) &&
              !isSubmitting;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(
                    LogicalKeyboardKey.enter,
                    control: true,
                  ): onSubmit,
                  const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                      onSubmit,
                  const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                      onPasteShortcut,
                  const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                      onPasteShortcut,
                },
                child: SizedBox(
                  height: 96,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !isSubmitting,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: '写下你的想法，AI 将自动整理并生成结构化内容...',
                      hintStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colors.textSubtle),
                      hoverColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      filled: false,
                      fillColor: Colors.transparent,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.text,
                      fontSize: 14,
                      height: 1.625,
                    ),
                  ),
                ),
              ),
              if (pendingImages.isNotEmpty) ...[
                const SizedBox(height: 10),
                _PendingImageStrip(
                  images: pendingImages,
                  enabled: !isSubmitting,
                  onRemove: onRemovePendingImage,
                ),
              ],
              if (attachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                _AttachmentStrip(
                  attachments: attachments,
                  enabled: !isSubmitting,
                  onRemove: onRemoveAttachment,
                ),
              ],
              if (attachmentError != null) ...[
                const SizedBox(height: 8),
                Text(
                  attachmentError!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: dark
                        ? const Color(0xFFFCD34D)
                        : const Color(0xFFB45309),
                    fontSize: 12,
                  ),
                ),
              ],
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: colors.divider.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _ToolIcon(
                      type: _ToolIconType.image,
                      tooltip: '上传图片',
                      enabled: !isSubmitting,
                      onTap: onPickImages,
                    ),
                    const SizedBox(width: 4),
                    _ToolIcon(
                      type: _ToolIconType.paperclip,
                      tooltip: '添加文件',
                      enabled: !isSubmitting,
                      onTap: onPickDocuments,
                    ),
                    const SizedBox(width: 4),
                    const _ToolIcon(
                      type: _ToolIconType.atSign,
                      tooltip: '提及功能',
                    ),
                    const Spacer(),
                    Text(
                      '$characterCount 字',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSubtle,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 18),
                    _SmartGenerateButton(
                      canSubmit: canSubmit,
                      isSubmitting: isSubmitting,
                      onSubmit: onSubmit,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SmartGenerateButton extends StatefulWidget {
  const _SmartGenerateButton({
    required this.canSubmit,
    required this.isSubmitting,
    required this.onSubmit,
  });

  static const keyValue = ValueKey('home-smart-generate-button');

  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  State<_SmartGenerateButton> createState() => _SmartGenerateButtonState();
}

class _SmartGenerateButtonState extends State<_SmartGenerateButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = dark
        ? (_hovered && widget.canSubmit ? colors.textMuted : colors.text)
        : (_hovered && widget.canSubmit
              ? const Color(0xFF262626)
              : const Color(0xFF171717));
    final foregroundColor = dark ? colors.onAccent : Colors.white;
    return MouseRegion(
      cursor: widget.canSubmit
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: _SmartGenerateButton.keyValue,
        behavior: HitTestBehavior.opaque,
        onTap: widget.canSubmit ? widget.onSubmit : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.08),
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                widget.isSubmitting ? '整理中' : '智能生成',
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.333,
                ),
              ),
              const SizedBox(width: 6),
              if (widget.isSubmitting)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF34D399),
                    ),
                  ),
                )
              else
                const _LucideSparklesIcon(size: 12, color: Color(0xFF34D399)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingImageStrip extends StatelessWidget {
  const _PendingImageStrip({
    required this.images,
    required this.enabled,
    required this.onRemove,
  });

  final List<PendingImage> images;
  final bool enabled;
  final ValueChanged<PendingImage> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final image in images)
          _PendingImageChip(
            image: image,
            enabled: enabled,
            onRemove: () => onRemove(image),
          ),
      ],
    );
  }
}

class _PendingImageChip extends StatelessWidget {
  const _PendingImageChip({
    required this.image,
    required this.enabled,
    required this.onRemove,
  });

  final PendingImage image;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Tooltip(
      message: image.name,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        height: 40,
        padding: const EdgeInsets.only(left: 6, right: 4),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: 28,
                height: 28,
                child: image.isSvg
                    ? DecoratedBox(
                        decoration: BoxDecoration(color: colors.surfaceMuted),
                        child: Icon(
                          Icons.image_outlined,
                          size: 16,
                          color: colors.textMuted,
                        ),
                      )
                    : Image.memory(
                        image.bytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => DecoratedBox(
                          decoration: BoxDecoration(color: colors.surfaceMuted),
                          child: Icon(
                            Icons.image_outlined,
                            size: 16,
                            color: colors.textMuted,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '图片 · ${image.name}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textMuted,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? onRemove : null,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: enabled
                      ? colors.textSubtle
                      : colors.textSubtle.withValues(alpha: 0.48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentStrip extends StatelessWidget {
  const _AttachmentStrip({
    required this.attachments,
    required this.enabled,
    required this.onRemove,
  });

  final List<HomeAttachment> attachments;
  final bool enabled;
  final ValueChanged<HomeAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final attachment in attachments)
          _AttachmentChip(
            attachment: attachment,
            enabled: enabled,
            onRemove: () => onRemove(attachment),
          ),
      ],
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.enabled,
    required this.onRemove,
  });

  final HomeAttachment attachment;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final icon = attachment.kind == HomeAttachmentKind.image
        ? Icons.image_outlined
        : Icons.description_outlined;
    final typeLabel = attachment.kind == HomeAttachmentKind.image ? '图片' : '文件';

    return Tooltip(
      message: attachment.path,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        height: 32,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: colors.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$typeLabel · ${attachment.name}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textMuted,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? onRemove : null,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: enabled
                      ? colors.textSubtle
                      : colors.textSubtle.withValues(alpha: 0.48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ToolIconType { image, paperclip, atSign }

class _ToolIcon extends StatefulWidget {
  const _ToolIcon({
    required this.type,
    required this.tooltip,
    this.onTap,
    this.enabled = true,
  });

  final _ToolIconType type;
  final String tooltip;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<_ToolIcon> createState() => _ToolIconState();
}

class _ToolIconState extends State<_ToolIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final active = widget.enabled && widget.onTap != null;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: active ? widget.onTap : null,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    opacity: _hovered && active ? 1 : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                _LucideToolbarIcon(
                  type: widget.type,
                  size: 16,
                  color: _iconColor(context, active),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _iconColor(BuildContext context, bool active) {
    final colors = AppTheme.colors(context);
    if (!widget.enabled) {
      return colors.textSubtle.withValues(alpha: 0.48);
    }
    if (_hovered && active) {
      return colors.textMuted;
    }
    return colors.textSubtle;
  }
}

class _LucideToolbarIcon extends StatelessWidget {
  const _LucideToolbarIcon({
    required this.type,
    required this.size,
    required this.color,
  });

  final _ToolIconType type;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LucideToolbarPainter(type: type, color: color),
    );
  }
}

class _LucideToolbarPainter extends CustomPainter {
  const _LucideToolbarPainter({required this.type, required this.color});

  final _ToolIconType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24;
    final sy = size.height / 24;
    final strokeScale = sx < sy ? sx : sy;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * strokeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset point(double x, double y) => Offset(x * sx, y * sy);

    switch (type) {
      case _ToolIconType.image:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(3 * sx, 3 * sy, 18 * sx, 18 * sy),
            Radius.circular(2 * sx),
          ),
          paint,
        );
        canvas.drawCircle(point(9, 9), 2 * sx, paint);
        final imagePath = Path()
          ..moveTo(21 * sx, 15 * sy)
          ..lineTo(17.914 * sx, 11.914 * sy)
          ..cubicTo(
            17.133 * sx,
            11.133 * sy,
            15.867 * sx,
            11.133 * sy,
            15.086 * sx,
            11.914 * sy,
          )
          ..lineTo(6 * sx, 21 * sy);
        canvas.drawPath(imagePath, paint);
        break;
      case _ToolIconType.paperclip:
        final paperclipPath = Path()
          ..moveTo(16 * sx, 6 * sy)
          ..lineTo(7.586 * sx, 14.586 * sy)
          ..cubicTo(
            6.805 * sx,
            15.367 * sy,
            6.805 * sx,
            16.633 * sy,
            7.586 * sx,
            17.414 * sy,
          )
          ..cubicTo(
            8.367 * sx,
            18.195 * sy,
            9.633 * sx,
            18.195 * sy,
            10.414 * sx,
            17.414 * sy,
          )
          ..lineTo(18.828 * sx, 8.828 * sy)
          ..cubicTo(
            20.39 * sx,
            7.266 * sy,
            20.39 * sx,
            4.734 * sy,
            18.828 * sx,
            3.172 * sy,
          )
          ..cubicTo(
            17.266 * sx,
            1.61 * sy,
            14.734 * sx,
            1.61 * sy,
            13.172 * sx,
            3.172 * sy,
          )
          ..lineTo(4.793 * sx, 11.723 * sy)
          ..cubicTo(
            2.45 * sx,
            14.066 * sy,
            2.45 * sx,
            17.864 * sy,
            4.793 * sx,
            20.207 * sy,
          )
          ..cubicTo(
            7.136 * sx,
            22.55 * sy,
            10.934 * sx,
            22.55 * sy,
            13.277 * sx,
            20.207 * sy,
          )
          ..lineTo(21.656 * sx, 11.656 * sy);
        canvas.drawPath(paperclipPath, paint);
        break;
      case _ToolIconType.atSign:
        canvas.drawCircle(point(12, 12), 4 * sx, paint);
        final atPath = Path()
          ..moveTo(16 * sx, 8 * sy)
          ..lineTo(16 * sx, 13 * sy)
          ..cubicTo(
            16 * sx,
            14.657 * sy,
            17.343 * sx,
            16 * sy,
            19 * sx,
            16 * sy,
          )
          ..cubicTo(
            20.657 * sx,
            16 * sy,
            22 * sx,
            14.657 * sy,
            22 * sx,
            13 * sy,
          )
          ..lineTo(22 * sx, 12 * sy)
          ..cubicTo(22 * sx, 6.477 * sy, 17.523 * sx, 2 * sy, 12 * sx, 2 * sy)
          ..cubicTo(6.477 * sx, 2 * sy, 2 * sx, 6.477 * sy, 2 * sx, 12 * sy)
          ..cubicTo(2 * sx, 17.523 * sy, 6.477 * sx, 22 * sy, 12 * sx, 22 * sy)
          ..cubicTo(
            14.197 * sx,
            22 * sy,
            16.224 * sx,
            21.294 * sy,
            17.875 * sx,
            20.097 * sy,
          );
        canvas.drawPath(atPath, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _LucideToolbarPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}

class _LucideSparklesIcon extends StatelessWidget {
  const _LucideSparklesIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LucideSparklesPainter(color: color),
    );
  }
}

class _LucideSparklesPainter extends CustomPainter {
  const _LucideSparklesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 24;
    final scaleY = size.height / 24;
    final strokeScale = scaleX < scaleY ? scaleX : scaleY;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * strokeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path scaledPath(List<Offset> points) {
      final path = Path()
        ..moveTo(points.first.dx * scaleX, points.first.dy * scaleY);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx * scaleX, point.dy * scaleY);
      }
      return path;
    }

    final sparkle = Path()
      ..moveTo(11.017 * scaleX, 2.814 * scaleY)
      ..cubicTo(
        11.199 * scaleX,
        1.852 * scaleY,
        12.801 * scaleX,
        1.852 * scaleY,
        12.983 * scaleX,
        2.814 * scaleY,
      )
      ..lineTo(14.034 * scaleX, 8.372 * scaleY)
      ..cubicTo(
        14.184 * scaleX,
        9.165 * scaleY,
        14.835 * scaleX,
        9.816 * scaleY,
        15.628 * scaleX,
        9.966 * scaleY,
      )
      ..lineTo(21.186 * scaleX, 11.017 * scaleY)
      ..cubicTo(
        22.148 * scaleX,
        11.199 * scaleY,
        22.148 * scaleX,
        12.801 * scaleY,
        21.186 * scaleX,
        12.983 * scaleY,
      )
      ..lineTo(15.628 * scaleX, 14.034 * scaleY)
      ..cubicTo(
        14.835 * scaleX,
        14.184 * scaleY,
        14.184 * scaleX,
        14.835 * scaleY,
        14.034 * scaleX,
        15.628 * scaleY,
      )
      ..lineTo(12.983 * scaleX, 21.186 * scaleY)
      ..cubicTo(
        12.801 * scaleX,
        22.148 * scaleY,
        11.199 * scaleX,
        22.148 * scaleY,
        11.017 * scaleX,
        21.186 * scaleY,
      )
      ..lineTo(9.966 * scaleX, 15.628 * scaleY)
      ..cubicTo(
        9.816 * scaleX,
        14.835 * scaleY,
        9.165 * scaleX,
        14.184 * scaleY,
        8.372 * scaleX,
        14.034 * scaleY,
      )
      ..lineTo(2.814 * scaleX, 12.983 * scaleY)
      ..cubicTo(
        1.852 * scaleX,
        12.801 * scaleY,
        1.852 * scaleX,
        11.199 * scaleY,
        2.814 * scaleX,
        11.017 * scaleY,
      )
      ..lineTo(8.372 * scaleX, 9.966 * scaleY)
      ..cubicTo(
        9.165 * scaleX,
        9.816 * scaleY,
        9.816 * scaleX,
        9.165 * scaleY,
        9.966 * scaleX,
        8.372 * scaleY,
      )
      ..close();

    canvas.drawPath(sparkle, paint);
    canvas.drawPath(scaledPath(const [Offset(20, 2), Offset(20, 6)]), paint);
    canvas.drawPath(scaledPath(const [Offset(22, 4), Offset(18, 4)]), paint);
    canvas.drawCircle(Offset(4 * scaleX, 20 * scaleY), 2 * scaleX, paint);
  }

  @override
  bool shouldRepaint(covariant _LucideSparklesPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.overview});

  final StructuredWorkNote overview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cards = [
      _OverviewCard(
        eyebrow: 'Overview · 完成事项',
        accentColor: colors.textSubtle,
        items: overview.completed,
        emptyText: '完成事项',
      ),
      _OverviewCard(
        eyebrow: 'Featured · 问题记录',
        accentColor: dark ? const Color(0xFFFCA5A5) : const Color(0xFFF87171),
        items: overview.issues,
        emptyText: '问题记录',
      ),
      _OverviewCard(
        eyebrow: 'Overview · 明日计划',
        accentColor: colors.textSubtle,
        items: overview.plans,
        emptyText: '明日计划',
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
            const SizedBox(width: 24),
            Expanded(child: cards[1]),
            const SizedBox(width: 24),
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
    required this.accentColor,
    required this.items,
    required this.emptyText,
  });

  final String eyebrow;
  final Color accentColor;
  final List<String> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final visibleItems = items.take(2).toList();
    final lineTexts = [
      if (visibleItems.isEmpty) emptyText else visibleItems[0],
      if (visibleItems.length > 1) visibleItems[1] else '',
    ];

    return SoftCard(
      padding: const EdgeInsets.all(28),
      borderRadius: 16,
      withShadow: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < 2; index++)
                        Padding(
                          padding: EdgeInsets.only(bottom: index == 0 ? 4 : 0),
                          child: lineTexts[index].isEmpty
                              ? const SizedBox(width: 180, height: 16)
                              : ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 180,
                                  ),
                                  child: Text(
                                    lineTexts[index],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: index == 0
                                              ? colors.textMuted
                                              : colors.textSubtle,
                                          fontSize: 12,
                                          height: 1.333,
                                        ),
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Text(
            items.length.toString().padLeft(2, '0'),
            style: TextStyle(
              color: colors.text,
              fontSize: 36,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.9,
              height: 1,
              fontFamily: 'monospace',
              fontFeatures: [FontFeature.tabularFigures()],
            ),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF0B3024) : const Color(0xFFECFDF5);
    final border = dark ? const Color(0xFF14532D) : const Color(0xFFD1FAE5);
    final accent = dark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final foreground = dark ? const Color(0xFF86EFAC) : const Color(0xFF047857);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '已写入当日日报：$path',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foreground),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF3B2714) : const Color(0xFFFFFBEB);
    final border = dark ? const Color(0xFF78350F) : const Color(0xFFFDE68A);
    final accent = dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    final foreground = dark ? const Color(0xFFFCD34D) : const Color(0xFF92400E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudSyncIssueBanner extends StatelessWidget {
  const _CloudSyncIssueBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF3B1119) : const Color(0xFFFEF2F2);
    final border = dark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA);
    final accent = dark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626);
    final foreground = dark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateNoticeBanner extends StatefulWidget {
  const _UpdateNoticeBanner({
    required this.result,
    required this.updateCheckService,
  });

  final UpdateCheckResult result;
  final UpdateCheckService? updateCheckService;

  @override
  State<_UpdateNoticeBanner> createState() => _UpdateNoticeBannerState();
}

class _UpdateNoticeBannerState extends State<_UpdateNoticeBanner> {
  bool _hovered = false;

  bool get _clickable =>
      widget.result.status == UpdateCheckStatus.updateAvailable &&
      widget.result.latest != null;

  @override
  Widget build(BuildContext context) {
    final latest = widget.result.latest;
    final colors = AppTheme.colors(context);
    final message = switch (widget.result.status) {
      UpdateCheckStatus.updateAvailable =>
        '发现新版本 ${latest?.version ?? ''}，点击查看更新内容',
      UpdateCheckStatus.failed => '更新检测失败',
      UpdateCheckStatus.idle => '',
    };
    final foreground = widget.result.status == UpdateCheckStatus.failed
        ? colors.textSubtle
        : colors.textMuted;

    return MouseRegion(
      cursor: _clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (_clickable) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (_clickable) {
          setState(() => _hovered = false);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _clickable ? () => _showUpdateDialog(context, latest!) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceHover : colors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              if (widget.result.status == UpdateCheckStatus.failed)
                Icon(Icons.info_outline_rounded, size: 18, color: foreground)
              else
                UpdateDownloadIcon(size: 18, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_clickable)
                Icon(Icons.chevron_right_rounded, size: 20, color: foreground),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showUpdateDialog(
    BuildContext context,
    AppUpdateInfo latest,
  ) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (context) {
        return AppUpdateDialog(
          updateCheckService: widget.updateCheckService ?? UpdateCheckService(),
          currentVersion: widget.result.currentVersion,
          latest: latest,
        );
      },
    );
  }
}
