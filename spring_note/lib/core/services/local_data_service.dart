import 'dart:convert';
import 'dart:io';

import '../models/app_config.dart';
import '../models/local_data_state.dart';

class LocalDataService {
  const LocalDataService({this.appDataPath});

  static const String _configFileName = 'config.json';
  static const String _directoryPointerFileName = 'data-directory.json';

  final String? appDataPath;

  Future<LocalDataState> initialize() async {
    final root = await _resolveDataDirectory();
    return _buildState(root);
  }

  Future<AppConfig> readConfig() async {
    final root = await _resolveDataDirectory();
    final configFile = File(_join(root.path, _configFileName));
    return _readOrCreateConfig(configFile);
  }

  Future<void> saveConfig(AppConfig config) async {
    final root = await _resolveDataDirectory();
    await root.create(recursive: true);
    await _writeConfig(
      File(_join(root.path, _configFileName)),
      config.copyWith(customDataDirectory: await _customDirectoryFor(root)),
    );
  }

  Future<LocalDataState> migrateDataDirectory({
    required LocalDataState currentState,
    required String? targetDirectory,
  }) async {
    final currentRoot = Directory(currentState.dataDirectory);
    final defaultRoot = await _resolveDefaultDataDirectory();
    final targetRoot = _targetDirectory(targetDirectory, defaultRoot);

    if (_samePath(currentRoot.path, targetRoot.path)) {
      final config = currentState.config.copyWith(
        customDataDirectory: await _customDirectoryFor(targetRoot),
      );
      await _writeActiveDataDirectoryPointer(config.customDataDirectory);
      return _buildState(targetRoot, config: config);
    }

    if (_isWithin(targetRoot.path, currentRoot.path)) {
      throw ArgumentError('保存目录不能选择当前数据目录的子目录。');
    }

    if (await FileSystemEntity.isFile(targetRoot.path)) {
      throw ArgumentError('保存目录不能是一个文件。');
    }

    await targetRoot.create(recursive: true);
    await _copyDirectoryContents(currentRoot, targetRoot);

    final config = currentState.config.copyWith(
      customDataDirectory: await _customDirectoryFor(targetRoot),
    );
    await _writeConfig(File(_join(targetRoot.path, _configFileName)), config);
    await _writeActiveDataDirectoryPointer(config.customDataDirectory);

    return _buildState(targetRoot, config: config);
  }

  Future<LocalDataState> _buildState(
    Directory root, {
    AppConfig? config,
  }) async {
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

    final configFile = File(_join(root.path, _configFileName));
    final expectedCustomDirectory = await _customDirectoryFor(root);
    var nextConfig = config ?? await _readOrCreateConfig(configFile);
    if (nextConfig.customDataDirectory != expectedCustomDirectory) {
      nextConfig = nextConfig.copyWith(
        customDataDirectory: expectedCustomDirectory,
      );
      await _writeConfig(configFile, nextConfig);
    } else if (config != null) {
      await _writeConfig(configFile, nextConfig);
    }
    await _writeActiveDataDirectoryPointer(nextConfig.customDataDirectory);

    return LocalDataState(
      dataDirectory: root.path,
      configPath: configFile.path,
      dailyNotesDirectory: daily.path,
      weeklyNotesDirectory: weekly.path,
      monthlyNotesDirectory: monthly.path,
      config: nextConfig,
    );
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
    await file.parent.create(recursive: true);
    await file.writeAsString('${encoder.convert(config.toJson())}\n');
  }

  Future<Directory> _resolveDataDirectory() async {
    final defaultRoot = await _resolveDefaultDataDirectory();
    final pointerPath = await _readActiveDataDirectoryPointer(defaultRoot);
    if (pointerPath != null) {
      return Directory(pointerPath);
    }

    final defaultConfigFile = File(_join(defaultRoot.path, _configFileName));
    if (await defaultConfigFile.exists()) {
      final config = await _readOrCreateConfig(defaultConfigFile);
      if (config.customDataDirectory != null) {
        return Directory(config.customDataDirectory!);
      }
    }

    return defaultRoot;
  }

  Future<Directory> _resolveDefaultDataDirectory() async {
    final basePath = appDataPath ?? Platform.environment['APPDATA'];
    if (basePath == null || basePath.trim().isEmpty) {
      throw StateError(
        'APPDATA is not available; cannot initialize SpringNote data.',
      );
    }
    return Directory(_join(basePath, 'SpringNote'));
  }

  Directory _targetDirectory(String? path, Directory defaultRoot) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return defaultRoot;
    }
    return Directory(trimmed).absolute;
  }

  Future<String?> _customDirectoryFor(Directory root) async {
    final defaultRoot = await _resolveDefaultDataDirectory();
    return _samePath(root.path, defaultRoot.path) ? null : root.path;
  }

  Future<String?> _readActiveDataDirectoryPointer(Directory defaultRoot) async {
    final file = await _activeDataDirectoryPointerFile();
    if (!await file.exists()) {
      return null;
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      return null;
    }
    final path = decoded['dataDirectory'];
    if (path is! String || path.trim().isEmpty) {
      return null;
    }
    return path.trim();
  }

  Future<void> _writeActiveDataDirectoryPointer(String? customPath) async {
    final defaultRoot = await _resolveDefaultDataDirectory();
    final file = await _activeDataDirectoryPointerFile();
    final activePath = customPath == null || customPath.trim().isEmpty
        ? defaultRoot.path
        : customPath.trim();

    const encoder = JsonEncoder.withIndent('  ');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${encoder.convert({'dataDirectory': activePath})}\n',
    );
  }

  Future<File> _activeDataDirectoryPointerFile() async {
    return File(
      _join(await _executableDirectoryPath(), _directoryPointerFileName),
    );
  }

  Future<String> _executableDirectoryPath() async {
    return File(Platform.resolvedExecutable).parent.path;
  }

  Future<void> _copyDirectoryContents(
    Directory source,
    Directory target,
  ) async {
    if (!await source.exists()) {
      return;
    }
    await target.create(recursive: true);

    await for (final entity in source.list(followLinks: false)) {
      final name = _fileName(entity.path);
      if (name == _directoryPointerFileName) {
        continue;
      }
      final targetPath = _join(target.path, name);
      if (entity is Directory) {
        await _copyDirectoryContents(entity, Directory(targetPath));
      } else if (entity is File) {
        await File(targetPath).parent.create(recursive: true);
        await entity.copy(targetPath);
      } else if (entity is Link) {
        final link = Link(targetPath);
        if (await link.exists()) {
          await link.delete();
        }
        await link.create(await entity.target(), recursive: true);
      }
    }
  }

  bool _isWithin(String childPath, String parentPath) {
    final child = _normalizeForCompare(childPath);
    final parent = _normalizeForCompare(parentPath);
    if (child == parent) {
      return false;
    }
    return child.startsWith('$parent${Platform.pathSeparator}');
  }

  bool _samePath(String left, String right) {
    return _normalizeForCompare(left) == _normalizeForCompare(right);
  }

  String _normalizeForCompare(String path) {
    var normalized = Directory(path).absolute.path;
    while (normalized.endsWith(Platform.pathSeparator) &&
        normalized.length > Platform.pathSeparator.length) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String _fileName(String path) {
    return path.split(RegExp(r'[\\/]')).last;
  }

  String _join(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }
}
