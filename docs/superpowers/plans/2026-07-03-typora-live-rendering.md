# Typora-Style Live Markdown Rendering Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a Typora-style live markdown rendering mode with a full-width preview and slide-up editor overlay.

**Architecture:** Add `_typoraMode` state to `_NotesPageState`. When active, replace the split editor+preview layout with a full-width `_TyporaPane` containing a `_PreviewPane`, a FAB for toggling a slide-up `_EditorPane` overlay. Reuse existing `_editorController` and `_saveEditorText` for auto-save.

**Tech Stack:** Flutter/Dart with `SpringNoteIconButton`, `FloatingActionButton.small`, `AnimatedPositioned`

## Global Constraints

- All changes confined to `spring_note/lib/features/notes/notes_page.dart`
- Use existing private widgets (`_PreviewPane`, `_EditorPane`, `_NotesSidebar`)
- Use existing `SpringNoteIconButton` from `page_scaffold.dart`
- No changes to `markdown_preview.dart`
- No mode persistence across sessions
- Sidebar stays visible in both modes

---

### Task 1: Add Typora mode state and toggle methods

**Files:**
- Modify: `spring_note/lib/features/notes/notes_page.dart:83-85` — add state vars
- Modify: `spring_note/lib/features/notes/notes_page.dart:980` — add toggle methods

- [ ] **Step 1: Add state variables after line 82**

After `bool _editorFocusedByPointer = false;`, add:
```dart
bool _typoraMode = false;
bool _typoraEditOverlayOpen = false;
```

- [ ] **Step 2: Add toggle methods before `build()`**

Before the `build()` method (after `_filteredNotes` getter), add:
```dart
void _toggleTyporaMode() {
  setState(() {
    _typoraMode = !_typoraMode;
    if (!_typoraMode) {
      _typoraEditOverlayOpen = false;
    }
  });
}

void _toggleTyporaEditOverlay() {
  setState(() {
    _typoraEditOverlayOpen = !_typoraEditOverlayOpen;
  });
}
```

### Task 2: Modify `_PreviewPane` to accept Typora mode params

**Files:**
- Modify: `spring_note/lib/features/notes/notes_page.dart:1958-1996` — add params and toggle button

- [ ] **Step 1: Add `typoraMode` and `onToggleTyporaMode` params to `_PreviewPane`**

```dart
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.markdown,
    required this.localImageBasePath,
    this.typoraMode = false,
    this.onToggleTyporaMode,
  });

  final String markdown;
  final String? localImageBasePath;
  final bool typoraMode;
  final VoidCallback? onToggleTyporaMode;
```

- [ ] **Step 2: Add toggle button to the header**

Replace the `Spacer()` + `Icon(Icons.open_in_full_rounded...)` with:
```dart
const Spacer(),
SpringNoteIconButton(
  tooltip: typoraMode ? '退出实时渲染模式' : '实时渲染模式',
  icon: Icons.remove_red_eye_outlined,
  onPressed: onToggleTyporaMode,
),
const SizedBox(width: 8),
const Icon(
  Icons.open_in_full_rounded,
  size: 15,
  color: AppTheme.textSubtle,
),
```

### Task 3: Modify `build()` to switch layouts

**Files:**
- Modify: `spring_note/lib/features/notes/notes_page.dart:982-1021`

- [ ] **Step 1: Replace the build() body with conditional layout**

Replace the existing `build()` body so that when `_typoraMode` is true, a `_TyporaPane` replaces the editor+preview split:

```dart
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
          child: _typoraMode
              ? _TyporaPane(
                  markdown: _editorController.text,
                  localImageBasePath: selected == null
                      ? null
                      : _parentDirectoryPath(selected.path),
                  editOverlayOpen: _typoraEditOverlayOpen,
                  onToggleEditOverlay: _toggleTyporaEditOverlay,
                  controller: _editorController,
                  focusNode: _editorFocusNode,
                  statusText: _editorStatusText,
                  enabled: selected != null && !_loading,
                  predicting: _predicting,
                  onInsertImage: _insertImageFromPicker,
                  onPointerFocus: _handleEditorPointerFocus,
                  onToggleTyporaMode: _toggleTyporaMode,
                )
              : Row(
                  children: [
                    Expanded(
                      flex: 32,
                      child: _EditorPane(
                        controller: _editorController,
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
        ),
      ],
    ),
  );
}
```

### Task 4: Create `_TyporaPane` widget

**Files:**
- Create: `spring_note/lib/features/notes/notes_page.dart` (after `_PreviewPane`, before `_PaneFrame`)

- [ ] **Step 1: Add the `_TyporaPane` StatefulWidget**

Add after `_PreviewPane` (after line ~1996):
```dart
class _TyporaPane extends StatelessWidget {
  const _TyporaPane({
    required this.markdown,
    required this.localImageBasePath,
    required this.editOverlayOpen,
    required this.onToggleEditOverlay,
    required this.controller,
    required this.focusNode,
    required this.statusText,
    required this.enabled,
    required this.predicting,
    required this.onInsertImage,
    required this.onPointerFocus,
    required this.onToggleTyporaMode,
  });

  final String markdown;
  final String? localImageBasePath;
  final bool editOverlayOpen;
  final VoidCallback onToggleEditOverlay;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String statusText;
  final bool enabled;
  final bool predicting;
  final VoidCallback onInsertImage;
  final VoidCallback onPointerFocus;
  final VoidCallback onToggleTyporaMode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final overlayHeight = constraints.maxHeight * 0.4;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Full-width preview
            Positioned.fill(
              child: _PreviewPane(
                markdown: markdown,
                localImageBasePath: localImageBasePath,
                typoraMode: true,
                onToggleTyporaMode: onToggleTyporaMode,
              ),
            ),

            // Slide-up edit overlay
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: 0,
              height: editOverlayOpen ? overlayHeight : 0,
              child: SizedBox(
                height: overlayHeight,
                child: Material(
                  elevation: 8,
                  color: Colors.white,
                  child: _EditorPane(
                    controller: controller,
                    focusNode: focusNode,
                    statusText: statusText,
                    enabled: enabled,
                    predicting: predicting,
                    onInsertImage: onInsertImage,
                    onPointerFocus: onPointerFocus,
                  ),
                ),
              ),
            ),

            // FAB
            Positioned(
              right: 24,
              bottom: editOverlayOpen ? overlayHeight + 24 : 24,
              child: FloatingActionButton.small(
                onPressed: onToggleEditOverlay,
                backgroundColor: const Color(0xFF3A3A3A),
                child: Icon(
                  editOverlayOpen ? Icons.close : Icons.edit_outlined,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
```

### Task 5: Git operations

- [ ] **Step 1: Create branch**
```bash
git checkout -b feat/typora-live-rendering
```

- [ ] **Step 2: Commit**
```bash
git add spring_note/lib/features/notes/notes_page.dart
git commit -m "feat: implement Typora-style live markdown rendering mode (#68)"
```

- [ ] **Step 3: Push**
```bash
git push origin feat/typora-live-rendering
```

- [ ] **Step 4: Create PR**
```bash
gh pr create --repo radiant303/springnote --base main --head feat/typora-live-rendering --title "feat: implement Typora-style live markdown rendering mode" --body "Closes #68

## 实现内容

实现了 Typora 风格的实时 Markdown 渲染模式，用户可以通过切换按钮在分栏编辑模式和实时渲染模式之间切换。

### 主要改动
- 在预览面板标题栏添加了 Typora 模式切换按钮
- 实现全宽预览的实时渲染模式
- 点击编辑按钮弹出编辑器面板
- 保留侧边栏和自动保存功能

### 使用方法
1. 在预览面板顶部点击 👁️ 图标切换到 Typora 模式
2. 预览区域占据全宽显示渲染效果
3. 点击右下角 ✏️ 按钮编辑文档内容
4. 再次点击 👁️ 图标切换回分栏模式"
```
