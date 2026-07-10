import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/services/note_image_cleanup_service.dart';
import 'package:spring_note/core/services/note_service.dart';
import 'package:spring_note/src/rust/note_image_cleanup.dart' as rust_model;

void main() {
  test('cleanup service maps Rust scan results', () async {
    final api = _RecordingNoteImageCleanupRustApi(
      scanResult: const rust_model.NoteImageCleanupScanResult(
        ok: true,
        errorMessage: '',
        totalImageCount: 3,
        referencedImageCount: 2,
        totalSizeBytes: 6144,
        unusedImages: [
          rust_model.NoteImageCleanupEntry(
            relativePath: 'unused image.png',
            sizeBytes: 2048,
          ),
        ],
      ),
    );

    final result = await NoteImageCleanupService(api: api).scan(_state());

    expect(api.scannedDataDirectory, r'D:\Temp\SpringNote');
    expect(result.totalImageCount, 3);
    expect(result.referencedImageCount, 2);
    expect(result.totalSizeBytes, 6144);
    expect(result.unusedImageCount, 1);
    expect(result.unusedImages.single.relativePath, 'unused image.png');
    expect(result.unusedSizeBytes, 2048);
  });

  test('cleanup service sends only relative candidates to Rust', () async {
    final api = _RecordingNoteImageCleanupRustApi(
      deleteResult: const rust_model.NoteImageCleanupDeleteResult(
        ok: true,
        errorMessage: '',
        deletedImages: [
          rust_model.NoteImageCleanupEntry(
            relativePath: 'remove.png',
            sizeBytes: 4096,
          ),
        ],
        failedImages: [],
        skippedCount: 1,
      ),
    );

    final result = await NoteImageCleanupService(api: api).deleteUnusedImages(
      localDataState: _state(),
      candidateRelativePaths: const ['remove.png', 'keep.png'],
    );

    expect(api.deletedDataDirectory, r'D:\Temp\SpringNote');
    expect(api.deletedCandidates, ['remove.png', 'keep.png']);
    expect(result.deletedCount, 1);
    expect(result.deletedSizeBytes, 4096);
    expect(result.skippedCount, 1);
  });

  test('cleanup service surfaces Rust validation errors', () async {
    final api = _RecordingNoteImageCleanupRustApi(
      scanResult: const rust_model.NoteImageCleanupScanResult(
        ok: false,
        errorMessage: 'Images directory is unsafe.',
        totalImageCount: 0,
        referencedImageCount: 0,
        totalSizeBytes: 0,
        unusedImages: [],
      ),
    );

    await expectLater(
      NoteImageCleanupService(api: api).scan(_state()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Images directory is unsafe.',
        ),
      ),
    );
  });

  test(
    'cleanup deletion blocks managed note writes for the same data',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'spring_note_cleanup_coordination_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final state = _stateForRoot(temp.path);
      final note = File(
        '${state.dailyNotesDirectory}${Platform.pathSeparator}2026-07-10.md',
      );
      await note.parent.create(recursive: true);
      await note.writeAsString('before');

      final deleteStarted = Completer<void>();
      final releaseDelete = Completer<void>();
      addTearDown(() {
        if (!releaseDelete.isCompleted) {
          releaseDelete.complete();
        }
      });
      final api = _RecordingNoteImageCleanupRustApi(
        deleteStarted: deleteStarted,
        deleteGate: releaseDelete.future,
      );
      final cleanupFuture = NoteImageCleanupService(api: api)
          .deleteUnusedImages(
            localDataState: state,
            candidateRelativePaths: const ['unused.png'],
          );
      await deleteStarted.future;

      var writeCompleted = false;
      final writeFuture = const NoteService()
          .writeMarkdown(note.path, 'after')
          .then((_) => writeCompleted = true);
      await Future<void>.delayed(Duration.zero);

      expect(writeCompleted, isFalse);
      expect(await note.readAsString(), 'before');

      releaseDelete.complete();
      await cleanupFuture;
      await writeFuture;
      expect(await note.readAsString(), 'after');
    },
  );
}

LocalDataState _state() {
  return LocalDataState(
    dataDirectory: r'D:\Temp\SpringNote',
    configPath: r'D:\Temp\SpringNote\config.json',
    dailyNotesDirectory: r'D:\Temp\SpringNote\notes\daily',
    weeklyNotesDirectory: r'D:\Temp\SpringNote\notes\weekly',
    monthlyNotesDirectory: r'D:\Temp\SpringNote\notes\monthly',
    config: AppConfig.defaults(),
  );
}

LocalDataState _stateForRoot(String root) {
  final notes = '$root${Platform.pathSeparator}notes';
  return LocalDataState(
    dataDirectory: root,
    configPath: '$root${Platform.pathSeparator}config.json',
    dailyNotesDirectory: '$notes${Platform.pathSeparator}daily',
    weeklyNotesDirectory: '$notes${Platform.pathSeparator}weekly',
    monthlyNotesDirectory: '$notes${Platform.pathSeparator}monthly',
    config: AppConfig.defaults(),
  );
}

class _RecordingNoteImageCleanupRustApi extends NoteImageCleanupRustApi {
  _RecordingNoteImageCleanupRustApi({
    this.scanResult = const rust_model.NoteImageCleanupScanResult(
      ok: true,
      errorMessage: '',
      totalImageCount: 0,
      referencedImageCount: 0,
      totalSizeBytes: 0,
      unusedImages: [],
    ),
    this.deleteResult = const rust_model.NoteImageCleanupDeleteResult(
      ok: true,
      errorMessage: '',
      deletedImages: [],
      failedImages: [],
      skippedCount: 0,
    ),
    this.deleteStarted,
    this.deleteGate,
  });

  final rust_model.NoteImageCleanupScanResult scanResult;
  final rust_model.NoteImageCleanupDeleteResult deleteResult;
  final Completer<void>? deleteStarted;
  final Future<void>? deleteGate;
  String? scannedDataDirectory;
  String? deletedDataDirectory;
  List<String>? deletedCandidates;

  @override
  Future<rust_model.NoteImageCleanupScanResult> scan(
    String dataDirectory,
  ) async {
    scannedDataDirectory = dataDirectory;
    return scanResult;
  }

  @override
  Future<rust_model.NoteImageCleanupDeleteResult> deleteUnused({
    required String dataDirectory,
    required List<String> candidateRelativePaths,
  }) async {
    deletedDataDirectory = dataDirectory;
    deletedCandidates = candidateRelativePaths;
    if (deleteStarted != null && !deleteStarted!.isCompleted) {
      deleteStarted!.complete();
    }
    final gate = deleteGate;
    if (gate != null) {
      await gate;
    }
    return deleteResult;
  }
}
