import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/provider_config.dart';
import 'package:spring_note/core/services/ai_client_service.dart';
import 'package:spring_note/core/services/local_data_service.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/settings/settings_page.dart';
import 'package:spring_note/src/rust/ai.dart' as rust_ai;

void main() {
  test('app theme applies configured font and clamps font scale', () {
    final theme = AppTheme.light(appFont: 'Consolas');

    expect(theme.textTheme.bodyMedium?.fontFamily, 'Consolas');
    expect(theme.textTheme.titleMedium?.fontFamily, 'Consolas');
    expect(AppTheme.fontScaleFactor(120), 1.2);
    expect(AppTheme.fontScaleFactor(10), 0.8);
    expect(AppTheme.fontScaleFactor(200), 1.4);
  });

  testWidgets('settings page switches sections and persists preferences', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _MemoryLocalDataService(AppConfig.defaults());
    AppConfig? latestConfig;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsPage(
          localDataState: _state(AppConfig.defaults()),
          localDataService: service,
          onConfigChanged: (config) => latestConfig = config,
        ),
      ),
    );

    for (final section in ['供应商', '默认模型', '快捷键', '统计', '关于', '偏好设置']) {
      await tester.tap(find.text(section).first);
      await tester.pump();
      expect(find.text(section), findsWidgets);
    }

    await tester.enterText(find.byType(TextField).first, '9');
    await tester.pump();
    expect(service.savedConfig.dailyWorkHours, 9);

    await tester.tap(find.byType(Switch).at(2));
    await tester.pump();
    expect(service.savedConfig.apiLogEnabled, isTrue);
    expect(latestConfig?.apiLogEnabled, isTrue);
  });

  testWidgets('settings page persists font size input', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _MemoryLocalDataService(AppConfig.defaults());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsPage(
          localDataState: _state(AppConfig.defaults()),
          localDataService: service,
        ),
      ),
    );

    expect(find.text('系统默认'), findsOneWidget);
    final fontScaleField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller?.text == '100',
    );
    expect(fontScaleField, findsOneWidget);

    await tester.enterText(fontScaleField, '120');
    await tester.pump();

    expect(service.savedConfig.fontScale, 120);
  });

  testWidgets('settings page adds provider edits model and selects default', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _MemoryLocalDataService(AppConfig.defaults());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsPage(
          localDataState: _state(AppConfig.defaults()),
          localDataService: service,
        ),
      ),
    );

    await tester.tap(find.text('供应商').first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-provider-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-add-provider-button')));
    await tester.pumpAndSettle();

    expect(service.savedConfig.providers, hasLength(1));
    expect(
      service.savedConfig.providers.first.models.first.modelId,
      'gpt-4.1-mini',
    );

    await tester.tap(find.byKey(const ValueKey('add-model-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-model-id-field')),
      'custom-chat-model',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-model-name-field')),
      'Custom Chat Model',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-add-model-button')));
    await tester.pumpAndSettle();

    expect(
      service.savedConfig.providers.first.models.map((model) => model.modelId),
      contains('custom-chat-model'),
    );

    await tester.tap(
      find.byKey(const ValueKey('edit-model-custom-chat-model')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('edit-model-name-field')),
      'Custom Chat Edited',
    );
    expect(find.text('FIM 模式'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, '补全'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-edit-model-button')));
    await tester.pumpAndSettle();

    final edited = service.savedConfig.providers.first.models.firstWhere(
      (model) => model.modelId == 'custom-chat-model',
    );
    expect(edited.displayName, 'Custom Chat Edited');
    expect(edited.modelTypes, contains('completion'));
    expect(edited.fimMode, 'completions');

    await tester.tap(find.text('默认模型').first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('default-model-智能生成模型')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom Chat Edited').last);
    await tester.pumpAndSettle();

    expect(
      service.savedConfig.defaultModels['intelligentGenerationModel'],
      'custom-chat-model',
    );

    await tester.tap(find.byKey(const ValueKey('default-model-编辑补全模型')));
    await tester.pumpAndSettle();
    expect(find.text('Custom Chat Edited'), findsWidgets);
    expect(find.text('GPT-4.1 Mini'), findsNothing);
    await tester.tap(find.text('Custom Chat Edited').last);
    await tester.pumpAndSettle();
    expect(
      service.savedConfig.defaultModels['editCompletionModel'],
      'custom-chat-model',
    );
  });

  testWidgets('provider and model changes persist to config file', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('spring_note_settings_persist_'),
    );
    expect(temp, isNotNull);
    addTearDown(() async {
      final directory = temp;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final configFile = File(
      '${temp!.path}${Platform.pathSeparator}config.json',
    );
    final service = _FileBackedLocalDataService(
      configFile,
      AppConfig.defaults(),
    );
    final state = _state(AppConfig.defaults());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsPage(localDataState: state, localDataService: service),
      ),
    );

    await tester.tap(find.text('供应商').first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-provider-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-add-provider-button')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('add-model-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-model-id-field')),
      'persist-model',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-model-name-field')),
      'Persist Model',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-add-model-button')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('edit-model-persist-model')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('edit-model-name-field')),
      'Persist Model Edited',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-edit-model-button')));
    await tester.pump(const Duration(milliseconds: 300));

    final reloaded = await tester.runAsync(service.readConfig);
    expect(reloaded, isNotNull);
    expect(reloaded!.providers, hasLength(1));
    final persistedModel = reloaded.providers.first.models.firstWhere(
      (model) => model.modelId == 'persist-model',
    );
    expect(persistedModel.displayName, 'Persist Model Edited');
    final persistedJson = jsonDecode(configFile.readAsStringSync()).toString();
    expect(persistedJson, isNot(contains('fimMode')));
  });

  testWidgets('provider fetch models dialog groups and toggles remote models', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const provider = ProviderConfig(
      id: 'openai-test',
      enabled: true,
      name: 'OpenAI',
      protocol: 'openaiCompatible',
      apiKey: 'test-key',
      baseUrl: 'https://api.openai.com/v1',
      apiPath: '/chat/completions',
      models: [],
    );
    final service = _MemoryLocalDataService(
      AppConfig.defaults().copyWith(providers: const [provider]),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsPage(
          localDataState: _state(service.savedConfig),
          localDataService: service,
          aiClientService: const _FakeAiClientService(),
        ),
      ),
    );

    await tester.tap(find.text('供应商').first);
    await tester.pump();
    await tester.tap(find.text('获取模型'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));

    final dialog = find.byKey(const ValueKey('provider-model-fetch-dialog'));
    final remoteModel = find.descendant(
      of: dialog,
      matching: find.text('qwen3-coder'),
    );

    expect(dialog, findsOne);
    expect(find.text('qwen'), findsOneWidget);
    expect(remoteModel, findsOneWidget);

    await tester.tap(remoteModel);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      service.savedConfig.providers.first.models.map((model) => model.modelId),
      contains('qwen/qwen3-coder'),
    );

    await tester.tap(remoteModel);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      service.savedConfig.providers.first.models.map((model) => model.modelId),
      isNot(contains('qwen/qwen3-coder')),
    );
  });
}

LocalDataState _state(AppConfig config) {
  return LocalDataState(
    dataDirectory: 'D:\\Temp\\SpringNote',
    configPath: 'D:\\Temp\\SpringNote\\config.json',
    dailyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\daily',
    weeklyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\weekly',
    monthlyNotesDirectory: 'D:\\Temp\\SpringNote\\notes\\monthly',
    config: config,
  );
}

class _MemoryLocalDataService extends LocalDataService {
  _MemoryLocalDataService(this.savedConfig);

  AppConfig savedConfig;

  @override
  Future<AppConfig> readConfig() async {
    return savedConfig;
  }

  @override
  Future<void> saveConfig(AppConfig config) async {
    savedConfig = config;
  }
}

class _FileBackedLocalDataService extends LocalDataService {
  _FileBackedLocalDataService(this.configFile, this.savedConfig);

  final File configFile;
  AppConfig savedConfig;

  @override
  Future<AppConfig> readConfig() async {
    if (!configFile.existsSync()) {
      return savedConfig;
    }
    final decoded = jsonDecode(configFile.readAsStringSync());
    final json = (decoded as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
    savedConfig = AppConfig.fromJson(json);
    return savedConfig;
  }

  @override
  Future<void> saveConfig(AppConfig config) async {
    savedConfig = config;
    configFile.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    configFile.writeAsStringSync('${encoder.convert(config.toJson())}\n');
  }
}

class _FakeAiClientService extends AiClientService {
  const _FakeAiClientService();

  @override
  Future<rust_ai.ModelListResult> fetchProviderModels({
    required String appDataDir,
    required bool apiLogEnabled,
    required ProviderConfig provider,
  }) async {
    return const rust_ai.ModelListResult(
      ok: true,
      models: [
        rust_ai.AiModel(
          modelId: 'qwen/qwen3-coder',
          displayName: 'qwen/qwen3-coder',
        ),
        rust_ai.AiModel(modelId: 'zed/zed-chat', displayName: 'zed/zed-chat'),
        rust_ai.AiModel(modelId: 'gpt-4.1-mini', displayName: 'GPT-4.1 Mini'),
      ],
      errorCode: '',
      errorMessage: '',
    );
  }
}
