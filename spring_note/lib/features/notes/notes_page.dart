import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/local_data_state.dart';
import '../../core/models/note_external_update.dart';
import '../../core/models/note_file.dart';
import '../../core/services/ai_client_service.dart';
import '../../core/services/clipboard_image_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/note_service.dart';
import '../../core/services/note_upload_queue.dart';
import '../../core/services/pasted_image_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_scaffold.dart';
import 'markdown_preview.dart';

typedef NoteImagePicker = Future<List<NoteImageAttachment>> Function();

class NoteImageAttachment {
  const NoteImageAttachment({required this.path, required this.name});

  final String path;
  final String name;
}

class NotesPage extends StatefulWidget {
  const NotesPage({
    super.key,
    required this.localDataState,
    this.noteService = const NoteService(),
    this.aiClientService = const AiClientService(),
    this.clipboardImageService = const ClipboardImageService(),
    this.cloudSyncService = const CloudSyncService(),
    this.noteUploadQueue,
    this.pastedImageService = const PastedImageService(),
    this.externalNoteUpdate,
    this.imagePicker,
  });

  final LocalDataState localDataState;
  final NoteService noteService;
  final AiClientService aiClientService;
  final ClipboardImageService clipboardImageService;
  final CloudSyncService cloudSyncService;
  final NoteUploadQueue? noteUploadQueue;
  final PastedImageService pastedImageService;
  final ValueListenable<NoteExternalUpdate?>? externalNoteUpdate;
  final NoteImagePicker? imagePicker;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _FimTextEditingController _editorController =
      _FimTextEditingController();
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _editorFocusNode;

  NoteKind _kind = NoteKind.daily;
  List<NoteFile> _notes = [];
  NoteFile? _selectedNote;
  bool _loading = true;
  bool _saving = false;
  bool _predicting = false;
  String _statusText = '正在加载';
  String _lastEditorText = '';
  TextSelection _lastEditorSelection = const TextSelection.collapsed(offset: 0);
  int _editorRevision = 0;
  int _editorTextRevision = 0;
  bool _awaitingInitialEditorSelection = false;
  TextEditingValue? _editorInitialValue;
  bool _restoreInitialSelectionAfterUndo = false;
  final UndoHistoryController _editorUndoController = UndoHistoryController();
  Timer? _fimDebounce;
  int _fimGeneration = 0;
  String? _fimPrediction;
  String? _fimMessage;
  String? _editorMessage;
  bool _consumingFimPrediction = false;
  bool _insertingImage = false;
  bool _pastingClipboard = false;
  int _notesLoadGeneration = 0;
  Timer? _autoCloudSyncTimer;
  bool _autoCloudUploadAfterSave = false;
  bool _editorFocusedByPointer = false;
  NoteUploadQueue? _ownedNoteUploadQueue;

  static const Duration _autoCloudSyncInterval = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _editorFocusNode = FocusNode(onKeyEvent: _handleEditorKeyEvent);
    _editorFocusNode.addListener(_handleEditorFocusChanged);
    _editorController.addListener(_handleEditorChanged);
    _searchController.addListener(() => setState(() {}));
    widget.externalNoteUpdate?.addListener(_handleExternalNoteUpdate);
    _autoCloudSyncTimer = Timer.periodic(
      _autoCloudSyncInterval,
      (_) => unawaited(_flushPendingNoteUploads(requireEditorFocus: true)),
    );
    _noteUploadQueue.attach(widget.localDataState);
    _loadNotes(kind: _kind);
  }

  @override
  void didUpdateWidget(covariant NotesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalNoteUpdate != oldWidget.externalNoteUpdate) {
      oldWidget.externalNoteUpdate?.removeListener(_handleExternalNoteUpdate);
      widget.externalNoteUpdate?.addListener(_handleExternalNoteUpdate);
    }
    if (_localDataDirectoryChanged(oldWidget.localDataState)) {
      unawaited(_loadNotes(kind: _kind));
    }
    if (widget.localDataState != oldWidget.localDataState ||
        widget.noteUploadQueue != oldWidget.noteUploadQueue) {
      _noteUploadQueue.attach(widget.localDataState);
    }
  }

  @override
  void dispose() {
    widget.externalNoteUpdate?.removeListener(_handleExternalNoteUpdate);
    _editorController
      ..removeListener(_handleEditorChanged)
      ..dispose();
    _editorUndoController.dispose();
    _editorFocusNode.removeListener(_handleEditorFocusChanged);
    _editorFocusNode.dispose();
    _fimDebounce?.cancel();
    _autoCloudSyncTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  KeyEventResult _handleEditorKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final logicalKey = event.logicalKey;
    final controlPressed = HardwareKeyboard.instance.isControlPressed;
    final metaPressed = HardwareKeyboard.instance.isMetaPressed;
    if (event is KeyDownEvent &&
        logicalKey == LogicalKeyboardKey.keyV &&
        _isPasteModifierPressed(
          controlPressed: controlPressed,
          metaPressed: metaPressed,
        )) {
      unawaited(_handlePasteShortcut());
      return KeyEventResult.handled;
    }
    if (_isUndoShortcut(
      logicalKey: logicalKey,
      controlPressed: controlPressed,
      metaPressed: metaPressed,
    )) {
      _triggerEditorUndo();
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.tab) {
      if (_fimPrediction == null) {
        _insertPlainText('\t');
      } else {
        _acceptFimPrediction(_FimAcceptMode.all);
      }
      return KeyEventResult.handled;
    }
    if (_fimPrediction == null) {
      return KeyEventResult.ignored;
    }
    if (controlPressed && logicalKey == LogicalKeyboardKey.keyL) {
      _acceptFimPrediction(_FimAcceptMode.line);
      return KeyEventResult.handled;
    }
    if (controlPressed && logicalKey == LogicalKeyboardKey.keyK) {
      _acceptFimPrediction(_FimAcceptMode.character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleEditorFocusChanged() {
    if (_editorFocusNode.hasFocus) {
      _autoCloudUploadAfterSave = false;
      return;
    }
    final wasEditorFocusedByPointer = _editorFocusedByPointer;
    _editorFocusedByPointer = false;
    if (!wasEditorFocusedByPointer || !_autoCloudSyncAvailable) {
      return;
    }
    if (_saving) {
      _autoCloudUploadAfterSave = true;
      return;
    }
    unawaited(_flushPendingNoteUploads(requireEditorFocus: false));
  }

  void _handleEditorPointerFocus() {
    _editorFocusedByPointer = true;
    _captureInitialEditorSelectionSoon();
  }

  bool _isPasteModifierPressed({
    required bool controlPressed,
    required bool metaPressed,
  }) {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => metaPressed,
      _ => controlPressed,
    };
  }

  bool _isUndoShortcut({
    required LogicalKeyboardKey logicalKey,
    required bool controlPressed,
    required bool metaPressed,
  }) {
    if (logicalKey != LogicalKeyboardKey.keyZ ||
        HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }
    return _isPasteModifierPressed(
      controlPressed: controlPressed,
      metaPressed: metaPressed,
    );
  }

  bool _localDataDirectoryChanged(LocalDataState previous) {
    final current = widget.localDataState;
    return previous.dataDirectory != current.dataDirectory ||
        previous.dailyNotesDirectory != current.dailyNotesDirectory ||
        previous.weeklyNotesDirectory != current.weeklyNotesDirectory ||
        previous.monthlyNotesDirectory != current.monthlyNotesDirectory;
  }

  void _handleExternalNoteUpdate() {
    final update = widget.externalNoteUpdate?.value;
    if (update == null) {
      return;
    }
    unawaited(_refreshAfterExternalNoteUpdate(update));
  }

  Future<void> _refreshAfterExternalNoteUpdate(
    NoteExternalUpdate update,
  ) async {
    if (_kind != update.kind) {
      return;
    }

    final selected = _selectedNote;
    final directory = _directoryFor(_kind);
    final notes = await widget.noteService.listMarkdownFiles(
      directoryPath: directory,
      kind: _kind,
    );

    String? selectedContent;
    if (selected != null && _samePath(selected.path, update.path)) {
      selectedContent = await widget.noteService.readMarkdown(selected.path);
    }

    if (!mounted || _kind != update.kind) {
      return;
    }

    setState(() {
      _notes = notes;
      if (selected != null) {
        _selectedNote = notes.firstWhere(
          (note) => _samePath(note.path, selected.path),
          orElse: () => selected,
        );
      }
      if (selected != null && selectedContent != null) {
        if (selectedContent != _editorController.text) {
          _setEditorText(selectedContent, preserveSelection: true);
          _statusText = '已同步';
        }
      }
    });
  }

  Future<void> _loadNotes({
    required NoteKind kind,
    String? selectedPath,
  }) async {
    final generation = ++_notesLoadGeneration;
    setState(() {
      _kind = kind;
      _loading = true;
      _statusText = '正在加载';
    });

    final directory = _directoryFor(kind);
    var notes = await widget.noteService.listMarkdownFiles(
      directoryPath: directory,
      kind: kind,
    );
    NoteFile? currentDailyNote;
    if (kind == NoteKind.daily) {
      currentDailyNote = await widget.noteService.ensureCurrentMarkdownFile(
        directoryPath: directory,
        kind: kind,
      );
      notes = await widget.noteService.listMarkdownFiles(
        directoryPath: directory,
        kind: kind,
      );
    } else if (notes.isEmpty) {
      final current = await widget.noteService.ensureCurrentMarkdownFile(
        directoryPath: directory,
        kind: kind,
      );
      notes = [current];
    }

    final selected = selectedPath == null
        ? currentDailyNote == null
              ? notes.first
              : notes.firstWhere(
                  (note) => _samePath(note.path, currentDailyNote!.path),
                  orElse: () => currentDailyNote!,
                )
        : notes.firstWhere(
            (note) => note.path == selectedPath,
            orElse: () => notes.first,
          );
    final content = await widget.noteService.readMarkdown(selected.path);

    if (!mounted || generation != _notesLoadGeneration) {
      return;
    }

    setState(() {
      _notes = notes;
      _selectedNote = selected;
      _setEditorText(content);
      _loading = false;
      _statusText = '已加载';
    });
  }

  Future<void> _selectNote(NoteFile note) async {
    setState(() {
      _selectedNote = note;
      _loading = true;
      _statusText = '正在加载';
    });

    final content = await widget.noteService.readMarkdown(note.path);
    if (!mounted) {
      return;
    }

    setState(() {
      _setEditorText(content);
      _loading = false;
      _statusText = '已加载';
    });
  }

  void _handleEditorChanged() {
    final selected = _selectedNote;
    if (_loading || selected == null) {
      return;
    }

    final text = _editorController.text;
    final selection = _editorController.selection;
    final textChanged = text != _lastEditorText;
    final selectionChanged = selection != _lastEditorSelection;
    if (textChanged) {
      _editorTextRevision++;
    }

    if (_awaitingInitialEditorSelection && selectionChanged && !textChanged) {
      _captureInitialEditorSelection();
    } else if (_awaitingInitialEditorSelection && textChanged) {
      _awaitingInitialEditorSelection = false;
    }

    if (textChanged) {
      _restoreInitialSelectionIfUndoReachedBaseline(text);
    }

    final currentText = _editorController.text;
    final currentSelection = _editorController.selection;
    _lastEditorText = currentText;
    _lastEditorSelection = currentSelection;

    if (_consumingFimPrediction) {
      if (textChanged) {
        _saveEditorText(selected, currentText);
      }
      return;
    }

    if (textChanged || selectionChanged) {
      _invalidateFimPrediction(scheduleNext: true);
    }
    if (textChanged && _editorMessage != null) {
      setState(() => _editorMessage = null);
    }

    if (!textChanged) {
      return;
    }

    _saveEditorText(selected, currentText);
  }

  Future<void> _saveEditorText(NoteFile selected, String text) async {
    setState(() {
      _saving = true;
      _statusText = '保存中';
    });

    await widget.noteService.writeMarkdown(selected.path, text);
    _noteUploadQueue.markDirty(selected.path);
    final updatedNotes = await widget.noteService.listMarkdownFiles(
      directoryPath: _directoryFor(_kind),
      kind: _kind,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _notes = updatedNotes;
      _selectedNote = updatedNotes.firstWhere(
        (note) => note.path == selected.path,
        orElse: () => selected,
      );
      _saving = false;
      _statusText = '已保存';
    });
    if (_autoCloudUploadAfterSave && !_editorFocusNode.hasFocus) {
      _autoCloudUploadAfterSave = false;
      unawaited(_flushPendingNoteUploads(requireEditorFocus: false));
    }
  }

  Future<void> _flushPendingNoteUploads({
    required bool requireEditorFocus,
  }) async {
    if (!_autoCloudSyncAvailable ||
        (requireEditorFocus &&
            (!_editorFocusNode.hasFocus || !_editorFocusedByPointer)) ||
        _loading ||
        _saving) {
      return;
    }

    final editorTextRevision = _editorTextRevision;
    try {
      final result = await _noteUploadQueue.flush();
      if (!mounted || !result.attempted) {
        return;
      }
      if (result.ok) {
        setState(() {
          if (result.uploaded > 0 &&
              _editorTextRevision == editorTextRevision &&
              !_noteUploadQueue.hasPendingUploads) {
            _statusText = '已自动同步';
          }
          _editorMessage = null;
        });
      } else {
        setState(() {
          _editorMessage = '自动同步失败：${result.message}';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to auto upload note: $error\n$stackTrace');
      if (mounted) {
        setState(() => _editorMessage = '自动同步失败，请稍后重试。');
      }
    }
  }

  bool get _autoCloudSyncAvailable {
    final sync = widget.localDataState.config.cloudSync;
    return sync.enabled && sync.realTimeSync && sync.hasRequiredFields;
  }

  NoteUploadQueue get _noteUploadQueue {
    final provided = widget.noteUploadQueue;
    if (provided != null) {
      return provided;
    }
    return _ownedNoteUploadQueue ??= NoteUploadQueue(
      cloudSyncService: widget.cloudSyncService,
    )..attach(widget.localDataState);
  }

  void _setEditorText(String value, {bool preserveSelection = false}) {
    final nextSelection = preserveSelection
        ? _selectionClampedTo(value)
        : TextSelection.collapsed(offset: value.length);
    _editorController
      ..removeListener(_handleEditorChanged)
      ..text = value
      ..selection = nextSelection
      ..addListener(_handleEditorChanged);
    _editorRevision++;
    _editorTextRevision++;
    _awaitingInitialEditorSelection = true;
    _editorInitialValue = TextEditingValue(
      text: value,
      selection: nextSelection,
    );
    _restoreInitialSelectionAfterUndo = false;
    _lastEditorText = value;
    _lastEditorSelection = _editorController.selection;
    _fimGeneration++;
    _fimDebounce?.cancel();
    _fimPrediction = null;
    _predicting = false;
    _fimMessage = null;
    _editorMessage = null;
    _editorController.clearFimPrediction();
  }

  void _captureInitialEditorSelectionSoon() {
    if (!_awaitingInitialEditorSelection) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_awaitingInitialEditorSelection) {
        return;
      }
      if (_editorController.text != _lastEditorText) {
        _awaitingInitialEditorSelection = false;
        return;
      }
      _captureInitialEditorSelection();
    });
  }

  void _captureInitialEditorSelection() {
    final selection = _editorController.selection;
    if (!selection.isValid || _selectedNote == null) {
      return;
    }
    _awaitingInitialEditorSelection = false;
    _editorInitialValue = TextEditingValue(
      text: _editorController.text,
      selection: selection,
    );
    _lastEditorSelection = selection;
  }

  void _triggerEditorUndo() {
    final beforeUndo = _editorController.value;
    _restoreInitialSelectionAfterUndo = _editorInitialValue != null;
    _editorUndoController.undo();
    final initial = _editorInitialValue;
    if (_editorController.value == beforeUndo ||
        initial == null ||
        _editorController.text != initial.text) {
      _restoreInitialSelectionAfterUndo = false;
    }
  }

  void _restoreInitialSelectionIfUndoReachedBaseline(String text) {
    final initial = _editorInitialValue;
    if (!_restoreInitialSelectionAfterUndo ||
        initial == null ||
        text != initial.text) {
      return;
    }
    _restoreInitialSelectionAfterUndo = false;

    final selection = _selectionClampedToText(initial.selection, text);
    if (_editorController.selection == selection) {
      return;
    }
    scheduleMicrotask(() {
      if (!mounted || _editorController.text != initial.text) {
        return;
      }
      _editorController
        ..removeListener(_handleEditorChanged)
        ..selection = selection
        ..addListener(_handleEditorChanged);
      _lastEditorSelection = selection;
    });
  }

  TextSelection _selectionClampedTo(String text) {
    return _selectionClampedToText(_editorController.selection, text);
  }

  TextSelection _selectionClampedToText(TextSelection selection, String text) {
    if (!selection.isValid) {
      return TextSelection.collapsed(offset: text.length);
    }
    return TextSelection(
      baseOffset: _clampOffset(selection.baseOffset, text.length),
      extentOffset: _clampOffset(selection.extentOffset, text.length),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }

  int _clampOffset(int offset, int length) {
    if (offset < 0) {
      return 0;
    }
    if (offset > length) {
      return length;
    }
    return offset;
  }

  bool _samePath(String left, String right) {
    final normalizedLeft = left.replaceAll('\\', '/').toLowerCase();
    final normalizedRight = right.replaceAll('\\', '/').toLowerCase();
    return normalizedLeft == normalizedRight;
  }

  void _invalidateFimPrediction({required bool scheduleNext}) {
    _fimGeneration++;
    _fimDebounce?.cancel();

    if (_fimPrediction != null || _predicting) {
      setState(() {
        _fimPrediction = null;
        _predicting = false;
        _fimMessage = null;
        _editorController.clearFimPrediction();
      });
    }

    if (!scheduleNext || _selectedNote == null || _loading) {
      return;
    }

    final generation = _fimGeneration;
    final text = _editorController.text;
    final selection = _editorController.selection;

    if (!selection.isValid || !selection.isCollapsed) {
      return;
    }

    final unavailableReason = widget.aiClientService.fimUnavailableReason(
      widget.localDataState.config,
    );
    if (unavailableReason != null) {
      setState(() => _fimMessage = 'FIM 未触发：$unavailableReason');
      return;
    }

    if (_fimMessage != null) {
      setState(() => _fimMessage = null);
    }

    _fimDebounce = Timer(const Duration(milliseconds: 300), () {
      _requestFimPrediction(
        generation: generation,
        text: text,
        selection: selection,
      );
    });
  }

  Future<void> _requestFimPrediction({
    required int generation,
    required String text,
    required TextSelection selection,
  }) async {
    if (!mounted ||
        generation != _fimGeneration ||
        text != _editorController.text ||
        selection != _editorController.selection) {
      return;
    }

    setState(() => _predicting = true);
    final offset = selection.baseOffset;
    String? prediction;
    String? fimError;
    try {
      final result = await widget.aiClientService.fimCompleteMarkdown(
        appDataDir: widget.localDataState.dataDirectory,
        config: widget.localDataState.config,
        prompt: text.substring(0, offset),
        suffix: text.substring(offset),
      );
      prediction = result.content;
      fimError = result.error;
    } catch (_) {
      prediction = null;
    }

    if (!mounted ||
        generation != _fimGeneration ||
        text != _editorController.text ||
        selection != _editorController.selection) {
      return;
    }

    setState(() {
      _predicting = false;
      if (prediction?.isEmpty ?? true) {
        _fimPrediction = null;
        _fimMessage = fimError != null && fimError.isNotEmpty
            ? 'FIM 请求失败：$fimError'
            : 'FIM 已请求，但没有返回可用预测';
      } else {
        _fimPrediction = prediction;
        _fimMessage = null;
        _editorController.setFimPrediction(
          prediction!,
          offset: selection.baseOffset,
        );
      }
    });
  }

  void _acceptFimPrediction(_FimAcceptMode mode) {
    final prediction = _fimPrediction;
    final selection = _editorController.selection;
    if (prediction == null || prediction.isEmpty || !selection.isValid) {
      return;
    }

    final accepted = switch (mode) {
      _FimAcceptMode.all => prediction,
      _FimAcceptMode.line => _firstPredictionLine(prediction),
      _FimAcceptMode.character => prediction.characters.first,
    };
    final remaining = prediction.substring(accepted.length);

    final text = _editorController.text;
    final start = selection.start;
    final end = selection.end;
    final nextText = text.replaceRange(start, end, accepted);
    final nextOffset = start + accepted.length;
    _consumingFimPrediction = true;
    _editorController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _consumingFimPrediction = false;

    setState(() {
      if (remaining.isEmpty) {
        _fimPrediction = null;
        _editorController.clearFimPrediction();
      } else {
        _fimPrediction = remaining;
        _editorController.setFimPrediction(remaining, offset: nextOffset);
      }
      _fimMessage = null;
    });
  }

  void _insertPlainText(String value) {
    final selection = _editorController.selection;
    if (!selection.isValid) {
      return;
    }

    final text = _editorController.text;
    final start = selection.start;
    final end = selection.end;
    final nextText = text.replaceRange(start, end, value);
    final nextOffset = start + value.length;
    _editorController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
  }

  Future<void> _insertImageFromPicker() async {
    final selected = _selectedNote;
    if (_loading || selected == null || _insertingImage) {
      return;
    }

    _insertingImage = true;
    try {
      final images = await (widget.imagePicker ?? _defaultImagePicker)();
      if (!mounted) {
        return;
      }
      if (images.isEmpty) {
        setState(() => _editorMessage = '已取消选择图片');
        return;
      }
      final copiedImages = <NoteImageAttachment>[];
      for (final image in images) {
        if (image.path.trim().isEmpty) {
          continue;
        }
        final saved = await widget.pastedImageService.copyImageFileForNote(
          notePath: selected.path,
          sourcePath: image.path,
          sourceName: image.name,
        );
        copiedImages.add(
          NoteImageAttachment(path: saved.path, name: saved.name),
        );
      }
      final snippets = copiedImages
          .map((image) => _markdownImageSnippet(image, notePath: selected.path))
          .toList();
      if (snippets.isEmpty) {
        return;
      }
      _insertPlainText(_insertionTextForBlock(snippets.join('\n')));
      setState(() {
        _editorMessage = '已插入图片';
        _fimMessage = null;
      });
      _editorFocusNode.requestFocus();
    } on ArgumentError catch (error, stackTrace) {
      debugPrint('Unsupported image selected: $error\n$stackTrace');
      if (mounted) {
        setState(() => _editorMessage = '图片格式不支持，请重新选择文件。');
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to insert image: $error\n$stackTrace');
      if (mounted) {
        setState(() => _editorMessage = '无法插入图片，请重新选择文件。');
      }
    } finally {
      _insertingImage = false;
    }
  }

  Future<void> _handlePasteShortcut() async {
    if (_loading || _selectedNote == null || _pastingClipboard) {
      return;
    }

    _pastingClipboard = true;
    try {
      final imageFiles = await _readClipboardImageFiles();
      if (!mounted || _loading) {
        return;
      }
      final selected = _selectedNote;

      if (selected != null && imageFiles.isNotEmpty) {
        await _pasteClipboardImageFiles(selected.path, imageFiles);
        return;
      }

      final imageBytes = await _readClipboardImage();
      if (!mounted || _loading) {
        return;
      }

      if (selected != null && imageBytes != null && imageBytes.isNotEmpty) {
        await _pasteClipboardImage(selected.path, imageBytes);
        return;
      }

      await _pasteClipboardText();
    } finally {
      _pastingClipboard = false;
    }
  }

  Future<List<NoteImageAttachment>> _readClipboardImageFiles() async {
    try {
      final files = await widget.clipboardImageService.readImageFiles();
      return files
          .map(
            (path) =>
                NoteImageAttachment(path: path, name: _fileNameFromPath(path)),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Uint8List?> _readClipboardImage() async {
    try {
      return widget.clipboardImageService.readPngImage();
    } catch (_) {
      return null;
    }
  }

  Future<void> _pasteClipboardImageFiles(
    String notePath,
    List<NoteImageAttachment> imageFiles,
  ) async {
    try {
      final copiedImages = <NoteImageAttachment>[];
      for (final image in imageFiles) {
        final saved = await widget.pastedImageService.copyImageFileForNote(
          notePath: notePath,
          sourcePath: image.path,
          sourceName: image.name,
        );
        copiedImages.add(
          NoteImageAttachment(path: saved.path, name: saved.name),
        );
      }
      if (!mounted || copiedImages.isEmpty) {
        return;
      }
      final snippets = copiedImages
          .map((image) => _markdownImageSnippet(image, notePath: notePath))
          .toList();
      _insertPlainText(_insertionTextForBlock(snippets.join('\n')));
      setState(() {
        _editorMessage = '已粘贴图片';
        _fimMessage = null;
      });
      _editorFocusNode.requestFocus();
    } on ArgumentError catch (error, stackTrace) {
      debugPrint('Unsupported clipboard image file: $error\n$stackTrace');
      if (mounted) {
        setState(() => _editorMessage = '图片格式不支持，请重新复制图片文件。');
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to paste clipboard image files: $error\n$stackTrace');
      if (mounted) {
        setState(() => _editorMessage = '无法粘贴图片，请重新获取图片后重试。');
      }
    }
  }

  Future<void> _pasteClipboardImage(
    String notePath,
    Uint8List imageBytes,
  ) async {
    try {
      final saved = await widget.pastedImageService.savePngForNote(
        notePath: notePath,
        pngBytes: imageBytes,
      );
      if (!mounted) {
        return;
      }
      final image = NoteImageAttachment(path: saved.path, name: saved.name);
      _insertPlainText(
        _insertionTextForBlock(
          _markdownImageSnippet(image, notePath: notePath),
        ),
      );
      setState(() {
        _editorMessage = '已粘贴图片';
        _fimMessage = null;
      });
      _editorFocusNode.requestFocus();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _editorMessage = '无法粘贴图片，请重新获取图片后重试。');
    }
  }

  Future<void> _pasteClipboardText() async {
    final ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      if (mounted) {
        setState(() => _editorMessage = '无法读取剪贴板文字。');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final text = data?.text;
    if (text == null || text.isEmpty) {
      setState(() => _editorMessage = '剪贴板中没有可粘贴的内容。');
      return;
    }
    _insertPlainText(text);
    _editorFocusNode.requestFocus();
  }

  Future<List<NoteImageAttachment>> _defaultImagePicker() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'bmp'],
          mimeTypes: ['image/*'],
          uniformTypeIdentifiers: ['public.image'],
          webWildCards: ['image/*'],
        ),
      ],
      confirmButtonText: '选择图片',
    );
    return files
        .map(
          (file) => NoteImageAttachment(path: file.path, name: _fileName(file)),
        )
        .toList();
  }

  String _fileName(XFile file) {
    final name = file.name.trim();
    if (name.isNotEmpty) {
      return name;
    }
    return _fileNameFromPath(file.path);
  }

  String _fileNameFromPath(String path) {
    final segments = path.split(RegExp(r'[\\/]')).where((item) {
      return item.trim().isNotEmpty;
    }).toList();
    if (segments.isEmpty) {
      return path;
    }
    return segments.last;
  }

  String _markdownImageSnippet(
    NoteImageAttachment image, {
    required String notePath,
  }) {
    final imagePath = widget.pastedImageService.markdownPathForNote(
      notePath: notePath,
      imagePath: image.path,
    );
    return '![${_escapeImageAltText(image.name)}]($imagePath)';
  }

  String _escapeImageAltText(String value) {
    return value
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ')
        .replaceAll('\\', r'\\')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)')
        .trim();
  }

  String _parentDirectoryPath(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf('\\');
    final index = slash > backslash ? slash : backslash;
    if (index <= 0) {
      return path;
    }
    return path.substring(0, index);
  }

  String _insertionTextForBlock(String block) {
    final selection = _editorController.selection;
    final text = _editorController.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final before = text.substring(0, start);
    final after = text.substring(end);
    final prefix = before.isEmpty || before.endsWith('\n') ? '' : '\n';
    final suffix = after.isEmpty || after.startsWith('\n') ? '' : '\n';
    return '$prefix$block$suffix';
  }

  String _firstPredictionLine(String prediction) {
    final newlineIndex = prediction.indexOf('\n');
    if (newlineIndex == -1) {
      return prediction;
    }
    return prediction.substring(0, newlineIndex + 1);
  }

  String _directoryFor(NoteKind kind) {
    return switch (kind) {
      NoteKind.daily => widget.localDataState.dailyNotesDirectory,
      NoteKind.weekly => widget.localDataState.weeklyNotesDirectory,
      NoteKind.monthly => widget.localDataState.monthlyNotesDirectory,
    };
  }

  List<NoteFile> get _filteredNotes {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _notes;
    }
    return _notes
        .where(
          (note) =>
              note.title.toLowerCase().contains(query) ||
              note.name.toLowerCase().contains(query) ||
              note.searchText.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedNote;

    return Material(
      color: AppTheme.background,
      child: Row(
        children: [
          _NotesSidebar(
            kind: _kind,
            notes: _filteredNotes,
            selectedPath: selected?.path,
            searchController: _searchController,
            onKindChanged: (kind) => _loadNotes(kind: kind),
            onNoteSelected: _selectNote,
          ),
          Expanded(
            flex: 32,
            child: _EditorPane(
              controller: _editorController,
              editorRevision: _editorRevision,
              undoController: _editorUndoController,
              focusNode: _editorFocusNode,
              statusText: _editorStatusText,
              enabled: selected != null && !_loading,
              predicting: _predicting,
              onInsertImage: _insertImageFromPicker,
              onPointerFocus: _handleEditorPointerFocus,
            ),
          ),
          Expanded(
            flex: 32,
            child: _PreviewPane(
              markdown: _editorController.text,
              localImageBasePath: selected == null
                  ? null
                  : _parentDirectoryPath(selected.path),
            ),
          ),
        ],
      ),
    );
  }

  String get _editorStatusText {
    if (_saving) {
      return '保存中';
    }
    if (_predicting) {
      return '补全预测中';
    }
    if (_fimPrediction != null) {
      return 'Tab 全部 · Ctrl+L 单行 · Ctrl+K 单字';
    }
    if (_fimMessage != null) {
      return _fimMessage!;
    }
    if (_editorMessage != null) {
      return _editorMessage!;
    }
    return _statusText;
  }
}

enum _FimAcceptMode { all, line, character }

class _FimTextEditingController extends TextEditingController {
  String? _fimPrediction;
  int? _fimOffset;

  void setFimPrediction(String prediction, {required int offset}) {
    final normalizedOffset = offset.clamp(0, text.length);
    if (_fimPrediction == prediction && _fimOffset == normalizedOffset) {
      return;
    }
    _fimPrediction = prediction;
    _fimOffset = normalizedOffset;
    notifyListeners();
  }

  void clearFimPrediction() {
    if (_fimPrediction == null && _fimOffset == null) {
      return;
    }
    _fimPrediction = null;
    _fimOffset = null;
    notifyListeners();
  }

  TextSpan _bottomSpacer(TextStyle style) {
    return TextSpan(
      text: '\n',
      style: style.copyWith(color: Colors.transparent),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final prediction = _fimPrediction;
    final offset = _fimOffset;
    final effectiveStyle = style ?? const TextStyle();
    if (prediction == null ||
        prediction.isEmpty ||
        offset == null ||
        offset < 0 ||
        offset > text.length) {
      return TextSpan(
        style: effectiveStyle,
        children: [
          super.buildTextSpan(
            context: context,
            style: style,
            withComposing: withComposing,
          ),
          _bottomSpacer(effectiveStyle),
        ],
      );
    }

    return TextSpan(
      style: effectiveStyle,
      children: [
        TextSpan(text: text.substring(0, offset)),
        TextSpan(
          text: prediction,
          style: effectiveStyle.copyWith(color: const Color(0xFF9AA0A6)),
        ),
        TextSpan(text: text.substring(offset)),
        _bottomSpacer(effectiveStyle),
      ],
    );
  }
}

class _NotesSidebar extends StatelessWidget {
  const _NotesSidebar({
    required this.kind,
    required this.notes,
    required this.selectedPath,
    required this.searchController,
    required this.onKindChanged,
    required this.onNoteSelected,
  });

  final NoteKind kind;
  final List<NoteFile> notes;
  final String? selectedPath;
  final TextEditingController searchController;
  final ValueChanged<NoteKind> onKindChanged;
  final ValueChanged<NoteFile> onNoteSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 278,
      padding: const EdgeInsets.fromLTRB(18, 24, 14, 20),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(right: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('笔记本', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  kind.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const Spacer(),
              _NotesKindMenuButton(kind: kind, onKindChanged: onKindChanged),
            ],
          ),
          const SizedBox(height: 16),
          _NotesSearchField(controller: searchController),
          const SizedBox(height: 16),
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配的便签',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: notes.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      return _NoteListItem(
                        note: note,
                        selected: note.path == selectedPath,
                        onTap: () => onNoteSelected(note),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _NotesKindMenuButton extends StatefulWidget {
  const _NotesKindMenuButton({required this.kind, required this.onKindChanged});

  final NoteKind kind;
  final ValueChanged<NoteKind> onKindChanged;

  @override
  State<_NotesKindMenuButton> createState() => _NotesKindMenuButtonState();
}

class _NotesKindMenuButtonState extends State<_NotesKindMenuButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  bool get _open => _overlayEntry != null;

  @override
  void dispose() {
    _removeOverlay(updateState: false);
    super.dispose();
  }

  void _toggleOverlay() {
    if (_open) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeOverlay,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 6),
            child: _NotesKindMenuTransition(
              child: _NotesKindMenu(
                selectedKind: widget.kind,
                onSelected: (kind) {
                  _removeOverlay();
                  if (kind != widget.kind) {
                    widget.onKindChanged(kind);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_overlayEntry!);
    setState(() {});
  }

  void _removeOverlay({bool updateState = true}) {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (updateState && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SpringNoteIconButton(
        tooltip: '切换日报/周报/月报',
        icon: Icons.more_horiz,
        onPressed: _toggleOverlay,
      ),
    );
  }
}

class _NotesKindMenuTransition extends StatelessWidget {
  const _NotesKindMenuTransition({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(opacity: value, child: child);
      },
      child: child,
    );
  }
}

class _NotesKindMenu extends StatefulWidget {
  const _NotesKindMenu({required this.selectedKind, required this.onSelected});

  final NoteKind selectedKind;
  final ValueChanged<NoteKind> onSelected;

  @override
  State<_NotesKindMenu> createState() => _NotesKindMenuState();
}

class _NotesKindMenuState extends State<_NotesKindMenu> {
  NoteKind? _hoveredKind;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE8E8E8)),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x17171717),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
            BoxShadow(
              color: Color(0x0A171717),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
              child: Text(
                '切换笔记类型',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.textSubtle,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            SizedBox(
              height: _NotesKindMenuItem.itemHeight * NoteKind.values.length,
              child: Column(
                children: [
                  for (final kind in NoteKind.values)
                    _NotesKindMenuItem(
                      kind: kind,
                      selected: kind == widget.selectedKind,
                      hovered: kind == _hoveredKind,
                      onHoverChanged: (hovered) {
                        setState(() {
                          if (hovered) {
                            _hoveredKind = kind;
                          } else if (_hoveredKind == kind) {
                            _hoveredKind = null;
                          }
                        });
                      },
                      onTap: () => widget.onSelected(kind),
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

class _NotesKindMenuItem extends StatelessWidget {
  const _NotesKindMenuItem({
    required this.kind,
    required this.selected,
    required this.hovered,
    required this.onHoverChanged,
    required this.onTap,
  });

  final NoteKind kind;
  final bool selected;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;

  static const double itemHeight = 52;

  @override
  Widget build(BuildContext context) {
    final active = selected || hovered;
    final backgroundColor = selected
        ? const Color(0xFFE2E2E2)
        : const Color(0xFFF5F5F5);
    final contentColor = active ? AppTheme.text : AppTheme.textMuted;
    final subtleColor = active ? AppTheme.textSubtle : const Color(0xFF8A8A8A);
    final titleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: contentColor,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      height: 1.1,
    );
    final subtitleStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: subtleColor, height: 1.1);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: itemHeight,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                bottom: 4,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  opacity: active ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                bottom: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(
                        _iconForKind(kind),
                        size: 17,
                        color: active ? AppTheme.text : AppTheme.textSubtle,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(kind.label, style: titleStyle),
                            const SizedBox(height: 3),
                            Text(
                              _descriptionForKind(kind),
                              style: subtitleStyle,
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppTheme.text,
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

  IconData _iconForKind(NoteKind kind) {
    return switch (kind) {
      NoteKind.daily => Icons.calendar_today_outlined,
      NoteKind.weekly => Icons.view_week_outlined,
      NoteKind.monthly => Icons.calendar_month_outlined,
    };
  }

  String _descriptionForKind(NoteKind kind) {
    return switch (kind) {
      NoteKind.daily => '每日记录',
      NoteKind.weekly => '阶段整理',
      NoteKind.monthly => '月度沉淀',
    };
  }
}

class _NotesSearchField extends StatefulWidget {
  const _NotesSearchField({required this.controller});

  final TextEditingController controller;

  @override
  State<_NotesSearchField> createState() => _NotesSearchFieldState();
}

class _NotesSearchFieldState extends State<_NotesSearchField> {
  late final FocusNode _focusNode = FocusNode()
    ..addListener(_handleFocusChanged);

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      height: 40,
      decoration: BoxDecoration(
        color: focused ? const Color(0xFFE2E2E2) : const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          textAlignVertical: TextAlignVertical.center,
          cursorHeight: 16,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.text, height: 1.2),
          decoration: InputDecoration(
            hintText: '搜索知识记录...',
            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSubtle.withValues(alpha: 0.78),
              height: 1.2,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 18,
              color: Color(0xFF8A8A8A),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            isDense: true,
            isCollapsed: true,
            filled: false,
            hoverColor: Colors.transparent,
            contentPadding: const EdgeInsets.only(right: 12),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

class _NoteListItem extends StatefulWidget {
  const _NoteListItem({
    required this.note,
    required this.selected,
    required this.onTap,
  });

  final NoteFile note;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NoteListItem> createState() => _NoteListItemState();
}

class _NoteListItemState extends State<_NoteListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.selected
        ? const Color(0xFFE2E2E2)
        : const Color(0xFFF5F5F5);
    final active = widget.selected || _hovered;
    final titleColor = active ? AppTheme.text : const Color(0xFF6E6E6E);
    final secondaryColor = active
        ? const Color(0xFF737373)
        : const Color(0xFF8A8A8A);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (!_hovered) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (_hovered) {
          setState(() => _hovered = false);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Stack(
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
                        borderRadius: BorderRadius.circular(14),
                      ),
                    );
                  },
                ),
              ),
            ),
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: titleColor),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              builder: (context, animatedTitleColor, _) {
                return TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: secondaryColor),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, animatedSecondaryColor, _) {
                    final effectiveTitleColor =
                        animatedTitleColor ?? titleColor;
                    final effectiveSecondaryColor =
                        animatedSecondaryColor ?? secondaryColor;
                    return Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.note.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: effectiveTitleColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatModified(widget.note.modifiedAt),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: effectiveSecondaryColor,
                                      fontSize: 11,
                                      fontFamily: 'Consolas',
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            widget.note.preview.isEmpty
                                ? widget.note.name
                                : widget.note.preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: effectiveSecondaryColor,
                                  fontSize: 12,
                                ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatModified(DateTime value) {
    final now = DateTime.now();
    if (value.year == now.year &&
        value.month == now.month &&
        value.day == now.day) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    return '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}

class _EditorPane extends StatefulWidget {
  const _EditorPane({
    required this.controller,
    required this.editorRevision,
    required this.undoController,
    required this.focusNode,
    required this.statusText,
    required this.enabled,
    required this.predicting,
    required this.onInsertImage,
    required this.onPointerFocus,
  });

  final TextEditingController controller;
  final int editorRevision;
  final UndoHistoryController undoController;
  final FocusNode focusNode;
  final String statusText;
  final bool enabled;
  final bool predicting;
  final VoidCallback onInsertImage;
  final VoidCallback onPointerFocus;

  @override
  State<_EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<_EditorPane> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editorStyle =
        Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF3A3A3A),
          fontSize: 14,
          height: 1.55,
        ) ??
        const TextStyle(color: Color(0xFF3A3A3A), fontSize: 14, height: 1.55);
    return _PaneFrame(
      headerPadding: const EdgeInsets.only(left: 32, right: 16),
      header: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(
                  Icons.code_rounded,
                  size: 15,
                  color: Color(0xFF8A8A8A),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Markdown Source · 源码编辑',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF8A8A8A),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SpringNoteIconButton(
            tooltip: '插入图片',
            icon: Icons.image_outlined,
            onPressed: widget.enabled ? widget.onInsertImage : null,
          ),
          const SizedBox(width: 8),
          _EditorStatusPill(statusText: widget.statusText),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sideInset = constraints.maxWidth > 720
              ? (constraints.maxWidth - 720) / 2 + 40
              : 40.0;

          return Stack(
            children: [
              Positioned.fill(
                child: Scrollbar(
                  controller: _scrollController,
                  child: ScrollConfiguration(
                    behavior: const _EditorTextFieldScrollBehavior(),
                    child: TextSelectionTheme(
                      data: TextSelectionTheme.of(context).copyWith(
                        cursorColor: const Color(0xFF6E6E6E),
                        selectionColor: const Color(
                          0xFFBDBDBD,
                        ).withValues(alpha: 0.34),
                        selectionHandleColor: const Color(0xFF737373),
                      ),
                      child: TextField(
                        key: ValueKey('note-editor-${widget.editorRevision}'),
                        controller: widget.controller,
                        undoController: widget.undoController,
                        focusNode: widget.focusNode,
                        onTap: widget.onPointerFocus,
                        scrollController: _scrollController,
                        enabled: widget.enabled,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: '# 开始编辑 Markdown...',
                          hintStyle: const TextStyle(color: Color(0xFFCFCFCF)),
                          filled: true,
                          fillColor: Colors.white,
                          hoverColor: Colors.white,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.fromLTRB(
                            sideInset,
                            0,
                            sideInset / 2,
                            0,
                          ),
                        ),
                        style: editorStyle,
                        cursorColor: const Color(0xFF6E6E6E),
                        cursorWidth: 1.25,
                        cursorRadius: const Radius.circular(1),
                        selectionControls: desktopTextSelectionHandleControls,
                        enableInteractiveSelection: true,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EditorTextFieldScrollBehavior extends ScrollBehavior {
  const _EditorTextFieldScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _EditorStatusPill extends StatelessWidget {
  const _EditorStatusPill({required this.statusText});

  final String statusText;

  @override
  Widget build(BuildContext context) {
    final displayText = switch (statusText) {
      '已加载' => 'AI 实时补全已就绪',
      '补全预测中' => 'AI 补全预测中',
      _ => statusText,
    };
    final active =
        statusText == '已加载' ||
        statusText == '补全预测中' ||
        statusText.startsWith('Tab ');
    final foreground = active
        ? const Color(0xFF10B981)
        : const Color(0xFF666666);
    final background = active
        ? const Color(0xFFECFDF5)
        : const Color(0xFFF5F5F5);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 12, color: foreground),
            const SizedBox(width: 4),
            Text(
              displayText,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.markdown,
    required this.localImageBasePath,
  });

  final String markdown;
  final String? localImageBasePath;

  @override
  Widget build(BuildContext context) {
    return _PaneFrame(
      headerPadding: const EdgeInsets.symmetric(horizontal: 24),
      header: Row(
        children: [
          Text(
            'Markdown Preview · 渲染预览',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF8A8A8A),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.open_in_full_rounded,
            size: 15,
            color: AppTheme.textSubtle,
          ),
        ],
      ),
      child: MarkdownPreview(
        markdown: markdown,
        localImageBasePath: localImageBasePath,
      ),
    );
  }
}

class _PaneFrame extends StatelessWidget {
  const _PaneFrame({
    required this.header,
    required this.child,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 24),
  });

  final Widget header;
  final Widget child;
  final EdgeInsetsGeometry headerPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Column(
        children: [
          Container(
            height: 56,
            padding: headerPadding,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFEDEDED))),
            ),
            child: header,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
