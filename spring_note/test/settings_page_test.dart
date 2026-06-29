import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/cloud_sync_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/model_config.dart';
import 'package:spring_note/core/models/model_reference.dart';
import 'package:spring_note/core/models/provider_config.dart';
import 'package:spring_note/core/services/ai_client_service.dart';
import 'package:spring_note/core/services/cloud_sync_service.dart';
import 'package:spring_note/core/services/local_data_service.dart';
import 'package:spring_note/core/services/platform_feature_support.dart';
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

  testWidgets('settings page persists desktop widget orb mode', (
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

    await tester.ensureVisible(find.text('桌面组件圆球模式'));
    await tester.pumpAndSettle();

    final orbModeRow = find.ancestor(
      of: find.text('桌面组件圆球模式'),
      matching: find.byWidgetPredicate(
        (widget) => widget is Row && widget.children.last is Switch,
      ),
    );
    expect(orbModeRow, findsOneWidget);

    await tester.tap(
      find.descendant(of: orbModeRow, matching: find.byType(Switch)),
    );
    await tester.pump();

    expect(
      service.savedConfig.desktopWidgetOrbMode,
      PlatformFeatureSupport.supportsDesktopWidget,
    );
  });

  testWidgets('hotkeys page lists local submit shortcuts', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsPage(
          localDataState: _state(AppConfig.defaults()),
          localDataService: _MemoryLocalDataService(AppConfig.defaults()),
        ),
      ),
    );

    await tester.tap(find.text('快捷键').first);
    await tester.pump();

    expect(find.text('输入快捷键'), findsOneWidget);
    expect(find.text('首页快速输入'), findsOneWidget);
    expect(find.text('回忆书对话输入'), findsOneWidget);
    expect(
      find.text(Platform.isMacOS ? 'Cmd+Enter' : 'Ctrl+Enter'),
      findsNWidgets(2),
    );
    expect(
      find.text(Platform.isMacOS ? 'Ctrl+Enter' : 'Cmd+Enter'),
      findsNothing,
    );
  });

  testWidgets('hotkeys page rejects invalid global hotkey input', (
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

    await tester.tap(find.text('快捷键').first);
    await tester.pump();

    final hotkeyField = find.byType(TextField);
    expect(hotkeyField, findsOneWidget);

    if (!PlatformFeatureSupport.supportsGlobalHotkeys) {
      final textField = tester.widget<TextField>(hotkeyField);
      expect(textField.enabled, isFalse);
      expect(find.text('当前平台暂不支持'), findsOneWidget);
      expect(service.savedConfig.hotkeys['toggleWindow'], 'Ctrl+Shift+S');
      return;
    }

    await tester.enterText(hotkeyField, 'hello');
    await tester.pump();

    expect(service.savedConfig.hotkeys['toggleWindow'], 'Ctrl+Shift+S');
    expect(find.text('请输入类似 Ctrl+Shift+S 的组合键'), findsOneWidget);

    await tester.enterText(hotkeyField, 'Ctrl+Alt+H');
    await tester.pump();

    expect(service.savedConfig.hotkeys['toggleWindow'], 'Ctrl+Alt+H');
    expect(find.text('请输入类似 Ctrl+Shift+S 的组合键'), findsNothing);
  });

  testWidgets('settings page persists WebDAV cloud sync config', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _MemoryLocalDataService(AppConfig.defaults());
    final cloudSyncService = _FakeCloudSyncService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsPage(
          localDataState: _state(AppConfig.defaults()),
          localDataService: service,
          cloudSyncService: cloudSyncService,
        ),
      ),
    );

    await tester.tap(find.text('云同步').first);
    await tester.pump();
    expect(find.text('连接设置'), findsOneWidget);
    expect(find.text('WebDAV 地址'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cloud-sync-message-slot')),
      findsOneWidget,
    );
    expect(find.textContaining('例如 https://example.com'), findsNothing);
    expect(find.textContaining('建议使用服务商生成'), findsNothing);
    expect(find.textContaining('连接测试只验证'), findsNothing);
    expect(find.text('应用关闭时自动同步'), findsNothing);
    expect(find.text('实时同步'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(service.savedConfig.cloudSync.enabled, isTrue);

    await tester.enterText(
      _cloudSyncTextFieldWithText(''),
      'https://dav.example.com/remote.php/dav/files/me/',
    );
    await tester.pump();
    await tester.enterText(_cloudSyncTextFieldWithText(''), 'me');
    await tester.pump();
    await tester.enterText(_cloudSyncTextFieldWithText(''), 'token');
    await tester.pump();

    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    await tester.tap(find.byType(Switch).at(2));
    await tester.pump();

    expect(
      service.savedConfig.cloudSync.serverUrl,
      contains('dav.example.com'),
    );
    expect(service.savedConfig.cloudSync.username, 'me');
    expect(service.savedConfig.cloudSync.password, 'token');
    expect(service.savedConfig.cloudSync.syncOnStartup, isTrue);
    expect(service.savedConfig.cloudSync.realTimeSync, isTrue);

    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(cloudSyncService.tested, isTrue);
    expect(find.text('连接成功'), findsOneWidget);

    await tester.tap(find.text('手动同步'));
    await tester.pumpAndSettle();
    expect(cloudSyncService.synced, isTrue);
    expect(service.savedConfig.cloudSync.lastSyncedAt, isNotNull);
    expect(find.textContaining('手动同步完成'), findsOneWidget);
  });

  testWidgets('settings page confirms cloud sync delete plan', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final initialConfig = AppConfig.defaults().copyWith(
      cloudSync: CloudSyncConfig.defaults().copyWith(enabled: true),
    );
    final service = _MemoryLocalDataService(initialConfig);
    final cloudSyncService = _FakeCloudSyncService(
      syncResults: [
        const CloudSyncResult(
          ok: true,
          message: '检测到删除项，请确认后继续同步',
          needsDeleteConfirmation: true,
          pendingDeleteLocal: ['notes/daily/old.md'],
          pendingDeleteRemote: ['notes/daily/images/old.png'],
        ),
        CloudSyncResult(
          ok: true,
          message: '手动同步完成：上传 0，下载 0，冲突 0',
          syncedAt: DateTime(2026, 6, 29, 1, 30),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsPage(
          localDataState: _state(initialConfig),
          localDataService: service,
          cloudSyncService: cloudSyncService,
        ),
      ),
    );

    await tester.tap(find.text('云同步').first);
    await tester.pump();
    await tester.tap(find.text('手动同步'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('cloud-sync-delete-confirm-dialog')),
      findsOneWidget,
    );
    expect(find.text('daily/old.md'), findsOneWidget);
    expect(find.text('daily/images/old.png'), findsOneWidget);

    final confirmButtonCenter = tester.getCenter(find.text('确认删除并同步'));
    await tester.tapAt(confirmButtonCenter);
    await tester.tapAt(confirmButtonCenter);
    await tester.pumpAndSettle();

    expect(cloudSyncService.syncCallCount, 2);
    expect(cloudSyncService.lastConfirmedDeleteLocal, ['notes/daily/old.md']);
    expect(cloudSyncService.lastConfirmedDeleteRemote, [
      'notes/daily/images/old.png',
    ]);
    expect(service.savedConfig.cloudSync.lastSyncedAt, isNotNull);
    expect(find.textContaining('手动同步完成'), findsOneWidget);
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
    await tester.tap(find.text('补全'));
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
      ModelReference.encode(
        providerId: service.savedConfig.providers.first.id,
        modelId: 'custom-chat-model',
      ),
    );

    await tester.tap(find.byKey(const ValueKey('default-model-编辑补全模型')));
    await tester.pumpAndSettle();
    expect(find.text('Custom Chat Edited'), findsWidgets);
    expect(find.text('GPT-4.1 Mini'), findsNothing);
    await tester.tap(find.text('Custom Chat Edited').last);
    await tester.pumpAndSettle();
    expect(
      service.savedConfig.defaultModels['editCompletionModel'],
      ModelReference.encode(
        providerId: service.savedConfig.providers.first.id,
        modelId: 'custom-chat-model',
      ),
    );
  });

  testWidgets('default model picker stores provider-qualified model refs', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const providers = [
      ProviderConfig(
        id: 'deepseek',
        enabled: true,
        name: 'DeepSeek',
        protocol: 'openaiCompatible',
        apiKey: 'key-1',
        baseUrl: 'https://api.deepseek.com',
        apiPath: '/chat/completions',
        models: [
          ModelConfig(modelId: 'chat-model', displayName: 'Shared Chat'),
        ],
      ),
      ProviderConfig(
        id: 'openrouter',
        enabled: true,
        name: 'OpenRouter',
        protocol: 'openaiCompatible',
        apiKey: 'key-2',
        baseUrl: 'https://openrouter.ai/api/v1',
        apiPath: '/chat/completions',
        models: [
          ModelConfig(modelId: 'chat-model', displayName: 'Shared Chat'),
        ],
      ),
    ];
    final service = _MemoryLocalDataService(
      AppConfig.defaults().copyWith(providers: providers),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsPage(
          localDataState: _state(service.savedConfig),
          localDataService: service,
        ),
      ),
    );

    await tester.tap(find.text('默认模型').first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('default-model-智能生成模型')));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.text('OpenRouter')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('OpenRouter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Shared Chat')).last,
    );
    await tester.pumpAndSettle();

    expect(
      service.savedConfig.defaultModels['intelligentGenerationModel'],
      ModelReference.encode(providerId: 'openrouter', modelId: 'chat-model'),
    );
    expect(find.text('Shared Chat · OpenRouter'), findsOneWidget);
  });

  testWidgets('provider editor preserves unknown protocol values', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const provider = ProviderConfig(
      id: 'custom-provider',
      enabled: true,
      name: 'Custom Provider',
      protocol: 'customProtocol',
      apiKey: 'key',
      baseUrl: 'https://api.example.com',
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
        ),
      ),
    );

    await tester.tap(find.text('供应商').first);
    await tester.pump();

    expect(find.text('customProtocol'), findsWidgets);

    final nameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.controller?.text == 'Custom Provider',
    );
    expect(nameField, findsOneWidget);

    await tester.enterText(nameField, 'Renamed Provider');
    await tester.pump();

    expect(service.savedConfig.providers.first.name, 'Renamed Provider');
    expect(service.savedConfig.providers.first.protocol, 'customProtocol');
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
    await tester.tap(
      find.byKey(const ValueKey('fetch-provider-models-button')),
    );
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

  testWidgets('provider connection test dialog selects model and stream mode', (
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
      models: [
        ModelConfig(modelId: 'alpha-model', displayName: 'Alpha Model'),
        ModelConfig(modelId: 'beta-model', displayName: 'Beta Model'),
      ],
    );
    final localDataService = _MemoryLocalDataService(
      AppConfig.defaults().copyWith(providers: const [provider]),
    );
    final aiClientService = _RecordingAiClientService();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsPage(
          localDataState: _state(localDataService.savedConfig),
          localDataService: localDataService,
          aiClientService: aiClientService,
        ),
      ),
    );

    await tester.tap(find.text('供应商').first);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('test-provider-connection-button')),
    );
    await tester.pumpAndSettle();

    final dialog = find.byKey(
      const ValueKey('provider-connection-test-dialog'),
    );
    expect(dialog, findsOneWidget);
    expect(find.text('选择模型'), findsOneWidget);

    await tester.tap(find.descendant(of: dialog, matching: find.text('选择模型')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final picker = find.byKey(
      const ValueKey('provider-connection-model-picker-dialog'),
    );
    expect(picker, findsOneWidget);

    await tester.tap(
      find.descendant(of: picker, matching: find.text('Beta Model')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(picker, findsNothing);
    expect(
      find.descendant(of: dialog, matching: find.text('Beta Model')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: dialog, matching: find.byType(Switch)),
    );
    await tester.pump();
    await tester.tap(find.descendant(of: dialog, matching: find.text('测试')));
    await tester.pumpAndSettle();

    expect(aiClientService.streamTested, isTrue);
    expect(aiClientService.nonStreamTested, isFalse);
    expect(aiClientService.lastModelId, 'beta-model');
    expect(dialog, findsOneWidget);
    expect(find.text('测试成功'), findsOneWidget);
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

Finder _cloudSyncTextFieldWithText(String text) {
  return find
      .byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == text,
      )
      .first;
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

class _RecordingAiClientService extends AiClientService {
  bool streamTested = false;
  bool nonStreamTested = false;
  String? lastModelId;

  @override
  Future<rust_ai.ProviderTestResult> testProviderConnection({
    required String appDataDir,
    required bool apiLogEnabled,
    required ProviderConfig provider,
    required ModelConfig model,
  }) async {
    nonStreamTested = true;
    lastModelId = model.modelId;
    return const rust_ai.ProviderTestResult(
      ok: true,
      message: 'non-stream-ok',
      errorCode: '',
    );
  }

  @override
  Future<rust_ai.ProviderTestResult> testProviderConnectionStream({
    required String appDataDir,
    required bool apiLogEnabled,
    required ProviderConfig provider,
    required ModelConfig model,
  }) async {
    streamTested = true;
    lastModelId = model.modelId;
    return const rust_ai.ProviderTestResult(
      ok: true,
      message: 'stream-ok',
      errorCode: '',
    );
  }
}

class _FakeCloudSyncService extends CloudSyncService {
  _FakeCloudSyncService({List<CloudSyncResult>? syncResults})
    : syncResults =
          syncResults ??
          [
            CloudSyncResult(
              ok: true,
              message: '手动同步完成：上传 1，下载 0，冲突 0',
              uploaded: 1,
              syncedAt: DateTime(2026, 6, 28, 22, 0),
            ),
          ];

  bool tested = false;
  bool synced = false;
  int syncCallCount = 0;
  final List<CloudSyncResult> syncResults;
  List<String> lastConfirmedDeleteLocal = const [];
  List<String> lastConfirmedDeleteRemote = const [];

  @override
  Future<CloudSyncResult> testConnection(CloudSyncConfig config) async {
    tested = true;
    return const CloudSyncResult(ok: true, message: '连接成功');
  }

  @override
  Future<CloudSyncResult> sync({
    required LocalDataState localDataState,
    required CloudSyncTrigger trigger,
    List<String> confirmedDeleteLocal = const [],
    List<String> confirmedDeleteRemote = const [],
  }) async {
    synced = true;
    lastConfirmedDeleteLocal = confirmedDeleteLocal;
    lastConfirmedDeleteRemote = confirmedDeleteRemote;
    final index = syncCallCount < syncResults.length
        ? syncCallCount
        : syncResults.length - 1;
    syncCallCount += 1;
    return syncResults[index];
  }
}
