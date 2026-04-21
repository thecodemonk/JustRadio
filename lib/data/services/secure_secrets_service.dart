import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper around flutter_secure_storage for the handful of credentials
/// this app stores (Last.fm session + Unsplash access key). Keeps call sites
/// decoupled from the underlying platform store.
///
/// Platform backing:
/// - macOS/iOS: Keychain (requires Keychain Sharing entitlement on macOS)
/// - Windows: DPAPI
/// - Linux: libsecret (gnome-keyring / KWallet)
/// - Android: EncryptedSharedPreferences / Keystore
class SecureSecretsService {
  static const _lastfmSessionKey = 'lastfm_session_key';
  static const _lastfmUsernameKey = 'lastfm_username';
  static const _unsplashAccessKey = 'unsplash_access_key';

  final FlutterSecureStorage _storage;

  SecureSecretsService({FlutterSecureStorage? storage})
      : _storage = storage ?? FlutterSecureStorage();

  Future<String?> getLastfmSession() => _storage.read(key: _lastfmSessionKey);

  Future<void> setLastfmSession(String value) =>
      _storage.write(key: _lastfmSessionKey, value: value);

  Future<String?> getLastfmUsername() =>
      _storage.read(key: _lastfmUsernameKey);

  Future<void> setLastfmUsername(String value) =>
      _storage.write(key: _lastfmUsernameKey, value: value);

  Future<void> clearLastfm() async {
    await _storage.delete(key: _lastfmSessionKey);
    await _storage.delete(key: _lastfmUsernameKey);
  }

  Future<String?> getUnsplashAccessKey() =>
      _storage.read(key: _unsplashAccessKey);

  Future<void> setUnsplashAccessKey(String value) =>
      _storage.write(key: _unsplashAccessKey, value: value);

  Future<void> clearUnsplashAccessKey() =>
      _storage.delete(key: _unsplashAccessKey);
}
