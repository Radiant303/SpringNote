import 'dart:collection';

import '../models/local_data_state.dart';
import 'cloud_sync_service.dart';

class NoteUploadFlushResult {
  const NoteUploadFlushResult({
    required this.ok,
    required this.attempted,
    this.uploaded = 0,
    this.message = '',
  });

  final bool ok;
  final bool attempted;
  final int uploaded;
  final String message;

  static const idle = NoteUploadFlushResult(ok: true, attempted: false);
}

class NoteUploadQueue {
  NoteUploadQueue({required this.cloudSyncService});

  final CloudSyncService cloudSyncService;
  final LinkedHashMap<String, String> _pendingPaths = LinkedHashMap();

  LocalDataState? _localDataState;
  Future<NoteUploadFlushResult>? _activeFlush;

  bool get hasPendingUploads => _pendingPaths.isNotEmpty;

  void attach(LocalDataState localDataState) {
    final previousDirectory = _localDataState?.dataDirectory;
    _localDataState = localDataState;
    if (previousDirectory != null &&
        _pathKey(previousDirectory) != _pathKey(localDataState.dataDirectory)) {
      _pendingPaths.clear();
    }
  }

  void markDirty(String notePath) {
    final trimmed = notePath.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _pendingPaths[_pathKey(trimmed)] = trimmed;
  }

  Future<NoteUploadFlushResult> flush() {
    final activeFlush = _activeFlush;
    if (activeFlush != null) {
      return activeFlush.then((result) {
        if (_pendingPaths.isEmpty) {
          return result;
        }
        return flush();
      });
    }

    late final Future<NoteUploadFlushResult> flushFuture;
    flushFuture = _flushPending().whenComplete(() {
      if (identical(_activeFlush, flushFuture)) {
        _activeFlush = null;
      }
    });
    _activeFlush = flushFuture;
    return flushFuture;
  }

  Future<NoteUploadFlushResult> _flushPending() async {
    final localDataState = _localDataState;
    if (localDataState == null || !_autoCloudSyncAvailable(localDataState)) {
      return NoteUploadFlushResult.idle;
    }

    var attempted = false;
    var uploaded = 0;
    var lastMessage = '';

    while (_pendingPaths.isNotEmpty) {
      final state = _localDataState;
      if (state == null || !_autoCloudSyncAvailable(state)) {
        return NoteUploadFlushResult(
          ok: true,
          attempted: attempted,
          uploaded: uploaded,
          message: lastMessage,
        );
      }

      final entry = _pendingPaths.entries.first;
      _pendingPaths.remove(entry.key);
      attempted = true;

      final CloudSyncResult result;
      try {
        result = await cloudSyncService.uploadNote(
          localDataState: state,
          notePath: entry.value,
        );
      } catch (_) {
        _pendingPaths[entry.key] = entry.value;
        return NoteUploadFlushResult(
          ok: false,
          attempted: true,
          uploaded: uploaded,
          message: '自动同步失败，请稍后重试。',
        );
      }

      if (!result.ok) {
        _pendingPaths[entry.key] = entry.value;
        return NoteUploadFlushResult(
          ok: false,
          attempted: true,
          uploaded: uploaded,
          message: result.message,
        );
      }

      uploaded += result.uploaded;
      if (result.message.isNotEmpty) {
        lastMessage = result.message;
      }
    }

    return NoteUploadFlushResult(
      ok: true,
      attempted: attempted,
      uploaded: uploaded,
      message: lastMessage,
    );
  }

  bool _autoCloudSyncAvailable(LocalDataState state) {
    final sync = state.config.cloudSync;
    return sync.enabled && sync.realTimeSync && sync.hasRequiredFields;
  }

  String _pathKey(String path) {
    final normalized = path.trim().replaceAll(r'\', '/');
    final withoutTrailingSlashes = normalized.replaceFirst(RegExp(r'/+$'), '');
    if (RegExp(r'^[A-Za-z]:/').hasMatch(withoutTrailingSlashes)) {
      return withoutTrailingSlashes.toLowerCase();
    }
    return withoutTrailingSlashes;
  }
}
