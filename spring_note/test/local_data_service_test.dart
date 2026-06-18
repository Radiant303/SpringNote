import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/services/local_data_service.dart';

void main() {
  test('local data service creates first-run data layout', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_test_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final state = await LocalDataService(appDataPath: temp.path).initialize();

    expect(await File(state.configPath).exists(), isTrue);
    expect(await Directory(state.dailyNotesDirectory).exists(), isTrue);
    expect(await Directory(state.weeklyNotesDirectory).exists(), isTrue);
    expect(await Directory(state.monthlyNotesDirectory).exists(), isTrue);
    expect(
      state.config.defaultModels.keys,
      contains('intelligentGenerationModel'),
    );
    expect(state.config.defaultModels.keys, contains('editCompletionModel'));
    expect(state.config.defaultModels.keys, contains('memoryBookModel'));
  });
}
