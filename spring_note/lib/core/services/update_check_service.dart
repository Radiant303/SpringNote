import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

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

enum UpdateCheckStatus { idle, updateAvailable, failed }

class UpdateCheckResult {
  const UpdateCheckResult._({
    required this.status,
    required this.currentVersion,
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
    );
  }

  static const idle = UpdateCheckResult._(
    status: UpdateCheckStatus.idle,
    currentVersion: '',
  );

  final UpdateCheckStatus status;
  final String currentVersion;
  final AppUpdateInfo? latest;
}

class UpdateCheckService {
  const UpdateCheckService();

  static const _timeout = Duration(seconds: 10);
  static const _changelogUrl =
      'https://raw.githubusercontent.com/Radiant303/SpringNote/main/update/LATESTCHANGELOG.md';

  Future<UpdateCheckResult> check() async {
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
    } catch (_) {
      return UpdateCheckResult.failed(currentVersion: currentVersion);
    }
  }

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
      final changelog = await _readUrl(_changelogUrl);
      return changelog.trim().isEmpty ? '暂无更新内容。' : changelog;
    } catch (_) {
      return '更新内容加载失败。';
    }
  }

  Future<String> _readUrl(String url) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const HttpException('Unexpected update response status.');
      }
      return await response.transform(utf8.decoder).join().timeout(_timeout);
    } finally {
      client.close(force: true);
    }
  }

  String? _platformEndpoint() {
    const base =
        'https://raw.githubusercontent.com/Radiant303/SpringNote/main/update';
    if (Platform.isWindows) {
      return '$base/windows.json';
    }
    if (Platform.isLinux) {
      return '$base/linux.json';
    }
    if (Platform.isMacOS) {
      return '$base/mac.json';
    }
    return null;
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
