import 'package:hive/hive.dart';
import '../services/secure_secrets_service.dart';

class AppSettingsRepository {
  static const _boxName = 'app_settings';
  // Legacy key — read-only for one-time migration to secure storage.
  static const _legacyUnsplashKey = 'unsplash_access_key';
  static const _volumeKey = 'volume';
  static const _defaultVolume = 1.0;

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

  /// Persisted linear volume (0..1). Defaults to full volume on first run.
  /// The UI slider maps 1:1 to this; the audio service applies the cube
  /// taper when pushing down to the native player.
  double get volume {
    final v = _box?.get(_volumeKey);
    if (v is double && v.isFinite) return v.clamp(0.0, 1.0);
    return _defaultVolume;
  }

  Future<void> setVolume(double volume) async {
    await _box?.put(_volumeKey, volume.clamp(0.0, 1.0));
  }

  // ------------------------------------------------------------------
  // One-shot migration flags — for code that needs to run exactly once
  // per install (schema migrations, cache purges after a provider swap).
  // Name the key semantically + versioned so we can re-run a new
  // migration without disturbing prior ones.
  // ------------------------------------------------------------------

  bool isMigrationDone(String name) =>
      _box?.get('migration.$name') == true;

  Future<void> markMigrationDone(String name) async {
    await _box?.put('migration.$name', true);
  }
}
