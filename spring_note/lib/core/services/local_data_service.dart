import 'dart:convert';
import 'dart:io';

import '../models/app_config.dart';
import '../models/local_data_state.dart';
import 'security_scoped_directory_access.dart';

class LocalDataService {
  const LocalDataService({
    this.appDataPath,
    this.executableDirectoryPath,
    this.securityScopedDirectoryAccess =
        const MethodChannelSecurityScopedDirectoryAccess(),
  });

  static const String _configFileName = 'config.json';
  static const String _directoryPointerFileName = 'data-directory.json';
  static const String _notesDirectoryName = 'notes';
  static const String _dailyDirectoryName = 'daily';
  static const String _weeklyDirectoryName = 'weekly';
  static const String _monthlyDirectoryName = 'monthly';
  static const String _noteIndexDatabaseName = '.springnote-note-index.db';
  static const String _appDataDirectoryName = 'SpringNote';
  static const String _windowsAppDataEnv = 'APPDATA';
  static const String _homeEnv = 'HOME';
  static const String _userProfileEnv = 'USERPROFILE';
  static const String _xdgDataHomeEnv = 'XDG_DATA_HOME';
  static const String _macApplicationSupportDirectory = 'Application Support';
  static const String _macLibraryDirectory = 'Library';
  static const String _linuxLocalDirectory = '.local';
  static const String _linuxShareDirectory = 'share';
  static const String _jsonIndent = '  ';
  static const String _writeTestFileName = '.spring_note_write_test';
  static const String _writeTestContent = 'ok';
  static const int _backslash = 92;
  static const int _quote = 34;
  static const int _openingBrace = 123;
  static const int _closingBrace = 125;
  static const int _jsonObjectEndOffset = 1;
  static const int _backupTimestampLength = 17;
  static int _temporaryFileCounter = 0;

  final String? appDataPath;
  final String? executableDirectoryPath;
  final SecurityScopedDirectoryAccess securityScopedDirectoryAccess;

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
      await _syncSecurityScopedAccess(targetRoot);
      await _writeActiveDataDirectoryPointer(config.customDataDirectory);
      return _buildState(targetRoot, config: config);
    }

    if (_isWithin(targetRoot.path, currentRoot.path)) {
      throw ArgumentError('保存目录不能选择当前数据目录的子目录。');
    }

    if (await FileSystemEntity.isFile(targetRoot.path)) {
      throw ArgumentError('保存目录不能是一个文件。');
    }

    final targetConfigFile = File(_join(targetRoot.path, _configFileName));
    final targetAlreadyHasData = await targetConfigFile.exists();

    await targetRoot.create(recursive: true);
    if (!targetAlreadyHasData) {
      await _deleteDerivedNoteIndexFiles(targetRoot);
      await _copyDirectoryContents(currentRoot, targetRoot);
    }

    await _syncSecurityScopedAccess(targetRoot, previousRoot: currentRoot);
    final config = targetAlreadyHasData
        ? await _readOrCreateConfig(targetConfigFile)
        : currentState.config.copyWith(
            customDataDirectory: await _customDirectoryFor(targetRoot),
          );
    if (!targetAlreadyHasData) {
      await _writeConfig(targetConfigFile, config);
    }
    await _writeActiveDataDirectoryPointer(
      await _customDirectoryFor(targetRoot),
    );

    return _buildState(targetRoot, config: config);
  }

  Future<LocalDataState> _buildState(
    Directory root, {
    AppConfig? config,
  }) async {
    final notes = Directory(_join(root.path, _notesDirectoryName));
    final daily = Directory(_join(notes.path, _dailyDirectoryName));
    final weekly = Directory(_join(notes.path, _weeklyDirectoryName));
    final monthly = Directory(_join(notes.path, _monthlyDirectoryName));

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
    await _ensureActiveDataDirectoryPointer(nextConfig.customDataDirectory);

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

    var repaired = false;
    var decoded = _tryDecodeJsonMap(content);
    if (decoded == null) {
      await _backupMalformedFile(file);
      decoded = _tryDecodeFirstJsonMap(content);
      if (decoded == null) {
        final config = AppConfig.defaults();
        await _writeConfig(file, config);
        return config;
      }
      repaired = true;
    }

    final config = AppConfig.fromJson(decoded);
    if (repaired) {
      await _writeConfig(file, config);
    }
    return config;
  }

  Future<void> _writeConfig(File file, AppConfig config) async {
    const encoder = JsonEncoder.withIndent(_jsonIndent);
    await file.parent.create(recursive: true);
    await file.writeAsString('${encoder.convert(config.toJson())}\n');
  }

  Future<Directory> _resolveDataDirectory() async {
    final defaultRoot = await _resolveDefaultDataDirectory();
    final pointerPath = await _readActiveDataDirectoryPointer(defaultRoot);
    if (pointerPath != null) {
      final pointerRoot = Directory(pointerPath);
      if (await _ensureDirectoryAccess(pointerRoot)) {
        return pointerRoot;
      }
      return defaultRoot;
    }

    final defaultConfigFile = File(_join(defaultRoot.path, _configFileName));
    if (await defaultConfigFile.exists()) {
      final config = await _readOrCreateConfig(defaultConfigFile);
      if (config.customDataDirectory != null) {
        final customRoot = Directory(config.customDataDirectory!);
        if (await _ensureDirectoryAccess(customRoot)) {
          return customRoot;
        }
      }
    }

    return defaultRoot;
  }

  Future<Directory> _resolveDefaultDataDirectory() async {
    final basePath = appDataPath ?? _platformDataDirectoryPath();
    if (basePath == null || basePath.trim().isEmpty) {
      throw StateError(
        'No user data directory is available; cannot initialize SpringNote data.',
      );
    }
    return Directory(_join(basePath, _appDataDirectoryName));
  }

  String? _platformDataDirectoryPath() {
    if (Platform.isWindows) {
      return Platform.environment[_windowsAppDataEnv];
    }
    if (Platform.isMacOS) {
      final home = Platform.environment[_homeEnv];
      if (home == null || home.trim().isEmpty) {
        return null;
      }
      return _join(
        _join(home, _macLibraryDirectory),
        _macApplicationSupportDirectory,
      );
    }
    if (Platform.isLinux) {
      final xdgDataHome = Platform.environment[_xdgDataHomeEnv];
      if (xdgDataHome != null && xdgDataHome.trim().isNotEmpty) {
        return xdgDataHome;
      }
      final home = Platform.environment[_homeEnv];
      if (home == null || home.trim().isEmpty) {
        return null;
      }
      return _join(_join(home, _linuxLocalDirectory), _linuxShareDirectory);
    }
    final home =
        Platform.environment[_homeEnv] ??
        Platform.environment[_userProfileEnv] ??
        Directory.systemTemp.path;
    return home;
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

  Future<bool> _ensureDirectoryAccess(Directory root) async {
    if (await _customDirectoryFor(root) == null) {
      return true;
    }
    if (await securityScopedDirectoryAccess.startAccessing(root.path)) {
      return true;
    }
    return false;
  }

  Future<void> _syncSecurityScopedAccess(
    Directory root, {
    Directory? previousRoot,
  }) async {
    final customPath = await _customDirectoryFor(root);
    if (customPath == null) {
      if (previousRoot != null) {
        final previousCustomPath = await _customDirectoryFor(previousRoot);
        if (previousCustomPath != null) {
          await securityScopedDirectoryAccess.removeBookmark(previousRoot.path);
        }
      }
      return;
    }

    if (!await securityScopedDirectoryAccess.saveBookmark(root.path)) {
      throw FileSystemException('无法保存 macOS 文件夹访问授权，请重新选择保存目录。', root.path);
    }
    await securityScopedDirectoryAccess.startAccessing(root.path);
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
    var decoded = _tryDecodeJsonMap(content);
    if (decoded == null) {
      await _backupMalformedFile(file);
      decoded = _tryDecodeFirstJsonMap(content);
      if (decoded == null) {
        return null;
      }
      await _writeJson(file, decoded);
    }
    if (decoded.isEmpty) {
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

    await file.parent.create(recursive: true);
    await _writeJson(file, {'dataDirectory': activePath});
  }

  Future<void> _ensureActiveDataDirectoryPointer(String? customPath) async {
    final defaultRoot = await _resolveDefaultDataDirectory();
    final file = await _activeDataDirectoryPointerFile();
    if (await file.exists()) {
      return;
    }
    final activePath = customPath == null || customPath.trim().isEmpty
        ? defaultRoot.path
        : customPath.trim();
    await _writeJson(file, {'dataDirectory': activePath});
  }

  Future<void> _writeJson(File file, Map<String, Object?> json) async {
    const encoder = JsonEncoder.withIndent(_jsonIndent);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp-${_temporaryFileSuffix()}');
    try {
      await temporary.writeAsString('${encoder.convert(json)}\n', flush: true);
      await temporary.rename(file.path);
    } finally {
      await _deleteTemporaryFile(temporary);
    }
  }

  Map<String, Object?>? _tryDecodeJsonMap(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return null;
      }
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?>? _tryDecodeFirstJsonMap(String content) {
    final end = _firstJsonObjectEnd(content);
    if (end == null) {
      return null;
    }
    return _tryDecodeJsonMap(content.substring(0, end));
  }

  int? _firstJsonObjectEnd(String content) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    var started = false;

    for (var index = 0; index < content.length; index++) {
      final codeUnit = content.codeUnitAt(index);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (codeUnit == _backslash) {
          escaped = true;
        } else if (codeUnit == _quote) {
          inString = false;
        }
        continue;
      }

      if (codeUnit == _quote) {
        inString = true;
        continue;
      }
      if (codeUnit == _openingBrace) {
        depth++;
        started = true;
        continue;
      }
      if (codeUnit == _closingBrace) {
        if (!started) {
          return null;
        }
        depth--;
        if (depth == 0) {
          return index + _jsonObjectEndOffset;
        }
        if (depth < 0) {
          return null;
        }
      }
    }

    return null;
  }

  Future<void> _backupMalformedFile(File file) async {
    if (!await file.exists()) {
      return;
    }
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .padRight(_backupTimestampLength, '0')
        .substring(0, _backupTimestampLength);
    await file.copy('${file.path}.invalid-$stamp');
  }

  Future<File> _activeDataDirectoryPointerFile() async {
    final executablePointer = File(
      _join(await _executableDirectoryPath(), _directoryPointerFileName),
    );
    if (await _canUsePointerFile(executablePointer)) {
      return executablePointer;
    }

    final defaultRoot = await _resolveDefaultDataDirectory();
    return File(_join(defaultRoot.path, _directoryPointerFileName));
  }

  Future<String> _executableDirectoryPath() async {
    final override = executableDirectoryPath?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return File(Platform.resolvedExecutable).parent.path;
  }

  Future<bool> _canUsePointerFile(File file) async {
    final probe = File(
      _join(file.parent.path, '$_writeTestFileName-${_temporaryFileSuffix()}'),
    );
    try {
      await file.parent.create(recursive: true);
      await probe.writeAsString(_writeTestContent, flush: true);
      return true;
    } catch (_) {
      return false;
    } finally {
      await _deleteTemporaryFile(probe);
    }
  }

  String _temporaryFileSuffix() {
    final counter = _temporaryFileCounter++;
    return '$pid-${DateTime.now().microsecondsSinceEpoch}-$counter';
  }

  Future<void> _deleteTemporaryFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // A failed cleanup must not replace a successful pointer operation.
    }
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
      if (name == _directoryPointerFileName || _isDerivedNoteIndexFile(name)) {
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

  Future<void> _deleteDerivedNoteIndexFiles(Directory root) async {
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File(_join(root.path, '$_noteIndexDatabaseName$suffix'));
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  bool _isDerivedNoteIndexFile(String name) {
    return name == _noteIndexDatabaseName ||
        name == '$_noteIndexDatabaseName-wal' ||
        name == '$_noteIndexDatabaseName-shm';
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
