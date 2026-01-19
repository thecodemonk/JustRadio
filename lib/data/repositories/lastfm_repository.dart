import 'package:dio/dio.dart';
import '../../core/constants/api_constants.dart';
import '../../core/utils/md5_helper.dart';

class LastfmRepository {
  final Dio _dio;
  final String apiKey;
  final String apiSecret;
  String? _sessionKey;

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

  /// Get authentication URL for user to authorize
  String getAuthUrl() {
    return '${ApiConstants.lastfmAuthUrl}?api_key=$apiKey';
  }

  /// Get session key from token (after user authorization)
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
      // Handle error
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
      return response.data['scrobbles'] != null;
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
