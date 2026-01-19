import 'dart:async';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';
import '../repositories/lastfm_repository.dart';
import '../../core/constants/lastfm_config.dart';

class LastfmAuthService {
  static const _boxName = 'lastfm_settings';
  static const _sessionKeyKey = 'session_key';
  static const _usernameKey = 'username';
  static const _pendingTokenKey = 'pending_token';

  Box? _box;
  late final LastfmRepository _repository;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    final sessionKey = _box?.get(_sessionKeyKey) as String?;

    _repository = LastfmRepository(
      apiKey: LastfmConfig.apiKey,
      apiSecret: LastfmConfig.sharedSecret,
      sessionKey: sessionKey,
    );
  }

  bool get isAuthenticated {
    final sessionKey = _box?.get(_sessionKeyKey) as String?;
    return sessionKey != null && sessionKey.isNotEmpty;
  }

  String? get username => _box?.get(_usernameKey) as String?;
  String? get sessionKey => _box?.get(_sessionKeyKey) as String?;
  String? get pendingToken => _box?.get(_pendingTokenKey) as String?;
  bool get hasPendingToken => pendingToken != null && pendingToken!.isNotEmpty;

  LastfmRepository get repository => _repository;

  /// Step 1: Get token from Last.fm and open browser for authorization
  Future<void> startAuthFlow() async {
    // Get an unauthorized token from Last.fm
    final token = await _repository.getToken();
    if (token == null) {
      throw Exception('Failed to get token from Last.fm');
    }

    // Store the token for later use
    await _box?.put(_pendingTokenKey, token);

    // Open browser for user to authorize the token
    final url = _repository.getAuthUrl(token);
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('Could not launch Last.fm authorization URL');
    }
  }

  /// Step 2: After user authorizes in browser, exchange token for session
  Future<bool> completeAuth() async {
    final token = pendingToken;
    if (token == null || token.isEmpty) {
      throw StateError('No pending token. Start auth flow first.');
    }

    final session = await _repository.getSession(token);
    if (session != null) {
      await _box?.put(_sessionKeyKey, session.key);
      await _box?.put(_usernameKey, session.name);
      await _box?.delete(_pendingTokenKey);
      _repository.setSessionKey(session.key);
      return true;
    }
    return false;
  }

  Future<void> cancelAuth() async {
    await _box?.delete(_pendingTokenKey);
  }

  Future<void> logout() async {
    await _box?.delete(_sessionKeyKey);
    await _box?.delete(_usernameKey);
    await _box?.delete(_pendingTokenKey);
    _repository.setSessionKey(null);
  }

  Future<UserInfo?> getUserInfo() async {
    return _repository.getUserInfo();
  }
}
