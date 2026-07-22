import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/app_config.dart';
import '../../core/models/local_data_state.dart';
import '../../core/models/note_external_update.dart';
import '../../core/models/note_file.dart';
import '../../core/services/ai_client_service.dart';
import '../../core/services/clipboard_image_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/local_data_service.dart';
import '../../core/services/note_service.dart';
import '../../core/services/note_upload_queue.dart';
import '../../core/services/pasted_image_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/markdown_editor_highlight.dart';
import '../../core/widgets/page_scaffold.dart';
import 'markdown_preview.dart';

typedef NoteImagePicker = Future<List<NoteImageAttachment>> Function();

enum _EditorWorkspaceMode { edit, split, preview }

const _notesEditorBodyFontSize = 14.0;
const _notesEditorTopContentPadding = _notesEditorBodyFontSize / 2;

_EditorWorkspaceMode _workspaceModeFromConfig(AppConfig config) {
  for (final mode in _EditorWorkspaceMode.values) {
    if (mode.name == config.notesEditorWorkspaceMode) {
      return mode;
    }
  }
  return _EditorWorkspaceMode.split;
}

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
    this.localDataService,
    this.onConfigChanged,
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
  final LocalDataService? localDataService;
  final ValueChanged<AppConfig>? onConfigChanged;

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
  String _statusText = 'AI 实时补全已就绪';
  String _lastEditorText = '';
  TextSelection _lastEditorSelection = const TextSelection.collapsed(offset: 0);
  int _editorRevision = 0;
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
  bool _regeneratingReport = false;
  int _notesLoadGeneration = 0;
  int _noteSelectionGeneration = 0;
  int _saveGeneration = 0;
  int _searchGeneration = 0;
  Timer? _searchDebounce;
  List<NoteFile> _searchResults = [];
  bool _searching = false;
  Timer? _autoCloudSyncTimer;
  bool _autoCloudUploadAfterSave = false;
  bool _editorFocusedByPointer = false;
  late _EditorWorkspaceMode _workspaceMode;
  NoteUploadQueue? _ownedNoteUploadQueue;

  static const Duration _autoCloudSyncInterval = Duration(seconds: 3);
  static const int _minimumSearchQueryCharacters = 2;

  @override
  void initState() {
    super.initState();
    _workspaceMode = _workspaceModeFromConfig(widget.localDataState.config);
    _editorController.markdownSyntaxHighlightEnabled =
        widget.localDataState.config.markdownSyntaxHighlightEnabled;
    _editorFocusNode = FocusNode(onKeyEvent: _handleEditorKeyEvent);
    _editorFocusNode.addListener(_handleEditorFocusChanged);
    _editorController.addListener(_handleEditorChanged);
    _searchController.addListener(_handleSearchChanged);
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
    _editorController.markdownSyntaxHighlightEnabled =
        widget.localDataState.config.markdownSyntaxHighlightEnabled;
    if (widget.localDataState.config.notesEditorWorkspaceMode !=
        oldWidget.localDataState.config.notesEditorWorkspaceMode) {
      _workspaceMode = _workspaceModeFromConfig(widget.localDataState.config);
    }
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

  void _handleWorkspaceModeChanged(_EditorWorkspaceMode mode) {
    if (_workspaceMode == mode) {
      return;
    }
    setState(() => _workspaceMode = mode);

    final nextConfig = widget.localDataState.config.copyWith(
      notesEditorWorkspaceMode: mode.name,
    );
    widget.onConfigChanged?.call(nextConfig);

    final localDataService = widget.localDataService;
    if (localDataService != null) {
      unawaited(localDataService.saveConfig(nextConfig).catchError((_) {}));
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
    _searchDebounce?.cancel();
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
    await widget.noteService.indexMarkdownFile(
      directoryPath: directory,
      kind: _kind,
      notePath: update.path,
    );
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
          _statusText = 'AI 实时补全已就绪';
        }
      }
    });
    _scheduleSearch(immediate: true);
  }

  Future<void> _loadNotes({
    required NoteKind kind,
    String? selectedPath,
  }) async {
    final generation = ++_notesLoadGeneration;
    final selectionGeneration = ++_noteSelectionGeneration;
    _saveGeneration++;
    _searchGeneration++;
    _searchDebounce?.cancel();
    setState(() {
      _kind = kind;
      _loading = true;
      _saving = false;
      _searchResults = [];
      _searching =
          _searchController.text.trim().runes.length >=
          _minimumSearchQueryCharacters;
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

    if (!mounted ||
        generation != _notesLoadGeneration ||
        selectionGeneration != _noteSelectionGeneration) {
      return;
    }

    setState(() {
      _notes = notes;
      _selectedNote = selected;
      _setEditorText(content);
      _loading = false;
      _statusText = 'AI 实时补全已就绪';
    });
    _scheduleSearch(immediate: true);
    unawaited(_refreshNoteIndex(kind: kind, loadGeneration: generation));
  }

  Future<void> _selectNote(
    NoteFile note, {
    TextSelection? initialSelection,
    bool focusEditor = false,
  }) async {
    final generation = ++_noteSelectionGeneration;
    _saveGeneration++;
    setState(() {
      _selectedNote = note;
      _loading = true;
      _saving = false;
    });

    final content = await widget.noteService.readMarkdown(note.path);
    if (!mounted ||
        generation != _noteSelectionGeneration ||
        !_samePath(_selectedNote?.path ?? '', note.path)) {
      return;
    }

    setState(() {
      _setEditorText(content, initialSelection: initialSelection);
      _loading = false;
      _statusText = 'AI 实时补全已就绪';
    });
    if (focusEditor) {
      _focusEditorSelectionSoon();
    }
  }

  Future<void> _refreshNoteIndex({
    required NoteKind kind,
    required int loadGeneration,
  }) async {
    final changed = await widget.noteService.refreshMarkdownIndex(
      directoryPath: _directoryFor(kind),
      kind: kind,
    );
    if (!changed ||
        !mounted ||
        loadGeneration != _notesLoadGeneration ||
        kind != _kind) {
      return;
    }

    final notes = await widget.noteService.listMarkdownFiles(
      directoryPath: _directoryFor(kind),
      kind: kind,
    );
    if (!mounted || loadGeneration != _notesLoadGeneration || kind != _kind) {
      return;
    }

    final selected = _selectedNote;
    setState(() {
      _notes = notes;
      if (selected != null) {
        _selectedNote = notes.firstWhere(
          (note) => _samePath(note.path, selected.path),
          orElse: () => selected,
        );
      }
    });
    _scheduleSearch(immediate: true);
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
    final generation = ++_saveGeneration;
    final kind = selected.kind;
    final directory = _directoryFor(kind);
    setState(() {
      _saving = true;
    });

    await widget.noteService.writeMarkdown(selected.path, text);
    _noteUploadQueue.markDirty(selected.path);
    await widget.noteService.indexMarkdownFile(
      directoryPath: directory,
      kind: kind,
      notePath: selected.path,
    );
    final updatedNote = widget.noteService.describeMarkdown(
      note: selected,
      content: text,
    );

    if (!mounted || generation != _saveGeneration) {
      return;
    }

    setState(() {
      _notes = _notes
          .map(
            (note) => _samePath(note.path, selected.path) ? updatedNote : note,
          )
          .toList();
      if (_samePath(_selectedNote?.path ?? '', selected.path)) {
        _selectedNote = updatedNote;
      }
      _saving = false;
      _statusText = '已保存';
    });
    if (_searchController.text.trim().isNotEmpty) {
      _scheduleSearch();
    }
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

    try {
      final result = await _noteUploadQueue.flush();
      if (!mounted || !result.attempted) {
        return;
      }
      if (result.ok) {
        setState(() {
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

  void _setEditorText(
    String value, {
    bool preserveSelection = false,
    TextSelection? initialSelection,
  }) {
    final nextSelection = initialSelection != null
        ? _selectionClampedToText(initialSelection, value)
        : preserveSelection
        ? _selectionClampedTo(value)
        : TextSelection.collapsed(offset: value.length);
    _editorController
      ..removeListener(_handleEditorChanged)
      ..text = value
      ..selection = nextSelection
      ..addListener(_handleEditorChanged);
    _editorRevision++;
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

  void _focusEditorSelectionSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading) {
        return;
      }
      _editorFocusNode.requestFocus();
      final selection = _editorController.selection;
      _editorController.selection = TextSelection.collapsed(
        offset: selection.extentOffset,
      );
      _editorController.selection = selection;
    });
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

  Future<void> _regenerateSelectedReport() async {
    final selected = _selectedNote;
    if (_loading || _regeneratingReport || selected == null) {
      return;
    }
    final kind = _kind;
    setState(() {
      _regeneratingReport = true;
      _editorMessage = null;
    });

    try {
      final result = await widget.aiClientService.regenerateReport(
        appDataDir: widget.localDataState.dataDirectory,
        config: widget.localDataState.config,
        kind: kind,
        targetPath: selected.path,
        dailyNotesDirectory: widget.localDataState.dailyNotesDirectory,
        weeklyNotesDirectory: widget.localDataState.weeklyNotesDirectory,
      );
      if (!mounted) {
        return;
      }
      if (result.ok) {
        final stillSelected =
            _kind == kind &&
            _samePath(_selectedNote?.path ?? '', selected.path);
        if (stillSelected) {
          await _loadNotes(kind: kind, selectedPath: selected.path);
          if (!mounted) {
            return;
          }
          setState(() => _editorMessage = '已重新生成');
        }
      } else {
        setState(() => _editorMessage = '重新生成失败：${result.errorMessage}');
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to regenerate report: $error\n$stackTrace');
      if (mounted) {
        setState(() => _editorMessage = '重新生成失败，请稍后重试。');
      }
    } finally {
      if (mounted) {
        setState(() => _regeneratingReport = false);
      }
    }
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

  void _handleSearchChanged() {
    _scheduleSearch();
  }

  void _scheduleSearch({bool immediate = false}) {
    final query = _searchController.text.trim();
    final generation = ++_searchGeneration;
    _searchDebounce?.cancel();
    if (query.runes.length < _minimumSearchQueryCharacters) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _searching = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _searching = true);
    }

    void start() {
      unawaited(
        _runSearch(
          generation: generation,
          kind: _kind,
          directory: _directoryFor(_kind),
          query: query,
        ),
      );
    }

    if (immediate) {
      start();
    } else {
      _searchDebounce = Timer(const Duration(milliseconds: 180), start);
    }
  }

  Future<void> _runSearch({
    required int generation,
    required NoteKind kind,
    required String directory,
    required String query,
  }) async {
    final results = await widget.noteService.searchMarkdownFiles(
      directoryPath: directory,
      kind: kind,
      query: query,
    );
    if (!mounted ||
        generation != _searchGeneration ||
        kind != _kind ||
        query != _searchController.text.trim()) {
      return;
    }
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final selected = _selectedNote;

    return Material(
      color: colors.background,
      child: Row(
        children: [
          _NotesSidebar(
            kind: _kind,
            notes: _notes,
            searchResults: _searchResults,
            searchQuery: _searchController.text.trim(),
            searching: _searching,
            selectedPath: selected?.path,
            searchController: _searchController,
            onKindChanged: (kind) => _loadNotes(kind: kind),
            onNoteSelected: _selectNote,
          ),
          Expanded(
            flex: 64,
            child: _EditorWorkspace(
              mode: _workspaceMode,
              controller: _editorController,
              editorRevision: _editorRevision,
              undoController: _editorUndoController,
              focusNode: _editorFocusNode,
              statusText: _editorStatusText,
              enabled: selected != null && !_loading && !_regeneratingReport,
              predicting: _predicting,
              markdown: _editorController.text,
              localImageBasePath: selected == null
                  ? null
                  : _parentDirectoryPath(selected.path),
              onInsertImage: _insertImageFromPicker,
              regenerating: _regeneratingReport,
              onRegenerate: _regenerateSelectedReport,
              onPointerFocus: _handleEditorPointerFocus,
              onModeChanged: _handleWorkspaceModeChanged,
            ),
          ),
        ],
      ),
    );
  }

  String? get _editorStatusText {
    if (_predicting) {
      return 'AI 编辑预测中';
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
  bool _markdownSyntaxHighlightEnabled = true;

  set markdownSyntaxHighlightEnabled(bool value) {
    if (_markdownSyntaxHighlightEnabled == value) {
      return;
    }
    _markdownSyntaxHighlightEnabled = value;
    notifyListeners();
  }

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
      if (!_markdownSyntaxHighlightEnabled) {
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
      return MarkdownEditorHighlightSpanBuilder(context).buildTextEditingValue(
        value,
        textStyle: effectiveStyle,
        withComposing: withComposing,
      );
    }

    final highlighter = MarkdownEditorHighlightSpanBuilder(
      context,
      includeBottomSpacer: false,
    );
    return TextSpan(
      style: effectiveStyle,
      children: [
        _markdownSyntaxHighlightEnabled
            ? highlighter.build(
                text.substring(0, offset),
                textStyle: effectiveStyle,
              )
            : TextSpan(text: text.substring(0, offset)),
        TextSpan(
          text: prediction,
          style: effectiveStyle.copyWith(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF7B92A8) // 深色模式：优雅的灰蓝色，与微暖文字完美搭配
                : const Color(0xFF9AA0A6), // 浅色模式：保持原有灰色
          ),
        ),
        _markdownSyntaxHighlightEnabled
            ? highlighter.build(
                text.substring(offset),
                textStyle: effectiveStyle,
              )
            : TextSpan(text: text.substring(offset)),
        _bottomSpacer(effectiveStyle),
      ],
    );
  }
}

class _NotesSidebar extends StatelessWidget {
  const _NotesSidebar({
    required this.kind,
    required this.notes,
    required this.searchResults,
    required this.searchQuery,
    required this.searching,
    required this.selectedPath,
    required this.searchController,
    required this.onKindChanged,
    required this.onNoteSelected,
  });

  final NoteKind kind;
  final List<NoteFile> notes;
  final List<NoteFile> searchResults;
  final String searchQuery;
  final bool searching;
  final String? selectedPath;
  final TextEditingController searchController;
  final ValueChanged<NoteKind> onKindChanged;
  final ValueChanged<NoteFile> onNoteSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      width: 278,
      padding: const EdgeInsets.fromLTRB(18, 24, 14, 20),
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(right: BorderSide(color: colors.divider)),
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
                  color: colors.surfaceMuted,
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
          _NotesSearchField(
            controller: searchController,
            hintText: '搜索全部${kind.label}...',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: searchQuery.isNotEmpty
                ? _FilteredNoteList(
                    results: searchResults,
                    query: searchQuery,
                    searching: searching,
                    selectedPath: selectedPath,
                    onNoteSelected: onNoteSelected,
                  )
                : notes.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配的便签',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : _NoteList(
                    notes: notes,
                    selectedPath: selectedPath,
                    onNoteSelected: onNoteSelected,
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilteredNoteList extends StatelessWidget {
  const _FilteredNoteList({
    required this.results,
    required this.query,
    required this.searching,
    required this.selectedPath,
    required this.onNoteSelected,
  });

  final List<NoteFile> results;
  final String query;
  final bool searching;
  final String? selectedPath;
  final ValueChanged<NoteFile> onNoteSelected;

  @override
  Widget build(BuildContext context) {
    if (query.runes.length < 2) {
      return Center(
        child: Text(
          '至少输入 2 个字符',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          searching ? '正在搜索...' : '没有匹配内容',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return _NoteList(
      notes: results,
      selectedPath: selectedPath,
      onNoteSelected: onNoteSelected,
    );
  }
}

class _NoteList extends StatelessWidget {
  const _NoteList({
    required this.notes,
    required this.selectedPath,
    required this.onNoteSelected,
  });

  final List<NoteFile> notes;
  final String? selectedPath;
  final ValueChanged<NoteFile> onNoteSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: notes.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final note = notes[index];
        return _NoteListItem(
          key: ValueKey(note.path),
          note: note,
          selected: _sameDisplayPath(note.path, selectedPath),
          onTap: () => onNoteSelected(note),
        );
      },
    );
  }

  bool _sameDisplayPath(String path, String? other) {
    if (other == null) {
      return false;
    }
    return path.replaceAll('\\', '/').toLowerCase() ==
        other.replaceAll('\\', '/').toLowerCase();
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
      child: Semantics(
        label: '切换日报/周报/月报',
        button: true,
        child: SpringNoteIconButton(
          icon: Icons.more_horiz,
          onPressed: _toggleOverlay,
        ),
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
    final colors = AppTheme.colors(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: AppTheme.menuSurface(context),
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.08),
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
                  color: colors.textSubtle,
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
    final colors = AppTheme.colors(context);
    final active = selected || hovered;
    final backgroundColor = selected
        ? colors.surfacePressed
        : colors.surfaceHover;
    final contentColor = active ? colors.text : colors.textMuted;
    final iconColor = active ? colors.text : colors.textSubtle;
    final subtleColor = colors.textSubtle;
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
                          borderRadius: BorderRadius.circular(13),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                bottom: 4,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: contentColor),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, animatedContentColor, _) {
                    return TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: iconColor),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      builder: (context, animatedIconColor, _) {
                        final titleStyle = Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: animatedContentColor ?? contentColor,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              height: 1.1,
                            );
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Icon(
                                _iconForKind(kind),
                                size: 17,
                                color: animatedIconColor ?? iconColor,
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
                                Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: colors.text,
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
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
  const _NotesSearchField({required this.controller, required this.hintText});

  final TextEditingController controller;
  final String hintText;

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
    final colors = AppTheme.colors(context);
    final focused = _focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      height: 40,
      decoration: BoxDecoration(
        color: focused ? colors.inputFocusedFill : colors.inputFill,
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
          ).textTheme.bodyMedium?.copyWith(color: colors.text, height: 1.2),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textSubtle.withValues(alpha: 0.78),
              height: 1.2,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color: colors.textSubtle,
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
    super.key,
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
    final colors = AppTheme.colors(context);
    final backgroundColor = widget.selected
        ? colors.surfacePressed
        : colors.surfaceHover;
    final active = widget.selected || _hovered;
    final titleColor = active ? colors.text : colors.textMuted;
    final secondaryColor = colors.textSubtle;

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

class _EditorWorkspace extends StatefulWidget {
  const _EditorWorkspace({
    required this.mode,
    required this.controller,
    required this.editorRevision,
    required this.undoController,
    required this.focusNode,
    required this.statusText,
    required this.enabled,
    required this.predicting,
    required this.markdown,
    required this.localImageBasePath,
    required this.onInsertImage,
    required this.regenerating,
    required this.onRegenerate,
    required this.onPointerFocus,
    required this.onModeChanged,
  });

  final _EditorWorkspaceMode mode;
  final TextEditingController controller;
  final int editorRevision;
  final UndoHistoryController undoController;
  final FocusNode focusNode;
  final String? statusText;
  final bool enabled;
  final bool predicting;
  final String markdown;
  final String? localImageBasePath;
  final VoidCallback onInsertImage;
  final bool regenerating;
  final VoidCallback onRegenerate;
  final VoidCallback onPointerFocus;
  final ValueChanged<_EditorWorkspaceMode> onModeChanged;

  @override
  State<_EditorWorkspace> createState() => _EditorWorkspaceState();
}

class _EditorWorkspaceState extends State<_EditorWorkspace> {
  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _previewScrollController = ScrollController();

  @override
  void dispose() {
    _editorScrollController.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return _PaneFrame(
      headerHeight: 42,
      headerPadding: const EdgeInsets.only(left: 24, right: 12),
      header: _EditorWorkspaceHeader(
        statusText: widget.statusText,
        insertImageEnabled: widget.enabled,
        onInsertImage: widget.onInsertImage,
        regenerateEnabled: widget.enabled,
        regenerating: widget.regenerating,
        onRegenerate: widget.onRegenerate,
        mode: widget.mode,
        onModeChanged: widget.onModeChanged,
      ),
      child: _buildBody(colors),
    );
  }

  Widget _buildBody(SpringThemeColors colors) {
    final editor = _EditorContent(
      controller: widget.controller,
      editorRevision: widget.editorRevision,
      undoController: widget.undoController,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      onPointerFocus: widget.onPointerFocus,
      scrollController: _editorScrollController,
    );
    final preview = _PreviewContent(
      markdown: widget.markdown,
      localImageBasePath: widget.localImageBasePath,
      scrollController: _previewScrollController,
      padding: widget.mode == _EditorWorkspaceMode.split
          ? const EdgeInsets.fromLTRB(32, _notesEditorTopContentPadding, 32, 56)
          : const EdgeInsets.fromLTRB(32, 20, 32, 56),
    );

    return switch (widget.mode) {
      _EditorWorkspaceMode.edit => editor,
      _EditorWorkspaceMode.preview => preview,
      _EditorWorkspaceMode.split => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: editor),
          Container(width: 1, color: colors.divider),
          Expanded(child: preview),
        ],
      ),
    };
  }
}

class _EditorWorkspaceHeader extends StatelessWidget {
  const _EditorWorkspaceHeader({
    required this.statusText,
    required this.insertImageEnabled,
    required this.onInsertImage,
    required this.regenerateEnabled,
    required this.regenerating,
    required this.onRegenerate,
    required this.mode,
    required this.onModeChanged,
  });

  final String? statusText;
  final bool insertImageEnabled;
  final VoidCallback onInsertImage;
  final bool regenerateEnabled;
  final bool regenerating;
  final VoidCallback onRegenerate;
  final _EditorWorkspaceMode mode;
  final ValueChanged<_EditorWorkspaceMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 240,
          child: statusText == null
              ? const SizedBox.shrink()
              : _EditorStatusPill(statusText: statusText!),
        ),
        const Spacer(),
        _EditorHeaderIconButton(
          tooltip: '插入图片',
          icon: Icons.image_outlined,
          onPressed: insertImageEnabled ? onInsertImage : null,
        ),
        const SizedBox(width: 8),
        _EditorHeaderIconButton(
          tooltip: '重新生成',
          icon: Icons.auto_awesome_outlined,
          iconSize: 14,
          loading: regenerating,
          onPressed: regenerateEnabled && !regenerating ? onRegenerate : null,
        ),
        const SizedBox(width: 8),
        _WorkspaceModeSegmentedControl(value: mode, onChanged: onModeChanged),
      ],
    );
  }
}

class _EditorHeaderIconButton extends StatelessWidget {
  const _EditorHeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 16,
    this.loading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: IconButton(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.textSubtle,
                ),
              )
            : Icon(icon, size: iconSize),
        color: colors.textSubtle,
        style: IconButton.styleFrom(
          fixedSize: const Size(30, 30),
          minimumSize: const Size(30, 30),
          maximumSize: const Size(30, 30),
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          hoverColor: colors.surfaceMuted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }
}

class _EditorContent extends StatelessWidget {
  const _EditorContent({
    required this.controller,
    required this.editorRevision,
    required this.undoController,
    required this.focusNode,
    required this.enabled,
    required this.onPointerFocus,
    required this.scrollController,
  });

  final TextEditingController controller;
  final int editorRevision;
  final UndoHistoryController undoController;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onPointerFocus;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final editorStyle =
        Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: colors.text,
          fontSize: _notesEditorBodyFontSize,
          height: 1.55,
        ) ??
        TextStyle(
          color: colors.text,
          fontSize: _notesEditorBodyFontSize,
          height: 1.55,
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideInset = constraints.maxWidth > 720
            ? (constraints.maxWidth - 720) / 2 + 40
            : 40.0;

        return Stack(
          children: [
            Positioned.fill(
              child: Scrollbar(
                controller: scrollController,
                child: ScrollConfiguration(
                  behavior: const _EditorTextFieldScrollBehavior(),
                  child: TextSelectionTheme(
                    data: TextSelectionTheme.of(context).copyWith(
                      cursorColor: colors.textMuted,
                      selectionColor: colors.textSubtle.withValues(alpha: 0.28),
                      selectionHandleColor: colors.textSubtle,
                    ),
                    child: TextField(
                      key: ValueKey('note-editor-$editorRevision'),
                      controller: controller,
                      undoController: undoController,
                      focusNode: focusNode,
                      onTap: onPointerFocus,
                      scrollController: scrollController,
                      enabled: enabled,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: '# 开始编辑 Markdown...',
                        hintStyle: TextStyle(
                          color: colors.textSubtle.withValues(alpha: 0.58),
                        ),
                        filled: true,
                        fillColor: colors.background,
                        hoverColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(
                          sideInset,
                          _notesEditorTopContentPadding,
                          sideInset / 2,
                          0,
                        ),
                      ),
                      style: editorStyle,
                      cursorColor: colors.textMuted,
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
    final colors = AppTheme.colors(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final displayText = switch (statusText) {
      _ => statusText,
    };
    final highlighted =
        statusText == '已重新生成' ||
        statusText == 'AI 实时补全已就绪' ||
        statusText == 'AI 编辑预测中' ||
        statusText.startsWith('Tab ');
    final foreground = highlighted
        ? (dark ? const Color(0xFF34D399) : const Color(0xFF10B981))
        : colors.textSubtle;
    final background = highlighted
        ? (dark ? const Color(0xFF0B3024) : const Color(0xFFECFDF5))
        : colors.surfaceMuted;

    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: displayText,
        waitDuration: const Duration(milliseconds: 500),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
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
              Flexible(
                child: Text(
                  displayText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
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

class _WorkspaceModeSegmentedControl extends StatelessWidget {
  const _WorkspaceModeSegmentedControl({
    required this.value,
    required this.onChanged,
  });

  final _EditorWorkspaceMode value;
  final ValueChanged<_EditorWorkspaceMode> onChanged;

  static const _options = [
    _EditorWorkspaceMode.edit,
    _EditorWorkspaceMode.split,
    _EditorWorkspaceMode.preview,
  ];

  static const _labels = {
    _EditorWorkspaceMode.edit: '编辑',
    _EditorWorkspaceMode.split: '分栏',
    _EditorWorkspaceMode.preview: '预览',
  };

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final textStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 1.2,
        ) ??
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.2);
    final textDirection = Directionality.of(context);
    const textScaler = TextScaler.noScaling;
    final borderColor = colors.border.a == 0
        ? colors.border
        : colors.border.withValues(alpha: 0.30);
    final highlightColor = Theme.of(context).brightness == Brightness.dark
        ? colors.surface
        : Colors.white;
    final selectedIndex = _options.indexOf(value);
    const horizontalPadding = 12.0;
    const verticalPadding = 4.0;
    const outerPadding = 2.0;
    const borderWidth = 1.0;
    const gap = 4.0;
    final segmentWidths = [
      for (final option in _options)
        _measureTextWidth(
              label: _labels[option]!,
              style: textStyle,
              textDirection: textDirection,
              textScaler: textScaler,
            ) +
            horizontalPadding * 2,
    ];
    final selectedLeft = selectedIndex <= 0
        ? 0.0
        : segmentWidths
                  .take(selectedIndex)
                  .fold(0.0, (sum, width) => sum + width) +
              gap * selectedIndex;
    final innerWidth =
        segmentWidths.fold(0.0, (sum, width) => sum + width) +
        gap * (_options.length - 1);
    final controlWidth = innerWidth + outerPadding * 2 + borderWidth * 2;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: SizedBox(
        width: controlWidth,
        height: 28,
        child: Container(
          padding: const EdgeInsets.all(outerPadding),
          decoration: BoxDecoration(
            color: colors.surfaceMuted.withValues(alpha: 0.60),
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: selectedLeft,
                top: 0,
                bottom: 0,
                width: segmentWidths[selectedIndex],
                child: Container(
                  decoration: BoxDecoration(
                    color: highlightColor,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: 0.12),
                        blurRadius: 7,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, option) in _options.indexed) ...[
                    SizedBox(
                      width: segmentWidths[index],
                      child: _WorkspaceModeSegment(
                        mode: option,
                        label: _labels[option]!,
                        selected: option == value,
                        textStyle: textStyle,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                        onTap: () => onChanged(option),
                      ),
                    ),
                    if (index != _options.length - 1)
                      const SizedBox(width: gap),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _measureTextWidth({
    required String label,
    required TextStyle style,
    required TextDirection textDirection,
    required TextScaler textScaler,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      maxLines: 1,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();
    return painter.width;
  }
}

class _WorkspaceModeSegment extends StatelessWidget {
  const _WorkspaceModeSegment({
    required this.mode,
    required this.label,
    required this.selected,
    required this.textStyle,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.onTap,
  });

  final _EditorWorkspaceMode mode;
  final String label;
  final bool selected;
  final TextStyle textStyle;
  final double horizontalPadding;
  final double verticalPadding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('notes-workspace-mode-${mode.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 140),
              style: textStyle.copyWith(
                color: selected ? colors.text : colors.textSubtle,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({
    required this.markdown,
    required this.localImageBasePath,
    required this.scrollController,
    required this.padding,
  });

  final String markdown;
  final String? localImageBasePath;
  final ScrollController scrollController;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return MarkdownPreview(
      markdown: markdown,
      localImageBasePath: localImageBasePath,
      scrollController: scrollController,
      padding: padding,
    );
  }
}

class _PaneFrame extends StatelessWidget {
  const _PaneFrame({
    required this.header,
    required this.child,
    this.headerHeight = 56,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 24),
  });

  final Widget header;
  final Widget child;
  final double headerHeight;
  final EdgeInsetsGeometry headerPadding;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(left: BorderSide(color: colors.divider)),
      ),
      child: Column(
        children: [
          Container(
            height: headerHeight,
            padding: headerPadding,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: header,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
