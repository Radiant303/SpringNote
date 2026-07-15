import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全存储服务
///
/// 用于加密存储敏感信息（如 API Key）
class SecureStorageService {
  SecureStorageService({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// API Key 存储键前缀
  static const String _apiKeyPrefix = 'provider_api_key_';

  /// 保存 API Key
  Future<void> saveApiKey(String providerId, String apiKey) async {
    if (apiKey.trim().isEmpty) {
      await deleteApiKey(providerId);
      return;
    }
    await _storage.write(
      key: '$_apiKeyPrefix$providerId',
      value: apiKey,
    );
  }

  /// 读取 API Key
  Future<String?> readApiKey(String providerId) async {
    return _storage.read(key: '$_apiKeyPrefix$providerId');
  }

  /// 删除 API Key
  Future<void> deleteApiKey(String providerId) async {
    await _storage.delete(key: '$_apiKeyPrefix$providerId');
  }

  /// 读取所有 API Key（用于迁移或备份）
  Future<Map<String, String>> readAllApiKeys() async {
    final all = await _storage.readAll();
    final apiKeys = <String, String>{};
    for (final entry in all.entries) {
      if (entry.key.startsWith(_apiKeyPrefix)) {
        final providerId = entry.key.substring(_apiKeyPrefix.length);
        apiKeys[providerId] = entry.value;
      }
    }
    return apiKeys;
  }

  /// 删除所有存储的数据
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
