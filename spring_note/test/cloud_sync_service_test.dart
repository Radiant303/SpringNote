import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/cloud_sync_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/services/cloud_sync_service.dart';
import 'package:spring_note/src/rust/cloud_sync.dart' as rust_cloud;

void main() {
  test('cloud sync delegates connection test to rust api', () async {
    final api = _FakeCloudSyncRustApi();
    final service = CloudSyncService(api: api);

    final result = await service.testConnection(_syncConfig());

    expect(result.ok, isTrue);
    expect(result.message, '连接成功');
    expect(api.testedConfig?.serverUrl, 'https://example.com/dav/');
    expect(api.testedConfig?.username, 'user');
    expect(api.testedConfig?.password, 'token');
  });

  test('cloud sync builds rust sync request and converts result', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_sync_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final state = _state(temp);
    final api = _FakeCloudSyncRustApi(
      syncResult: const rust_cloud.CloudSyncResult(
        ok: true,
        message: '手动同步完成: 上传 1, 下载 2, 冲突 0',
        uploaded: 1,
        downloaded: 2,
        conflicts: 0,
        syncedAt: '2026-06-28T22:00:00+08:00',
        errorCode: '',
        needsDeleteConfirmation: true,
        pendingDeleteLocal: ['notes/daily/old.md'],
        pendingDeleteRemote: ['notes/daily/remote.md'],
        needsDeleteModifyConfirmation: true,
        pendingDeleteModifyConflicts: [
          rust_cloud.DeleteModifyConflict(
            relativePath: 'notes/daily/conflict.md',
            direction: 'local_modified_remote_deleted',
          ),
        ],
      ),
    );
    final service = CloudSyncService(api: api);

    final result = await service.sync(
      localDataState: state,
      trigger: CloudSyncTrigger.manual,
      confirmedDeleteLocal: const ['notes/daily/local.md'],
      confirmedDeleteRemote: const ['notes/daily/remote.md'],
      confirmedOverwriteLocal: const ['notes/daily/cloud.md'],
      confirmedOverwriteRemote: const ['notes/daily/device.md'],
      skippedDeleteModifyConflicts: const ['notes/daily/skipped.md'],
    );

    expect(result.ok, isTrue);
    expect(result.message, '手动同步完成：上传 1，下载 2，冲突 0');
    expect(result.uploaded, 1);
    expect(result.downloaded, 2);
    expect(result.syncedAt, DateTime.parse('2026-06-28T22:00:00+08:00'));
    expect(result.needsDeleteConfirmation, isTrue);
    expect(result.pendingDeleteLocal, ['notes/daily/old.md']);
    expect(result.pendingDeleteRemote, ['notes/daily/remote.md']);
    expect(result.needsDeleteModifyConfirmation, isTrue);
    expect(
      result.pendingDeleteModifyConflicts.single.relativePath,
      'notes/daily/conflict.md',
    );
    expect(
      result.pendingDeleteModifyConflicts.single.direction,
      'local_modified_remote_deleted',
    );
    expect(api.syncRequest?.trigger, 'manual');
    expect(api.syncRequest?.dataDirectory, temp.path);
    expect(api.syncRequest?.dailyNotesDirectory, state.dailyNotesDirectory);
    expect(api.syncRequest?.config.enabled, isTrue);
    expect(api.syncRequest?.confirmedDeleteLocal, ['notes/daily/local.md']);
    expect(api.syncRequest?.confirmedDeleteRemote, ['notes/daily/remote.md']);
    expect(api.syncRequest?.confirmedOverwriteLocal, ['notes/daily/cloud.md']);
    expect(api.syncRequest?.confirmedOverwriteRemote, [
      'notes/daily/device.md',
    ]);
    expect(api.syncRequest?.skippedDeleteModifyConflicts, [
      'notes/daily/skipped.md',
    ]);
  });

  test('cloud sync builds rust single note upload request', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_upload_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final state = _state(temp);
    final api = _FakeCloudSyncRustApi(
      noteUploadResult: const rust_cloud.CloudSyncResult(
        ok: true,
        message: '笔记自动同步完成: 上传 1',
        uploaded: 1,
        downloaded: 0,
        conflicts: 0,
        syncedAt: '2026-06-29T00:00:00+08:00',
        errorCode: '',
        needsDeleteConfirmation: false,
        pendingDeleteLocal: [],
        pendingDeleteRemote: [],
        needsDeleteModifyConfirmation: false,
        pendingDeleteModifyConflicts: [],
      ),
    );
    final service = CloudSyncService(api: api);
    final notePath =
        '${state.dailyNotesDirectory}${Platform.pathSeparator}2026-06-29.md';

    final result = await service.uploadNote(
      localDataState: state,
      notePath: notePath,
    );

    expect(result.ok, isTrue);
    expect(result.uploaded, 1);
    expect(api.noteUploadRequest?.notePath, notePath);
    expect(api.noteUploadRequest?.dataDirectory, temp.path);
    expect(
      api.noteUploadRequest?.dailyNotesDirectory,
      state.dailyNotesDirectory,
    );
    expect(api.noteUploadRequest?.config.enabled, isTrue);
  });
}

CloudSyncConfig _syncConfig() {
  return CloudSyncConfig.defaults().copyWith(
    enabled: true,
    serverUrl: 'https://example.com/dav/',
    username: 'user',
    password: 'token',
  );
}

LocalDataState _state(Directory root) {
  final notes = '${root.path}${Platform.pathSeparator}notes';
  final daily = '$notes${Platform.pathSeparator}daily';
  final weekly = '$notes${Platform.pathSeparator}weekly';
  final monthly = '$notes${Platform.pathSeparator}monthly';
  for (final path in [daily, weekly, monthly]) {
    Directory(path).createSync(recursive: true);
  }
  return LocalDataState(
    dataDirectory: root.path,
    configPath: '${root.path}${Platform.pathSeparator}config.json',
    dailyNotesDirectory: daily,
    weeklyNotesDirectory: weekly,
    monthlyNotesDirectory: monthly,
    config: AppConfig.defaults().copyWith(cloudSync: _syncConfig()),
  );
}

class _FakeCloudSyncRustApi extends CloudSyncRustApi {
  _FakeCloudSyncRustApi({
    this.syncResult = const rust_cloud.CloudSyncResult(
      ok: true,
      message: '手动同步完成: 上传 0, 下载 0, 冲突 0',
      uploaded: 0,
      downloaded: 0,
      conflicts: 0,
      syncedAt: '',
      errorCode: '',
      needsDeleteConfirmation: false,
      pendingDeleteLocal: [],
      pendingDeleteRemote: [],
      needsDeleteModifyConfirmation: false,
      pendingDeleteModifyConflicts: [],
    ),
    this.noteUploadResult = const rust_cloud.CloudSyncResult(
      ok: true,
      message: '笔记自动同步完成: 上传 0',
      uploaded: 0,
      downloaded: 0,
      conflicts: 0,
      syncedAt: '',
      errorCode: '',
      needsDeleteConfirmation: false,
      pendingDeleteLocal: [],
      pendingDeleteRemote: [],
      needsDeleteModifyConfirmation: false,
      pendingDeleteModifyConflicts: [],
    ),
  });

  final rust_cloud.CloudSyncResult syncResult;
  final rust_cloud.CloudSyncResult noteUploadResult;
  rust_cloud.CloudSyncConfig? testedConfig;
  rust_cloud.CloudSyncRequest? syncRequest;
  rust_cloud.CloudSyncNoteUploadRequest? noteUploadRequest;

  @override
  Future<rust_cloud.CloudSyncResult> testConnection(
    rust_cloud.CloudSyncConfig config,
  ) async {
    testedConfig = config;
    return const rust_cloud.CloudSyncResult(
      ok: true,
      message: '连接成功',
      uploaded: 0,
      downloaded: 0,
      conflicts: 0,
      syncedAt: '',
      errorCode: '',
      needsDeleteConfirmation: false,
      pendingDeleteLocal: [],
      pendingDeleteRemote: [],
      needsDeleteModifyConfirmation: false,
      pendingDeleteModifyConflicts: [],
    );
  }

  @override
  Future<rust_cloud.CloudSyncResult> sync(
    rust_cloud.CloudSyncRequest request,
  ) async {
    syncRequest = request;
    return syncResult;
  }

  @override
  Future<rust_cloud.CloudSyncResult> uploadNote(
    rust_cloud.CloudSyncNoteUploadRequest request,
  ) async {
    noteUploadRequest = request;
    return noteUploadResult;
  }
}
