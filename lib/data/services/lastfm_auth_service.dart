import 'dart:async';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';
import '../repositories/lastfm_repository.dart';

class LastfmAuthService {
  static const _boxName = 'lastfm_settings';
  static const _sessionKeyKey = 'session_key';
  static const _usernameKey = 'username';
  static const _apiKeyKey = 'api_key';
  static const _apiSecretKey = 'api_secret';

  Box? _box;
  LastfmRepository? _repository;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _initRepository();
  }

  void _initRepository() {
    final apiKey = _box?.get(_apiKeyKey) as String?;
    final apiSecret = _box?.get(_apiSecretKey) as String?;
    final sessionKey = _box?.get(_sessionKeyKey) as String?;

    if (apiKey != null && apiSecret != null) {
      _repository = LastfmRepository(
        apiKey: apiKey,
        apiSecret: apiSecret,
        sessionKey: sessionKey,
      );
    }
  }

  bool get hasCredentials {
    final apiKey = _box?.get(_apiKeyKey) as String?;
    final apiSecret = _box?.get(_apiSecretKey) as String?;
    return apiKey != null &&
        apiKey.isNotEmpty &&
        apiSecret != null &&
        apiSecret.isNotEmpty;
  }

  bool get isAuthenticated {
    final sessionKey = _box?.get(_sessionKeyKey) as String?;
    return sessionKey != null && sessionKey.isNotEmpty;
  }

  String? get username => _box?.get(_usernameKey) as String?;
  String? get apiKey => _box?.get(_apiKeyKey) as String?;
  String? get apiSecret => _box?.get(_apiSecretKey) as String?;
  String? get sessionKey => _box?.get(_sessionKeyKey) as String?;

  LastfmRepository? get repository => _repository;

  Future<void> saveCredentials({
    required String apiKey,
    required String apiSecret,
  }) async {
    await _box?.put(_apiKeyKey, apiKey);
    await _box?.put(_apiSecretKey, apiSecret);
    _initRepository();
  }

  Future<void> startAuthFlow() async {
    if (_repository == null) {
      throw StateError('API credentials not set');
    }

    final url = _repository!.getAuthUrl();
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('Could not launch Last.fm authorization URL');
    }
  }

  Future<bool> completeAuth(String token) async {
    if (_repository == null) {
      throw StateError('API credentials not set');
    }

    final session = await _repository!.getSession(token);
    if (session != null) {
      await _box?.put(_sessionKeyKey, session.key);
      await _box?.put(_usernameKey, session.name);
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    await _box?.delete(_sessionKeyKey);
    await _box?.delete(_usernameKey);
    _repository?.setSessionKey(null);
  }

  Future<void> clearAll() async {
    await _box?.clear();
    _repository = null;
  }

  Future<UserInfo?> getUserInfo() async {
    return _repository?.getUserInfo();
  }
}
