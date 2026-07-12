import 'dart:io';

import '../../src/rust/api/note_index_api.dart' as rust_api;
import '../../src/rust/note_index.dart' as rust_model;
import '../models/note_file.dart';
import 'note_service.dart';

class IndexedNoteService extends NoteService {
  const IndexedNoteService();

  @override
  Future<List<NoteFile>> listMarkdownFiles({
    required String directoryPath,
    required NoteKind kind,
  }) async {
    final result = await rust_api.listIndexedNotes(
      directoryPath: directoryPath,
      kind: kind.name,
    );
    if (!result.ok) {
      return super.listMarkdownFiles(directoryPath: directoryPath, kind: kind);
    }
    return result.notes.map((note) => _noteFromRust(note, kind)).toList();
  }

  @override
  Future<NoteFile> ensureCurrentMarkdownFile({
    required String directoryPath,
    required NoteKind kind,
    DateTime? now,
  }) async {
    final note = await super.ensureCurrentMarkdownFile(
      directoryPath: directoryPath,
      kind: kind,
      now: now,
    );
    await indexMarkdownFile(
      directoryPath: directoryPath,
      kind: kind,
      notePath: note.path,
    );
    return note;
  }

  @override
  Future<String> readMarkdown(String path) async {
    final result = await rust_api.loadNoteContent(
      directoryPath: File(path).parent.path,
      notePath: path,
    );
    if (!result.ok) {
      return super.readMarkdown(path);
    }
    return result.content;
  }

  @override
  Future<bool> refreshMarkdownIndex({
    required String directoryPath,
    required NoteKind kind,
  }) async {
    final result = await rust_api.refreshNoteIndex(
      directoryPath: directoryPath,
      kind: kind.name,
    );
    return result.ok && (result.indexedCount > 0 || result.removedCount > 0);
  }

  @override
  Future<void> indexMarkdownFile({
    required String directoryPath,
    required NoteKind kind,
    required String notePath,
  }) async {
    await rust_api.indexNoteFile(
      directoryPath: directoryPath,
      kind: kind.name,
      notePath: notePath,
    );
  }

  @override
  Future<List<NoteSearchFile>> searchMarkdownFiles({
    required String directoryPath,
    required NoteKind kind,
    required String query,
  }) async {
    final result = await rust_api.searchIndexedNotes(
      directoryPath: directoryPath,
      kind: kind.name,
      query: query,
    );
    if (!result.ok) {
      return super.searchMarkdownFiles(
        directoryPath: directoryPath,
        kind: kind,
        query: query,
      );
    }
    return result.files
        .map(
          (file) => NoteSearchFile(
            note: _noteFromRust(file.note, kind),
            matches: file.matches
                .map(
                  (match) => NoteSearchLine(
                    lineNumber: match.lineNumber,
                    lineText: match.lineText,
                    matchStart: match.matchStartUtf16,
                    matchEnd: match.matchEndUtf16,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  NoteFile _noteFromRust(rust_model.NoteIndexEntry note, NoteKind kind) {
    return NoteFile(
      path: note.path,
      name: note.name,
      title: note.title,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(note.modifiedMillis),
      kind: kind,
      preview: note.preview,
    );
  }
}
