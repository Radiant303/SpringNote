import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'tray_service.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.changeTime,
    required this.downloadUrl,
    required this.changelog,
  });

  final String version;
  final String changeTime;
  final String downloadUrl;
  final String changelog;

  String get installerName {
    final uri = Uri.tryParse(downloadUrl);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return downloadUrl.split('/').last;
  }
}

enum UpdateInstallStage {
  preparing,
  downloading,
  verifying,
  extracting,
  installing,
  launching,
}

class UpdateInstallProgress {
  const UpdateInstallProgress({
    required this.stage,
    this.receivedBytes = 0,
    this.totalBytes,
    this.fractionOverride,
  });

  final UpdateInstallStage stage;
  final int receivedBytes;
  final int? totalBytes;
  final double? fractionOverride;

  double? get fraction {
    final explicitFraction = fractionOverride;
    if (explicitFraction != null) {
      return explicitFraction.clamp(0, 1).toDouble();
    }
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return receivedBytes.clamp(0, total) / total;
  }
}

class UpdateInstallException implements Exception {
  const UpdateInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum UpdateCheckStatus { idle, updateAvailable, failed }

enum UpdateCheckFailureKind { none, offline, temporary, permanent }

enum UpdateCheckMode { background, userInitiated }

class UpdateCheckResult {
  const UpdateCheckResult._({
    required this.status,
    required this.currentVersion,
    this.failureKind = UpdateCheckFailureKind.none,
    this.latest,
  });

  factory UpdateCheckResult.updateAvailable({
    required String currentVersion,
    required AppUpdateInfo latest,
  }) {
    return UpdateCheckResult._(
      status: UpdateCheckStatus.updateAvailable,
      currentVersion: currentVersion,
      latest: latest,
    );
  }

  factory UpdateCheckResult.failed({required String currentVersion}) {
    return UpdateCheckResult._(
      status: UpdateCheckStatus.failed,
      currentVersion: currentVersion,
      failureKind: UpdateCheckFailureKind.permanent,
    );
  }

  factory UpdateCheckResult.failedWithKind({
    required String currentVersion,
    required UpdateCheckFailureKind failureKind,
  }) {
    return UpdateCheckResult._(
      status: UpdateCheckStatus.failed,
      currentVersion: currentVersion,
      failureKind: failureKind,
    );
  }

  static const idle = UpdateCheckResult._(
    status: UpdateCheckStatus.idle,
    currentVersion: '',
  );

  final UpdateCheckStatus status;
  final String currentVersion;
  final UpdateCheckFailureKind failureKind;
  final AppUpdateInfo? latest;
}

class UpdateCheckService {
  UpdateCheckService({
    this.trayService = const TrayService(),
    this.macUpdateInstaller = const MacUpdateInstaller(),
  });

  static const _timeout = Duration(seconds: 10);
  static const _defaultUpdateBaseUrl =
      'https://api.github.com/repos/Radiant303/SpringNote/contents/update';
  static const _configuredUpdateBaseUrl = String.fromEnvironment(
    'SPRINGNOTE_UPDATE_BASE_URL',
  );
  final TrayService trayService;
  final MacUpdateInstaller macUpdateInstaller;

  Future<UpdateCheckResult> check({
    UpdateCheckMode mode = UpdateCheckMode.background,
  }) async {
    final currentVersion = await loadCurrentVersion();
    if (!_supportsUpdates) {
      return UpdateCheckResult.failed(currentVersion: currentVersion);
    }

    return previewLatest();
  }

  Future<void> installUpdate(
    AppUpdateInfo latest, {
    void Function(UpdateInstallProgress progress)? onProgress,
  }) async {
    if (Platform.isWindows) {
      await _installWindowsUpdate(latest, onProgress: onProgress);
      return;
    }

    if (Platform.isMacOS) {
      await _installMacUpdate(latest, onProgress: onProgress);
      return;
    }

    throw const UpdateInstallException('当前平台暂不支持自动更新。');
  }

  Future<void> _installMacUpdate(
    AppUpdateInfo latest, {
    void Function(UpdateInstallProgress progress)? onProgress,
  }) async {
    await macUpdateInstaller.installUpdate(
      feedUrl: _sparkleFeedUrlForVersion(latest.version),
      onProgress: onProgress,
    );
  }

  Future<UpdateCheckResult> previewLatest() async {
    final currentVersion = await loadCurrentVersion();
    final endpoint = _platformEndpoint();
    if (endpoint == null) {
      return UpdateCheckResult.failed(currentVersion: currentVersion);
    }

    try {
      final updateJson = await _readUrl(endpoint);
      final decoded = jsonDecode(updateJson);
      if (decoded is! Map<String, Object?>) {
        return UpdateCheckResult.failed(currentVersion: currentVersion);
      }

      final latestVersion = decoded['version']?.toString().trim() ?? '';
      final changeTime = decoded['change_time']?.toString().trim() ?? '';
      final downloadUrl = decoded['download_url']?.toString().trim() ?? '';
      if (latestVersion.isEmpty || downloadUrl.isEmpty) {
        return UpdateCheckResult.failed(currentVersion: currentVersion);
      }

      if (_compareVersions(latestVersion, currentVersion) <= 0) {
        return UpdateCheckResult.idle;
      }

      final changelog = await _readChangelog();
      return UpdateCheckResult.updateAvailable(
        currentVersion: currentVersion,
        latest: AppUpdateInfo(
          version: latestVersion,
          changeTime: changeTime.isEmpty ? '未提供' : changeTime,
          downloadUrl: downloadUrl,
          changelog: changelog,
        ),
      );
    } on FormatException {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: UpdateCheckFailureKind.permanent,
      );
    } on _UpdateHttpStatusException catch (error) {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: error.temporary
            ? UpdateCheckFailureKind.temporary
            : UpdateCheckFailureKind.permanent,
      );
    } on SocketException {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: UpdateCheckFailureKind.offline,
      );
    } on TimeoutException {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: UpdateCheckFailureKind.temporary,
      );
    } on HandshakeException {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: UpdateCheckFailureKind.temporary,
      );
    } catch (_) {
      return UpdateCheckResult.failedWithKind(
        currentVersion: currentVersion,
        failureKind: UpdateCheckFailureKind.temporary,
      );
    }
  }

  bool get _supportsUpdates => Platform.isWindows || Platform.isMacOS;

  Future<String> loadCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version.trim().isEmpty
          ? '1.0.0'
          : packageInfo.version.trim();
    } catch (_) {
      return '1.0.0';
    }
  }

  Future<String> _readChangelog() async {
    try {
      final changelog = await _readUrl(_updateUrl('LATESTCHANGELOG.md'));
      return changelog.trim().isEmpty ? '暂无更新内容。' : changelog;
    } catch (_) {
      return '更新内容加载失败。';
    }
  }

  Future<String> _readUrl(String url) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final uri = Uri.parse(url);
      final request = await client.getUrl(uri).timeout(_timeout);
      if (_isGitHubContentsApi(uri)) {
        request.headers.set('Accept', 'application/vnd.github.raw+json');
        request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      }
      final response = await request.close().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _UpdateHttpStatusException(response.statusCode);
      }
      return await response.transform(utf8.decoder).join().timeout(_timeout);
    } finally {
      client.close(force: true);
    }
  }

  bool _isGitHubContentsApi(Uri uri) {
    return uri.host == 'api.github.com' &&
        uri.pathSegments.length >= 5 &&
        uri.pathSegments[0] == 'repos' &&
        uri.pathSegments.contains('contents');
  }

  Future<void> _installWindowsUpdate(
    AppUpdateInfo latest, {
    void Function(UpdateInstallProgress progress)? onProgress,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp(
      'spring_note_update_',
    );
    final installer = File(
      _joinPath(tempDir.path, _safeFileName(latest.installerName)),
    );

    await _downloadFile(latest.downloadUrl, installer, onProgress: onProgress);
    onProgress?.call(
      const UpdateInstallProgress(stage: UpdateInstallStage.verifying),
    );
    await _verifyWindowsInstallerChecksum(latest, installer);
    onProgress?.call(
      const UpdateInstallProgress(stage: UpdateInstallStage.launching),
    );
    await trayService.prepareForApplicationExit();
    await _launchWindowsUpdater(tempDir, installer);
    await trayService.quitForUpdate();
  }

  Future<void> _launchWindowsUpdater(Directory tempDir, File installer) async {
    final app = File(Platform.resolvedExecutable);
    final updater = File(
      _joinPath(app.parent.path, 'SpringNoteUpdater.exe'),
    );
    if (!await updater.exists()) {
      throw const UpdateInstallException('更新助手缺失，请下载最新安装包手动更新。');
    }
    final updaterCopy = File(_joinPath(tempDir.path, 'SpringNoteUpdater.exe'));
    await updater.copy(updaterCopy.path);

    final log = File(_joinPath(tempDir.path, 'springnote_update_inno.log'));
    final helperLog = File(
      _joinPath(tempDir.path, 'springnote_update_helper.log'),
    );

    await Process.start(updaterCopy.path, [
      '--installer',
      installer.path,
      '--app',
      app.path,
      '--wait-pid',
      pid.toString(),
      '--inno-log',
      log.path,
      '--helper-log',
      helperLog.path,
    ], mode: ProcessStartMode.detached);
  }

  Future<void> _downloadFile(
    String url,
    File file, {
    void Function(UpdateInstallProgress progress)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UpdateInstallException('下载安装包失败 (${response.statusCode})');
      }

      await file.parent.create(recursive: true);
      sink = file.openWrite();
      var received = 0;
      final total = response.contentLength > 0 ? response.contentLength : null;
      onProgress?.call(
        UpdateInstallProgress(
          stage: UpdateInstallStage.downloading,
          totalBytes: total,
        ),
      );
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(
          UpdateInstallProgress(
            stage: UpdateInstallStage.downloading,
            receivedBytes: received,
            totalBytes: total,
          ),
        );
      }
    } on UpdateInstallException {
      rethrow;
    } on TimeoutException {
      throw const UpdateInstallException('下载更新超时，请稍后重试。');
    } on SocketException {
      throw const UpdateInstallException('网络不可用，请检查连接后重试。');
    } catch (_) {
      throw const UpdateInstallException('下载安装包失败，请稍后重试。');
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  Future<void> _verifyWindowsInstallerChecksum(
    AppUpdateInfo latest,
    File installer,
  ) async {
    final expected = await _readExpectedSha256(latest);
    final actual = await _calculateWindowsSha256(installer);
    if (actual.toLowerCase() != expected.toLowerCase()) {
      throw const UpdateInstallException('安装包校验失败，请稍后重试。');
    }
  }

  Future<String> _readExpectedSha256(AppUpdateInfo latest) async {
    final downloadUri = Uri.parse(latest.downloadUrl);
    final segments = downloadUri.pathSegments;
    if (segments.isEmpty) {
      throw const UpdateInstallException('无法读取安装包校验信息。');
    }
    final checksumUri = downloadUri.replace(
      pathSegments: [...segments.take(segments.length - 1), 'SHA256SUMS.txt'],
    );
    final checksums = await _readUrl(checksumUri.toString());
    final fileName = latest.installerName;
    for (final line in checksums.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }
      final hash = parts.first;
      final name = parts.last.replaceFirst(RegExp(r'^\*'), '');
      if (name == fileName && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) {
        return hash;
      }
    }
    throw const UpdateInstallException('未找到安装包校验信息。');
  }

  Future<String> _calculateWindowsSha256(File file) async {
    final result = await Process.run('certutil', [
      '-hashfile',
      file.path,
      'SHA256',
    ]);
    if (result.exitCode != 0) {
      throw const UpdateInstallException('安装包校验失败，请稍后重试。');
    }
    final output = '${result.stdout}\n${result.stderr}';
    for (final line in output.split('\n')) {
      final normalized = line.replaceAll(RegExp(r'\s+'), '').trim();
      if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(normalized)) {
        return normalized;
      }
    }
    throw const UpdateInstallException('安装包校验失败，请稍后重试。');
  }

  String _safeFileName(String fileName) {
    final sanitized = fileName.replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '_',
    );
    return sanitized.trim().isEmpty ? 'SpringNote-update.exe' : sanitized;
  }

  String _joinPath(String directory, String name) {
    final separator = Platform.pathSeparator;
    if (directory.endsWith(separator)) {
      return '$directory$name';
    }
    return '$directory$separator$name';
  }

  String? _platformEndpoint() {
    if (Platform.isWindows) {
      return _updateUrl('windows.json');
    }
    if (Platform.isLinux) {
      return _updateUrl('linux.json');
    }
    if (Platform.isMacOS) {
      return _updateUrl('mac.json');
    }
    return null;
  }

  String _updateUrl(String fileName) {
    final configured = _configuredUpdateBaseUrl.trim();
    final base = configured.isEmpty ? _defaultUpdateBaseUrl : configured;
    return '${base.replaceFirst(RegExp(r'/+$'), '')}/$fileName';
  }

  String _sparkleFeedUrlForVersion(String version) {
    final configured = _configuredUpdateBaseUrl.trim();
    final uri = Uri.tryParse(
      configured.isEmpty ? _defaultUpdateBaseUrl : configured,
    );
    if (uri == null || !_isGitHubContentsApi(uri)) {
      return _updateUrl('appcast.xml');
    }
    final segments = uri.pathSegments;
    if (segments.length < 5) {
      return _updateUrl('appcast.xml');
    }
    final owner = segments[1];
    final repo = segments[2];
    return 'https://github.com/$owner/$repo/releases/download/$version/appcast.xml';
  }

  int _compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    for (var index = 0; index < 3; index++) {
      final diff = leftParts[index] - rightParts[index];
      if (diff != 0) {
        return diff;
      }
    }
    return 0;
  }

  List<int> _versionParts(String version) {
    final normalized = version.split('+').first.trim();
    final parts = normalized.split('.');
    return [
      for (var index = 0; index < 3; index++)
        index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0,
    ];
  }
}

class MacUpdateInstaller {
  const MacUpdateInstaller({
    this.methodChannel = const MethodChannel('spring_note/mac_update'),
    this.eventChannel = const EventChannel('spring_note/mac_update_events'),
  });

  final MethodChannel methodChannel;
  final EventChannel eventChannel;

  Future<void> installUpdate({
    required String feedUrl,
    void Function(UpdateInstallProgress progress)? onProgress,
  }) async {
    if (!Platform.isMacOS) {
      throw const UpdateInstallException('当前平台暂不支持 macOS 自动更新。');
    }

    final completer = Completer<void>();
    StreamSubscription<dynamic>? subscription;

    void fail(String message) {
      if (!completer.isCompleted) {
        completer.completeError(UpdateInstallException(message));
      }
    }

    void complete() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    subscription = eventChannel.receiveBroadcastStream().listen(
      (event) {
        final data = _eventMap(event);
        if (data == null) {
          return;
        }

        final progress = _progressFromEvent(data);
        if (progress != null) {
          onProgress?.call(progress);
        }

        final type = data['type']?.toString();
        if (type == 'error') {
          fail(_eventMessage(data, 'macOS 更新失败，请稍后重试。'));
        } else if (type == 'notFound') {
          fail(_eventMessage(data, '没有找到可安装的 macOS 更新。'));
        } else if (type == 'dismissed') {
          fail('macOS 更新流程已结束，请稍后重试。');
        } else if (type == 'relaunching' || type == 'installed') {
          complete();
        }
      },
      onError: (_) => fail('macOS 更新失败，请稍后重试。'),
      onDone: () => fail('macOS 更新流程已中断，请稍后重试。'),
    );

    try {
      await methodChannel.invokeMethod<void>('installUpdate', {
        'feedUrl': feedUrl,
      });
      await completer.future;
    } on PlatformException catch (error) {
      throw UpdateInstallException(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'macOS 更新启动失败，请稍后重试。',
      );
    } finally {
      await subscription.cancel();
    }
  }

  Map<Object?, Object?>? _eventMap(Object? event) {
    if (event is Map<Object?, Object?>) {
      return event;
    }
    return null;
  }

  UpdateInstallProgress? _progressFromEvent(Map<Object?, Object?> data) {
    return switch (data['type']?.toString()) {
      'preparing' => const UpdateInstallProgress(
        stage: UpdateInstallStage.preparing,
      ),
      'downloading' => UpdateInstallProgress(
        stage: UpdateInstallStage.downloading,
        receivedBytes: _intValue(data['receivedBytes']),
        totalBytes: _nullableIntValue(data['totalBytes']),
      ),
      'extracting' => UpdateInstallProgress(
        stage: UpdateInstallStage.extracting,
        fractionOverride: _doubleValue(data['fraction']),
      ),
      'installing' => const UpdateInstallProgress(
        stage: UpdateInstallStage.installing,
      ),
      'relaunching' => const UpdateInstallProgress(
        stage: UpdateInstallStage.launching,
      ),
      'installed' => const UpdateInstallProgress(
        stage: UpdateInstallStage.launching,
      ),
      _ => null,
    };
  }

  String _eventMessage(Map<Object?, Object?> data, String fallback) {
    final message = data['message']?.toString().trim();
    return message == null || message.isEmpty ? fallback : message;
  }

  int _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _nullableIntValue(Object? value) {
    if (value == null) {
      return null;
    }
    final parsed = _intValue(value);
    return parsed > 0 ? parsed : null;
  }

  double? _doubleValue(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }
}

class _UpdateHttpStatusException implements Exception {
  const _UpdateHttpStatusException(this.statusCode);

  final int statusCode;

  bool get temporary => statusCode >= 500 && statusCode < 600;
}
