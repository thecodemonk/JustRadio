import 'dart:async';
import 'dart:collection';
import 'package:dio/dio.dart';
import '../models/genre_photo.dart';

/// Single-process semaphore — keeps concurrent outgoing requests bounded
/// so opening the Genres tab doesn't fire 100 requests simultaneously.
class _Throttle {
  final int maxConcurrent;
  int _active = 0;
  final Queue<Completer<void>> _waiting = Queue();

  _Throttle(this.maxConcurrent);

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= maxConcurrent) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      }
    }
  }
}

class UnsplashService {
  static const _base = 'https://api.unsplash.com';
  static const _utm = 'utm_source=just_radio&utm_medium=referral';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _base,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));
  final _Throttle _throttle = _Throttle(3);

  String? _accessKey;

  bool get isConfigured => _accessKey != null && _accessKey!.isNotEmpty;

  void setAccessKey(String? key) {
    _accessKey = key?.trim().isEmpty == true ? null : key?.trim();
  }

  /// Appends Unsplash-required UTM params to a photographer or photo URL.
  static String attributedLink(String url) {
    if (url.isEmpty) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url$sep$_utm';
  }

  /// Search for a landscape photo matching [query].
  /// Returns null when the service isn't configured, the query yields no
  /// results, or the request fails.
  Future<GenrePhoto?> searchPhoto(String query) async {
    if (!isConfigured) return null;
    final normalized = query.trim();
    if (normalized.isEmpty) return null;

    return _throttle.run(() async {
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          '/search/photos',
          queryParameters: {
            'query': '$normalized music',
            'per_page': 1,
            'orientation': 'landscape',
            'content_filter': 'high',
          },
          options: Options(
            headers: {'Authorization': 'Client-ID $_accessKey'},
          ),
        );
        final results = (response.data?['results'] as List?) ?? const [];
        if (results.isEmpty) return null;
        final photo = results.first as Map<String, dynamic>;
        final urls = photo['urls'] as Map<String, dynamic>? ?? const {};
        final links = photo['links'] as Map<String, dynamic>? ?? const {};
        final user = photo['user'] as Map<String, dynamic>? ?? const {};
        final userLinks =
            user['links'] as Map<String, dynamic>? ?? const {};

        return GenrePhoto(
          genre: normalized,
          imageUrl: (urls['regular'] ?? urls['small'] ?? urls['thumb'] ?? '')
              as String,
          photoPageUrl: (links['html'] ?? '') as String,
          photographerName: (user['name'] ?? 'Unknown') as String,
          photographerUrl: (userLinks['html'] ?? '') as String,
          downloadLocation: (links['download_location'] ?? '') as String,
          fetchedAt: DateTime.now(),
        );
      } catch (_) {
        return null;
      }
    });
  }

  /// Per Unsplash TOS: ping the `download_location` URL once per used photo.
  /// Fire-and-forget — we don't await the result.
  Future<void> registerDownload(String downloadLocation) async {
    if (!isConfigured || downloadLocation.isEmpty) return;
    try {
      await _dio.getUri(
        Uri.parse(downloadLocation),
        options: Options(
          headers: {'Authorization': 'Client-ID $_accessKey'},
        ),
      );
    } catch (_) {
      // Silent: tracking is best-effort, not user-visible.
    }
  }
}
