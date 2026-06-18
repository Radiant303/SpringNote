import 'dart:convert';
import 'dart:io';

import '../models/app_config.dart';
import '../models/local_data_state.dart';

class LocalDataService {
  const LocalDataService({this.appDataPath});

  final String? appDataPath;

  Future<LocalDataState> initialize() async {
    final root = await _resolveDataDirectory();
    final notes = Directory(_join(root.path, 'notes'));
    final daily = Directory(_join(notes.path, 'daily'));
    final weekly = Directory(_join(notes.path, 'weekly'));
    final monthly = Directory(_join(notes.path, 'monthly'));

    await Future.wait([
      root.create(recursive: true),
      daily.create(recursive: true),
      weekly.create(recursive: true),
      monthly.create(recursive: true),
    ]);

    final configFile = File(_join(root.path, 'config.json'));
    final config = await _readOrCreateConfig(configFile);

    return LocalDataState(
      dataDirectory: root.path,
      configPath: configFile.path,
      dailyNotesDirectory: daily.path,
      weeklyNotesDirectory: weekly.path,
      monthlyNotesDirectory: monthly.path,
      config: config,
    );
  }

  Future<AppConfig> readConfig() async {
    final root = await _resolveDataDirectory();
    final configFile = File(_join(root.path, 'config.json'));
    return _readOrCreateConfig(configFile);
  }

  Future<void> saveConfig(AppConfig config) async {
    final root = await _resolveDataDirectory();
    await root.create(recursive: true);
    await _writeConfig(File(_join(root.path, 'config.json')), config);
  }

  Future<AppConfig> _readOrCreateConfig(File file) async {
    if (!await file.exists()) {
      final config = AppConfig.defaults();
      await _writeConfig(file, config);
      return config;
    }

    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      final config = AppConfig.defaults();
      await _writeConfig(file, config);
      return config;
    }

    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('config.json must contain a JSON object');
    }

    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    return AppConfig.fromJson(json);
  }

  Future<void> _writeConfig(File file, AppConfig config) async {
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(config.toJson())}\n');
  }

  Future<Directory> _resolveDataDirectory() async {
    final basePath = appDataPath ?? Platform.environment['APPDATA'];
    if (basePath == null || basePath.trim().isEmpty) {
      throw StateError(
        'APPDATA is not available; cannot initialize SpringNote data.',
      );
    }
    return Directory(_join(basePath, 'SpringNote'));
  }

  String _join(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }
}
