import 'package:flutter/material.dart';

import '../../core/models/local_data_state.dart';
import '../../core/models/note_file.dart';
import '../../core/services/note_service.dart';
import '../../core/theme/app_theme.dart';
import 'markdown_preview.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({
    super.key,
    required this.localDataState,
    this.noteService = const NoteService(),
  });

  final LocalDataState localDataState;
  final NoteService noteService;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final TextEditingController _editorController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  NoteKind _kind = NoteKind.daily;
  List<NoteFile> _notes = [];
  NoteFile? _selectedNote;
  bool _loading = true;
  bool _saving = false;
  String _statusText = '正在加载';

  @override
  void initState() {
    super.initState();
    _editorController.addListener(_handleEditorChanged);
    _searchController.addListener(() => setState(() {}));
    _loadNotes(kind: _kind);
  }

  @override
  void dispose() {
    _editorController
      ..removeListener(_handleEditorChanged)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes({
    required NoteKind kind,
    String? selectedPath,
  }) async {
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
    if (notes.isEmpty) {
      final current = await widget.noteService.ensureCurrentMarkdownFile(
        directoryPath: directory,
        kind: kind,
      );
      notes = [current];
    }

    final selected = selectedPath == null
        ? notes.first
        : notes.firstWhere(
            (note) => note.path == selectedPath,
            orElse: () => notes.first,
          );
    final content = await widget.noteService.readMarkdown(selected.path);

    if (!mounted) {
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

  Future<void> _handleEditorChanged() async {
    final selected = _selectedNote;
    if (_loading || selected == null) {
      return;
    }

    setState(() {
      _saving = true;
      _statusText = '保存中';
    });

    await widget.noteService.writeMarkdown(
      selected.path,
      _editorController.text,
    );
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
  }

  void _setEditorText(String value) {
    _editorController
      ..removeListener(_handleEditorChanged)
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length)
      ..addListener(_handleEditorChanged);
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
              note.preview.toLowerCase().contains(query),
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 10, 24),
              child: _EditorPane(
                controller: _editorController,
                statusText: _saving ? '保存中' : _statusText,
                enabled: selected != null && !_loading,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 24, 24, 24),
              child: _PreviewPane(markdown: _editorController.text),
            ),
          ),
        ],
      ),
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
        border: Border(right: BorderSide(color: Color(0xFFEEF2F7))),
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
                  color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  kind.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const Spacer(),
              PopupMenuButton<NoteKind>(
                tooltip: '切换日报/周报/月报',
                icon: const Icon(Icons.more_horiz_rounded, size: 19),
                onSelected: onKindChanged,
                itemBuilder: (context) => [
                  for (final item in NoteKind.values)
                    PopupMenuItem(value: item, child: Text(item.label)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: searchController,
            decoration: const InputDecoration(
              hintText: '搜索知识记录...',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
            ),
          ),
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
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final background = widget.selected
        ? const Color(0xFFF1F5F9).withValues(alpha: 0.8)
        : _hovering
        ? const Color(0xFFF1F5F9).withValues(alpha: 0.6)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
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
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: widget.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatModified(widget.note.modifiedAt),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSubtle,
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: widget.selected
                      ? AppTheme.textMuted
                      : AppTheme.textSubtle,
                  fontSize: 12,
                ),
              ),
            ],
          ),
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

class _EditorPane extends StatelessWidget {
  const _EditorPane({
    required this.controller,
    required this.statusText,
    required this.enabled,
  });

  final TextEditingController controller;
  final String statusText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _PaneFrame(
      header: Row(
        children: [
          const Icon(Icons.code_rounded, size: 16, color: AppTheme.textSubtle),
          const SizedBox(width: 8),
          Text(
            'Markdown Source · 源码编辑',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSubtle,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          Text(statusText, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        expands: true,
        maxLines: null,
        minLines: null,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          hintText: '# 开始编辑 Markdown...',
          filled: true,
          fillColor: Colors.white,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(26, 24, 26, 24),
        ),
        style: const TextStyle(
          color: AppTheme.text,
          fontFamily: 'Consolas',
          fontSize: 14,
          height: 1.75,
        ),
      ),
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    return _PaneFrame(
      header: Row(
        children: [
          Text(
            'Markdown Preview · 渲染预览',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSubtle,
              fontWeight: FontWeight.w700,
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
      child: MarkdownPreview(markdown: markdown),
    );
  }
}

class _PaneFrame extends StatelessWidget {
  const _PaneFrame({required this.header, required this.child});

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEEF2F7)),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: header,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
