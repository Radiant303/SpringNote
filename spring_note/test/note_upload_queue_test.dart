import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/cloud_sync_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/services/cloud_sync_service.dart';
import 'package:spring_note/core/services/note_upload_queue.dart';

void main() {
  test('deduplicates repeated dirty marks for the same note', () async {
    final service = _FakeCloudSyncService();
    final queue = NoteUploadQueue(cloudSyncService: service)..attach(_state);

    queue
      ..markDirty(r'D:\Temp\SpringNote\notes\daily\2026-06-29.md')
      ..markDirty(r'D:\Temp\SpringNote\notes\daily\2026-06-29.md');

    final result = await queue.flush();

    expect(result.ok, isTrue);
    expect(result.uploaded, 1);
    expect(service.uploadedPaths, [
      r'D:\Temp\SpringNote\notes\daily\2026-06-29.md',
    ]);
  });

  test('uploads a note again when it is marked dirty during upload', () async {
    late NoteUploadQueue queue;
    var markedAgain = false;
    final service = _FakeCloudSyncService(
      onUpload: (path) {
        if (markedAgain) {
          return;
        }
        markedAgain = true;
        queue.markDirty(path);
      },
    );
    queue = NoteUploadQueue(cloudSyncService: service)..attach(_state);

    queue.markDirty(r'D:\Temp\SpringNote\notes\daily\2026-06-29.md');
    final result = await queue.flush();

    expect(result.ok, isTrue);
    expect(result.uploaded, 2);
    expect(service.uploadedPaths, [
      r'D:\Temp\SpringNote\notes\daily\2026-06-29.md',
      r'D:\Temp\SpringNote\notes\daily\2026-06-29.md',
    ]);
  });

  test('keeps pending notes when real-time sync is unavailable', () async {
    final service = _FakeCloudSyncService();
    final queue = NoteUploadQueue(cloudSyncService: service)
      ..attach(
        _state.copyWith(
          config: _state.config.copyWith(
            cloudSync: _state.config.cloudSync.copyWith(realTimeSync: false),
          ),
        ),
      );

    queue.markDirty(r'D:\Temp\SpringNote\notes\daily\2026-06-29.md');
    final result = await queue.flush();

    expect(result.attempted, isFalse);
    expect(queue.hasPendingUploads, isTrue);
    expect(service.uploadedPaths, isEmpty);
  });
}

class _FakeCloudSyncService extends CloudSyncService {
  _FakeCloudSyncService({this.onUpload});

  final void Function(String path)? onUpload;
  final List<String> uploadedPaths = [];

  @override
  Future<CloudSyncResult> uploadNote({
    required LocalDataState localDataState,
    required String notePath,
  }) async {
    uploadedPaths.add(notePath);
    onUpload?.call(notePath);
    return const CloudSyncResult(ok: true, message: '笔记自动同步完成', uploaded: 1);
  }
}

final _state = LocalDataState(
  dataDirectory: r'D:\Temp\SpringNote',
  configPath: r'D:\Temp\SpringNote\config.json',
  dailyNotesDirectory: r'D:\Temp\SpringNote\notes\daily',
  weeklyNotesDirectory: r'D:\Temp\SpringNote\notes\weekly',
  monthlyNotesDirectory: r'D:\Temp\SpringNote\notes\monthly',
  config: AppConfig.defaults().copyWith(
    cloudSync: CloudSyncConfig.defaults().copyWith(
      enabled: true,
      serverUrl: 'https://example.com/dav/',
      username: 'user',
      password: 'token',
      realTimeSync: true,
    ),
  ),
);
