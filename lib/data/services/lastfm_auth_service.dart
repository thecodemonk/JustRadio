import 'dart:async';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';
import '../repositories/lastfm_repository.dart';
import '../../core/constants/lastfm_config.dart';
import 'secure_secrets_service.dart';

class LastfmAuthService {
  static const _boxName = 'lastfm_settings';
  // Legacy Hive keys — read-only now; used for one-time migration to secure
  // storage. See SecureSecretsService.
  static const _legacySessionKeyKey = 'session_key';
  static const _legacyUsernameKey = 'username';
  static const _pendingTokenKey = 'pending_token';

  final SecureSecretsService _secrets;
  Box? _box;
  String? _sessionKey;
  String? _username;
  late final LastfmRepository _repository;
  StreamSubscription<void>? _invalidSessionSub;

  LastfmAuthService({SecureSecretsService? secrets})
      : _secrets = secrets ?? SecureSecretsService();

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);

    // One-time migration: if the session key still lives in the plaintext
    // Hive box, move it into secure storage and scrub it from Hive.
    final legacySession = _box?.get(_legacySessionKeyKey) as String?;
    final legacyUsername = _box?.get(_legacyUsernameKey) as String?;
    if (legacySession != null && legacySession.isNotEmpty) {
      await _secrets.setLastfmSession(legacySession);
      await _box?.delete(_legacySessionKeyKey);
    }
    if (legacyUsername != null && legacyUsername.isNotEmpty) {
      await _secrets.setLastfmUsername(legacyUsername);
      await _box?.delete(_legacyUsernameKey);
    }

    _sessionKey = await _secrets.getLastfmSession();
    _username = await _secrets.getLastfmUsername();

    _repository = LastfmRepository(
      apiKey: LastfmConfig.apiKey,
      apiSecret: LastfmConfig.sharedSecret,
      sessionKey: _sessionKey,
    );

    _invalidSessionSub = _repository.invalidSessionStream.listen((_) {
      // Server told us the session key is gone. Clear local state so the UI
      // can prompt the user to re-link. Fire-and-forget is fine here.
      logout();
    });
  }

  bool get isAuthenticated => _sessionKey != null && _sessionKey!.isNotEmpty;

  String? get username => _username;
  String? get sessionKey => _sessionKey;
  String? get pendingToken => _box?.get(_pendingTokenKey) as String?;
  bool get hasPendingToken => pendingToken != null && pendingToken!.isNotEmpty;

  LastfmRepository get repository => _repository;

  /// Emits when the server reports the session key is invalid. Consumers can
  /// watch this to prompt the user to re-link. The local state is already
  /// cleared by the time this fires.
  Stream<void> get invalidSessionStream => _repository.invalidSessionStream;

  void dispose() {
    _invalidSessionSub?.cancel();
    _repository.dispose();
  }

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
      await _secrets.setLastfmSession(session.key);
      await _secrets.setLastfmUsername(session.name);
      await _box?.delete(_pendingTokenKey);
      _sessionKey = session.key;
      _username = session.name;
      _repository.setSessionKey(session.key);
      return true;
    }
    return false;
  }

  Future<void> cancelAuth() async {
    await _box?.delete(_pendingTokenKey);
  }

  Future<void> logout() async {
    await _secrets.clearLastfm();
    await _box?.delete(_pendingTokenKey);
    // Also scrub any stragglers in the legacy Hive keys (defensive — migration
    // already handles the normal path).
    await _box?.delete(_legacySessionKeyKey);
    await _box?.delete(_legacyUsernameKey);
    _sessionKey = null;
    _username = null;
    _repository.setSessionKey(null);
  }

  Future<UserInfo?> getUserInfo() async {
    return _repository.getUserInfo();
  }
}
