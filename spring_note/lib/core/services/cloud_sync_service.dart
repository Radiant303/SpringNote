import '../../src/rust/api/cloud_sync_api.dart' as rust_api;
import '../../src/rust/cloud_sync.dart' as rust_model;
import '../models/cloud_sync_config.dart';
import '../models/local_data_state.dart';
import 'note_storage_coordinator.dart';

enum CloudSyncTrigger { manual, startup }

class CloudSyncDeleteModifyConflict {
  const CloudSyncDeleteModifyConflict({
    required this.relativePath,
    required this.direction,
  });

  final String relativePath;
  final String direction;

  factory CloudSyncDeleteModifyConflict.fromRust(
    rust_model.DeleteModifyConflict conflict,
  ) {
    return CloudSyncDeleteModifyConflict(
      relativePath: conflict.relativePath,
      direction: conflict.direction,
    );
  }
}

class CloudSyncResult {
  const CloudSyncResult({
    required this.ok,
    required this.message,
    this.uploaded = 0,
    this.downloaded = 0,
    this.conflicts = 0,
    this.syncedAt,
    this.errorCode = '',
    this.needsDeleteConfirmation = false,
    this.pendingDeleteLocal = const [],
    this.pendingDeleteRemote = const [],
    this.needsDeleteModifyConfirmation = false,
    this.pendingDeleteModifyConflicts = const [],
  });

  final bool ok;
  final String message;
  final int uploaded;
  final int downloaded;
  final int conflicts;
  final DateTime? syncedAt;
  final String errorCode;
  final bool needsDeleteConfirmation;
  final List<String> pendingDeleteLocal;
  final List<String> pendingDeleteRemote;
  final bool needsDeleteModifyConfirmation;
  final List<CloudSyncDeleteModifyConflict> pendingDeleteModifyConflicts;

  factory CloudSyncResult.fromRust(rust_model.CloudSyncResult result) {
    return CloudSyncResult(
      ok: result.ok,
      message: _normalizeMessage(result.message),
      uploaded: result.uploaded,
      downloaded: result.downloaded,
      conflicts: result.conflicts,
      syncedAt: result.syncedAt.isEmpty
          ? null
          : DateTime.tryParse(result.syncedAt),
      errorCode: result.errorCode,
      needsDeleteConfirmation: result.needsDeleteConfirmation,
      pendingDeleteLocal: List.unmodifiable(result.pendingDeleteLocal),
      pendingDeleteRemote: List.unmodifiable(result.pendingDeleteRemote),
      needsDeleteModifyConfirmation: result.needsDeleteModifyConfirmation,
      pendingDeleteModifyConflicts: List.unmodifiable(
        result.pendingDeleteModifyConflicts.map(
          CloudSyncDeleteModifyConflict.fromRust,
        ),
      ),
    );
  }

  static String _normalizeMessage(String message) {
    return message.replaceAll(': ', '：').replaceAll(', ', '，');
  }
}

class CloudSyncService {
  const CloudSyncService({this.api = const CloudSyncRustApi()});

  final CloudSyncRustApi api;

  Future<CloudSyncResult> testConnection(CloudSyncConfig config) async {
    final result = await api.testConnection(_rustConfig(config));
    return CloudSyncResult.fromRust(result);
  }

  Future<CloudSyncResult> sync({
    required LocalDataState localDataState,
    required CloudSyncTrigger trigger,
    List<String> confirmedDeleteLocal = const [],
    List<String> confirmedDeleteRemote = const [],
    List<String> confirmedOverwriteLocal = const [],
    List<String> confirmedOverwriteRemote = const [],
    List<String> skippedDeleteModifyConflicts = const [],
  }) async {
    return _runExclusive(localDataState.dataDirectory, () async {
      final config = localDataState.config.cloudSync;
      final result = await api.sync(
        rust_model.CloudSyncRequest(
          config: _rustConfig(config),
          dataDirectory: localDataState.dataDirectory,
          dailyNotesDirectory: localDataState.dailyNotesDirectory,
          weeklyNotesDirectory: localDataState.weeklyNotesDirectory,
          monthlyNotesDirectory: localDataState.monthlyNotesDirectory,
          trigger: trigger.name,
          confirmedDeleteLocal: confirmedDeleteLocal,
          confirmedDeleteRemote: confirmedDeleteRemote,
          confirmedOverwriteLocal: confirmedOverwriteLocal,
          confirmedOverwriteRemote: confirmedOverwriteRemote,
          skippedDeleteModifyConflicts: skippedDeleteModifyConflicts,
        ),
      );
      return CloudSyncResult.fromRust(result);
    });
  }

  Future<CloudSyncResult> uploadNote({
    required LocalDataState localDataState,
    required String notePath,
  }) async {
    return _runExclusive(localDataState.dataDirectory, () async {
      final config = localDataState.config.cloudSync;
      final result = await api.uploadNote(
        rust_model.CloudSyncNoteUploadRequest(
          config: _rustConfig(config),
          dataDirectory: localDataState.dataDirectory,
          dailyNotesDirectory: localDataState.dailyNotesDirectory,
          weeklyNotesDirectory: localDataState.weeklyNotesDirectory,
          monthlyNotesDirectory: localDataState.monthlyNotesDirectory,
          notePath: notePath,
        ),
      );
      return CloudSyncResult.fromRust(result);
    });
  }

  static Future<T> _runExclusive<T>(
    String dataDirectory,
    Future<T> Function() action,
  ) {
    return NoteStorageCoordinator.runForDataDirectory(dataDirectory, action);
  }

  rust_model.CloudSyncConfig _rustConfig(CloudSyncConfig config) {
    return rust_model.CloudSyncConfig(
      enabled: config.enabled,
      serverUrl: config.serverUrl,
      username: config.username,
      password: config.password,
    );
  }
}

class CloudSyncRustApi {
  const CloudSyncRustApi();

  Future<rust_model.CloudSyncResult> testConnection(
    rust_model.CloudSyncConfig config,
  ) {
    return rust_api.testWebDavConnection(config: config);
  }

  Future<rust_model.CloudSyncResult> sync(rust_model.CloudSyncRequest request) {
    return rust_api.syncWebDavNotes(request: request);
  }

  Future<rust_model.CloudSyncResult> uploadNote(
    rust_model.CloudSyncNoteUploadRequest request,
  ) {
    return rust_api.uploadWebDavNote(request: request);
  }
}
