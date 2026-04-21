import 'package:hive/hive.dart';
import '../services/secure_secrets_service.dart';

class AppSettingsRepository {
  static const _boxName = 'app_settings';
  // Legacy key — read-only for one-time migration to secure storage.
  static const _legacyUnsplashKey = 'unsplash_access_key';

  final SecureSecretsService _secrets;
  Box? _box;
  String? _unsplashAccessKey;

  AppSettingsRepository({SecureSecretsService? secrets})
      : _secrets = secrets ?? SecureSecretsService();

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);

    // One-time migration: move any plaintext Unsplash key out of Hive into
    // the OS keychain. `unsplashAccessKey` is cached in-memory so sync reads
    // from the provider don't incur a platform-channel hop per build.
    final legacy = _box?.get(_legacyUnsplashKey);
    if (legacy is String && legacy.isNotEmpty) {
      await _secrets.setUnsplashAccessKey(legacy);
      await _box?.delete(_legacyUnsplashKey);
    }

    _unsplashAccessKey = await _secrets.getUnsplashAccessKey();
  }

  String? get unsplashAccessKey {
    final v = _unsplashAccessKey;
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setUnsplashAccessKey(String? key) async {
    final trimmed = key?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _secrets.clearUnsplashAccessKey();
      _unsplashAccessKey = null;
    } else {
      await _secrets.setUnsplashAccessKey(trimmed);
      _unsplashAccessKey = trimmed;
    }
  }
}
