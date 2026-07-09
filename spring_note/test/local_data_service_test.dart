import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/cloud_sync_config.dart';
import 'package:spring_note/core/models/desktop_widget_position.dart';
import 'package:spring_note/core/models/model_config.dart';
import 'package:spring_note/core/models/provider_config.dart';
import 'package:spring_note/core/services/local_data_service.dart';
import 'package:spring_note/core/services/security_scoped_directory_access.dart';

void main() {
  test('app config round trips desktop widget position', () {
    const position = DesktopWidgetPosition(
      screenId: 'display-1',
      x: 120.5,
      y: 240.25,
    );
    final config = AppConfig.defaults().copyWith(
      desktopWidgetPosition: position,
    );

    final reloaded = AppConfig.fromJson(config.toJson());
    final cleared = reloaded.copyWith(desktopWidgetPosition: null);

    expect(reloaded.desktopWidgetPosition, position);
    expect(cleared.desktopWidgetPosition, isNull);
    expect(AppConfig.fromJson({}).desktopWidgetPosition, isNull);
    expect(
      AppConfig.fromJson({
        'desktopWidgetPosition': {'x': double.nan, 'y': 10},
      }).desktopWidgetPosition,
      isNull,
    );
    expect(
      AppConfig.fromJson({
        'desktopWidgetPosition': {'x': -1000000, 'y': 1000000},
      }).desktopWidgetPosition,
      const DesktopWidgetPosition(x: -1000000, y: 1000000),
    );
  });

  test('app config round trips desktop widget orb mode', () {
    final config = AppConfig.defaults().copyWith(desktopWidgetOrbMode: true);

    final reloaded = AppConfig.fromJson(config.toJson());

    expect(reloaded.desktopWidgetOrbMode, isTrue);
    expect(AppConfig.fromJson({}).desktopWidgetOrbMode, isFalse);
  });

  test('app config round trips theme mode preference', () {
    final config = AppConfig.defaults().copyWith(
      themeMode: AppThemePreference.dark,
    );

    final reloaded = AppConfig.fromJson(config.toJson());

    expect(reloaded.themeMode, AppThemePreference.dark);
    expect(
      AppConfig.fromJson({'themeMode': 'Dark'}).themeMode,
      AppThemePreference.dark,
    );
    expect(AppConfig.fromJson({}).themeMode, AppThemePreference.system);
    expect(
      AppConfig.fromJson({'themeMode': 'invalid'}).themeMode,
      AppThemePreference.system,
    );
  });

  test('app config round trips markdown syntax highlight preference', () {
    final config = AppConfig.defaults().copyWith(
      markdownSyntaxHighlightEnabled: false,
    );

    final reloaded = AppConfig.fromJson(config.toJson());

    expect(AppConfig.defaults().markdownSyntaxHighlightEnabled, isTrue);
    expect(reloaded.markdownSyntaxHighlightEnabled, isFalse);
    expect(AppConfig.fromJson({}).markdownSyntaxHighlightEnabled, isTrue);
  });

  test('app config round trips cloud sync config', () {
    final syncedAt = DateTime.utc(2026, 6, 28, 12, 40);
    final config = AppConfig.defaults().copyWith(
      cloudSync: CloudSyncConfig.defaults().copyWith(
        enabled: true,
        serverUrl: 'https://dav.example.com/remote.php/dav/files/me/',
        username: 'me',
        password: 'token',
        syncOnStartup: true,
        realTimeSync: true,
        lastSyncedAt: syncedAt,
      ),
    );

    final reloaded = AppConfig.fromJson(config.toJson());

    expect(reloaded.cloudSync.enabled, isTrue);
    expect(reloaded.cloudSync.serverUrl, contains('dav.example.com'));
    expect(reloaded.cloudSync.username, 'me');
    expect(reloaded.cloudSync.password, 'token');
    expect(reloaded.cloudSync.syncOnStartup, isTrue);
    expect(reloaded.cloudSync.realTimeSync, isTrue);
    expect(reloaded.cloudSync.lastSyncedAt, syncedAt);
    expect(AppConfig.fromJson({}).cloudSync.enabled, isFalse);
    expect(AppConfig.fromJson({}).cloudSync.realTimeSync, isFalse);
  });

  test('local data service creates first-run data layout', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_test_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final executableDir = Directory('${temp.path}${Platform.pathSeparator}bin');
    final state = await LocalDataService(
      appDataPath: temp.path,
      executableDirectoryPath: executableDir.path,
    ).initialize();

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
    expect(state.config.apiLogEnabled, isFalse);
    expect(
      await File(
        '${executableDir.path}${Platform.pathSeparator}data-directory.json',
      ).exists(),
      isTrue,
    );
  });

  test('local data service saves and reads provider model config', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_config_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final service = LocalDataService(
      appDataPath: temp.path,
      executableDirectoryPath: '${temp.path}${Platform.pathSeparator}bin',
      securityScopedDirectoryAccess: _RecordingSecurityScopedDirectoryAccess(),
    );
    final state = await service.initialize();
    final provider = ProviderConfig.template('OpenAI');
    final config = state.config.copyWith(
      dailyWorkHours: 9,
      apiLogEnabled: true,
      providers: [provider],
      defaultModels: {
        ...state.config.defaultModels,
        'intelligentGenerationModel': provider.models.first.modelId,
      },
    );

    await service.saveConfig(config);
    final reloaded = await service.readConfig();

    expect(reloaded.dailyWorkHours, 9);
    expect(reloaded.apiLogEnabled, isTrue);
    expect(reloaded.providers, hasLength(1));
    expect(reloaded.providers.first.name, 'OpenAI');
    expect(reloaded.providers.first.models.first.fimMode, 'none');
    expect(
      reloaded.providers.first.models.first.toJson().keys,
      isNot(contains('fimMode')),
    );
    expect(
      reloaded.defaultModels['intelligentGenerationModel'],
      'gpt-4.1-mini',
    );
  });

  test('local data service migrates data to custom directory', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_migrate_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final service = LocalDataService(
      appDataPath: temp.path,
      executableDirectoryPath: '${temp.path}${Platform.pathSeparator}bin',
      securityScopedDirectoryAccess: _RecordingSecurityScopedDirectoryAccess(),
    );
    final state = await service.initialize();
    final dailyNote = File(
      '${state.dailyNotesDirectory}${Platform.pathSeparator}2026-06-24.md',
    );
    await dailyNote.writeAsString('# Today\n\nMoved note');

    final target = Directory(
      '${temp.path}${Platform.pathSeparator}custom_store',
    );
    final migrated = await service.migrateDataDirectory(
      currentState: state.copyWith(
        config: state.config.copyWith(dailyWorkHours: 7),
      ),
      targetDirectory: target.path,
    );

    expect(migrated.dataDirectory, target.absolute.path);
    expect(migrated.config.customDataDirectory, target.absolute.path);
    expect(await File(migrated.configPath).exists(), isTrue);
    expect(
      await File(
        '${migrated.dailyNotesDirectory}${Platform.pathSeparator}2026-06-24.md',
      ).readAsString(),
      '# Today\n\nMoved note',
    );

    final reinitialized = await service.initialize();
    expect(reinitialized.dataDirectory, target.absolute.path);
    expect(reinitialized.config.dailyWorkHours, 7);
  });

  test(
    'local data service restores default directory and clears pointer',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'spring_note_default_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });

      final executableDir = Directory(
        '${temp.path}${Platform.pathSeparator}bin',
      );
      final service = LocalDataService(
        appDataPath: temp.path,
        executableDirectoryPath: executableDir.path,
        securityScopedDirectoryAccess:
            _RecordingSecurityScopedDirectoryAccess(),
      );
      final state = await service.initialize();
      final target = Directory(
        '${temp.path}${Platform.pathSeparator}custom_store',
      );
      final migrated = await service.migrateDataDirectory(
        currentState: state,
        targetDirectory: target.path,
      );

      final restored = await service.migrateDataDirectory(
        currentState: migrated,
        targetDirectory: null,
      );

      final defaultRoot = '${temp.path}${Platform.pathSeparator}SpringNote';
      expect(restored.dataDirectory, defaultRoot);
      expect(restored.config.customDataDirectory, isNull);
      expect(
        await File(
          '$defaultRoot${Platform.pathSeparator}data-directory.json',
        ).exists(),
        isFalse,
      );
      final executablePointer = File(
        '${executableDir.path}${Platform.pathSeparator}data-directory.json',
      );
      final executablePointerJson =
          jsonDecode(await executablePointer.readAsString())
              as Map<String, Object?>;
      expect(executablePointerJson['dataDirectory'], defaultRoot);

      final reinitialized = await service.initialize();
      expect(reinitialized.dataDirectory, defaultRoot);
    },
  );
  test('local data service falls back to data directory pointer', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_pointer_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final executablePath =
        '${temp.path}${Platform.pathSeparator}not-a-directory';
    await File(executablePath).writeAsString('blocked');
    final service = LocalDataService(
      appDataPath: temp.path,
      executableDirectoryPath: executablePath,
    );

    final state = await service.initialize();
    final defaultRoot = '${temp.path}${Platform.pathSeparator}SpringNote';
    final fallbackPointer = File(
      '$defaultRoot${Platform.pathSeparator}data-directory.json',
    );

    expect(state.dataDirectory, defaultRoot);
    expect(await fallbackPointer.exists(), isTrue);
    final fallbackPointerJson =
        jsonDecode(await fallbackPointer.readAsString())
            as Map<String, Object?>;
    expect(fallbackPointerJson['dataDirectory'], defaultRoot);
  });

  test(
    'local data service repairs config with trailing invalid json',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'spring_note_repair_config_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });

      final service = LocalDataService(
        appDataPath: temp.path,
        executableDirectoryPath: '${temp.path}${Platform.pathSeparator}bin',
      );
      final state = await service.initialize();
      final configFile = File(state.configPath);
      final configJson = jsonDecode(await configFile.readAsString()) as Map;
      configJson['dailyWorkHours'] = 6;
      const encoder = JsonEncoder.withIndent('  ');
      await configFile.writeAsString(
        '${encoder.convert(configJson)}\n  }\n}\n',
      );

      final reinitialized = await service.initialize();

      expect(reinitialized.config.dailyWorkHours, 6);
      expect(
        await configFile.parent.list().any(
          (entity) =>
              entity is File && entity.path.contains('config.json.invalid-'),
        ),
        isTrue,
      );
      expect(() => jsonDecode(configFile.readAsStringSync()), returnsNormally);
    },
  );

  test('local data service ignores malformed data directory pointer', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_bad_pointer_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final executableDir = Directory('${temp.path}${Platform.pathSeparator}bin');
    await executableDir.create(recursive: true);
    await File(
      '${executableDir.path}${Platform.pathSeparator}data-directory.json',
    ).writeAsString('}\n');

    final state = await LocalDataService(
      appDataPath: temp.path,
      executableDirectoryPath: executableDir.path,
    ).initialize();

    expect(
      state.dataDirectory,
      '${temp.path}${Platform.pathSeparator}SpringNote',
    );
    expect(
      await executableDir.list().any(
        (entity) =>
            entity is File &&
            entity.path.contains('data-directory.json.invalid-'),
      ),
      isTrue,
    );
  });

  test(
    'local data service switches to existing data directory without overwriting config',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'spring_note_existing_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });

      final access = _RecordingSecurityScopedDirectoryAccess();
      final service = LocalDataService(
        appDataPath: '${temp.path}${Platform.pathSeparator}app_data',
        executableDirectoryPath: '${temp.path}${Platform.pathSeparator}bin',
        securityScopedDirectoryAccess: access,
      );
      final state = await service.initialize();
      final target = Directory(
        '${temp.path}${Platform.pathSeparator}existing_store',
      );
      await target.create(recursive: true);
      await File(
        '${target.path}${Platform.pathSeparator}config.json',
      ).writeAsString('{"dailyWorkHours": 6, "showTrayIcon": false}\n');

      final migrated = await service.migrateDataDirectory(
        currentState: state.copyWith(
          config: state.config.copyWith(dailyWorkHours: 9),
        ),
        targetDirectory: target.path,
      );

      expect(migrated.dataDirectory, target.absolute.path);
      expect(migrated.config.dailyWorkHours, 6);
      expect(migrated.config.showTrayIcon, isFalse);
      expect(migrated.config.customDataDirectory, target.absolute.path);
      expect(access.savedBookmarks, contains(target.absolute.path));
      expect(
        await File(
          '${target.path}${Platform.pathSeparator}config.json',
        ).readAsString(),
        contains('"dailyWorkHours": 6'),
      );
    },
  );

  test('model config derives FIM mode from completion model type', () {
    const completionModel = ModelConfig(
      modelId: 'fim-model',
      displayName: 'FIM Model',
      modelTypes: ['chat', 'completion'],
    );
    expect(completionModel.fimMode, 'completions');
    expect(completionModel.toJson().keys, isNot(contains('fimMode')));

    final migrated = ModelConfig.fromJson({
      'modelId': 'legacy-fim-model',
      'displayName': 'Legacy FIM Model',
      'modelTypes': ['chat'],
      'fimMode': 'completions',
    });
    expect(migrated.modelTypes, contains('completion'));
    expect(migrated.fimMode, 'completions');
  });
}

class _RecordingSecurityScopedDirectoryAccess
    implements SecurityScopedDirectoryAccess {
  final List<String> savedBookmarks = [];
  final List<String> startedAccess = [];
  final List<String> removedBookmarks = [];

  @override
  Future<void> removeBookmark(String path) async {
    removedBookmarks.add(Directory(path).absolute.path);
  }

  @override
  Future<bool> saveBookmark(String path) async {
    savedBookmarks.add(Directory(path).absolute.path);
    return true;
  }

  @override
  Future<bool> startAccessing(String path) async {
    startedAccess.add(Directory(path).absolute.path);
    return true;
  }
}
