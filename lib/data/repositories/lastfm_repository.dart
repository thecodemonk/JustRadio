import 'dart:async';
import 'package:dio/dio.dart';
import '../../core/constants/api_constants.dart';
import '../../core/utils/md5_helper.dart';

/// Last.fm error code for a session key that has been revoked or is otherwise
/// no longer valid. See https://www.last.fm/api/errorcodes
const int kLastfmInvalidSessionError = 9;

class LastfmRepository {
  final Dio _dio;
  final String apiKey;
  final String apiSecret;
  String? _sessionKey;

  // Fires when the server reports error 9 ("Invalid session key"). The auth
  // service subscribes so it can clear local credentials and let the UI
  // prompt the user to re-link.
  final _invalidSessionController = StreamController<void>.broadcast();
  Stream<void> get invalidSessionStream => _invalidSessionController.stream;

  LastfmRepository({
    required this.apiKey,
    required this.apiSecret,
    String? sessionKey,
    Dio? dio,
  })  : _sessionKey = sessionKey,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: ApiConstants.lastfmBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ));

  void setSessionKey(String? key) {
    _sessionKey = key;
  }

  bool get isAuthenticated => _sessionKey != null && _sessionKey!.isNotEmpty;

  void dispose() {
    _invalidSessionController.close();
  }

  // Last.fm returns HTTP 200 even for API errors; check the JSON body.
  bool _checkInvalidSession(dynamic body) {
    if (body is Map && body['error'] == kLastfmInvalidSessionError) {
      _sessionKey = null;
      _invalidSessionController.add(null);
      return true;
    }
    return false;
  }

  /// Step 1: Get an unauthorized token from Last.fm
  Future<String?> getToken() async {
    final params = {
      'method': 'auth.getToken',
      'api_key': apiKey,
    };

    final signature = Md5Helper.generateLastfmSignature(params, apiSecret);
    params['api_sig'] = signature;
    params['format'] = 'json';

    try {
      final response = await _dio.get('', queryParameters: params);
      final data = response.data;
      return data['token'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Step 2: Get authentication URL for user to authorize the token
  String getAuthUrl(String token) {
    return '${ApiConstants.lastfmAuthUrl}?api_key=$apiKey&token=$token';
  }

  /// Step 3: Exchange authorized token for session key
  Future<SessionInfo?> getSession(String token) async {
    final params = {
      'method': 'auth.getSession',
      'api_key': apiKey,
      'token': token,
    };

    final signature = Md5Helper.generateLastfmSignature(params, apiSecret);
    params['api_sig'] = signature;
    params['format'] = 'json';

    try {
      final response = await _dio.get('', queryParameters: params);
      final data = response.data;

      if (data['session'] != null) {
        final session = data['session'];
        _sessionKey = session['key'];
        return SessionInfo(
          name: session['name'] ?? '',
          key: session['key'] ?? '',
        );
      }
    } catch (e) {
      rethrow;
    }
    return null;
  }

  /// Update now playing on Last.fm
  Future<bool> updateNowPlaying({
    required String artist,
    required String track,
    String? album,
    int? duration,
  }) async {
    if (!isAuthenticated) return false;

    final params = {
      'method': 'track.updateNowPlaying',
      'api_key': apiKey,
      'sk': _sessionKey!,
      'artist': artist,
      'track': track,
      if (album != null && album.isNotEmpty) 'album': album,
      if (duration != null) 'duration': duration.toString(),
    };

    final signature = Md5Helper.generateLastfmSignature(params, apiSecret);
    params['api_sig'] = signature;
    params['format'] = 'json';

    try {
      final response = await _dio.post(
        '',
        data: params,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      if (_checkInvalidSession(response.data)) return false;
      return response.data['nowplaying'] != null;
    } catch (e) {
      return false;
    }
  }

  /// Scrobble a track to Last.fm
  Future<bool> scrobble({
    required String artist,
    required String track,
    required int timestamp,
    String? album,
    int? duration,
  }) async {
    if (!isAuthenticated) return false;

    final params = {
      'method': 'track.scrobble',
      'api_key': apiKey,
      'sk': _sessionKey!,
      'artist': artist,
      'track': track,
      'timestamp': timestamp.toString(),
      if (album != null && album.isNotEmpty) 'album': album,
      if (duration != null) 'duration': duration.toString(),
    };

    final signature = Md5Helper.generateLastfmSignature(params, apiSecret);
    params['api_sig'] = signature;
    params['format'] = 'json';

    try {
      final response = await _dio.post(
        '',
        data: params,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      if (_checkInvalidSession(response.data)) return false;
      return response.data['scrobbles'] != null;
    } catch (e) {
      return false;
    }
  }

  /// Love a track on Last.fm
  Future<bool> loveTrack({
    required String artist,
    required String track,
  }) =>
      _loveOrUnlove('track.love', artist: artist, track: track);

  /// Unlove a track on Last.fm
  Future<bool> unloveTrack({
    required String artist,
    required String track,
  }) =>
      _loveOrUnlove('track.unlove', artist: artist, track: track);

  Future<bool> _loveOrUnlove(
    String method, {
    required String artist,
    required String track,
  }) async {
    if (!isAuthenticated) return false;

    final params = {
      'method': method,
      'api_key': apiKey,
      'sk': _sessionKey!,
      'artist': artist,
      'track': track,
    };

    final signature = Md5Helper.generateLastfmSignature(params, apiSecret);
    params['api_sig'] = signature;
    params['format'] = 'json';

    try {
      final response = await _dio.post(
        '',
        data: params,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      if (_checkInvalidSession(response.data)) return false;
      return response.statusCode == 200 && response.data['error'] == null;
    } catch (e) {
      return false;
    }
  }

  /// Check whether the authenticated user has loved this track.
  Future<bool> isTrackLoved({
    required String artist,
    required String track,
    required String username,
  }) async {
    final params = {
      'method': 'track.getInfo',
      'api_key': apiKey,
      'artist': artist,
      'track': track,
      'username': username,
      'format': 'json',
    };

    try {
      final response = await _dio.get('', queryParameters: params);
      final loved = response.data?['track']?['userloved'];
      return loved?.toString() == '1';
    } catch (e) {
      return false;
    }
  }

  /// Get user info
  Future<UserInfo?> getUserInfo() async {
    if (!isAuthenticated) return null;

    final params = {
      'method': 'user.getInfo',
      'api_key': apiKey,
      'sk': _sessionKey!,
      'format': 'json',
    };

    try {
      final response = await _dio.get('', queryParameters: params);
      final data = response.data;
      if (_checkInvalidSession(data)) return null;

      if (data['user'] != null) {
        final user = data['user'];
        return UserInfo(
          name: user['name'] ?? '',
          realName: user['realname'] ?? '',
          playcount: int.tryParse(user['playcount']?.toString() ?? '0') ?? 0,
          imageUrl: _extractImageUrl(user['image']),
        );
      }
    } catch (e) {
      // Handle error
    }
    return null;
  }

  String? _extractImageUrl(dynamic images) {
    if (images is List && images.isNotEmpty) {
      // Get the largest image
      for (final size in ['extralarge', 'large', 'medium', 'small']) {
        for (final img in images) {
          if (img['size'] == size && img['#text']?.isNotEmpty == true) {
            return img['#text'];
          }
        }
      }
    }
    return null;
  }
}

class SessionInfo {
  final String name;
  final String key;

  SessionInfo({required this.name, required this.key});
}

class UserInfo {
  final String name;
  final String realName;
  final int playcount;
  final String? imageUrl;

  UserInfo({
    required this.name,
    required this.realName,
    required this.playcount,
    this.imageUrl,
  });
}
