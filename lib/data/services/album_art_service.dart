import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import '../../core/constants/api_constants.dart';
import '../../core/constants/lastfm_config.dart';
import '../models/album_art.dart';

/// Album art lookup — tries Last.fm first (same credentials as scrobbling),
/// falls back to iTunes Search. Returns an [AlbumArt] record even on miss
/// (with `imageUrl = null`) so the caller can distinguish "unknown" from
/// "not yet looked up" and avoid hammering the APIs for known-empty tracks.
class AlbumArtService {
  final Dio _lastfmDio;
  final Dio _itunesDio;

  AlbumArtService({Dio? lastfmDio, Dio? itunesDio})
      : _lastfmDio = lastfmDio ??
            Dio(BaseOptions(
              baseUrl: ApiConstants.lastfmBaseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            )),
        _itunesDio = itunesDio ??
            Dio(BaseOptions(
              baseUrl: 'https://itunes.apple.com',
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ));

  Future<AlbumArt> lookup({
    required String artist,
    required String title,
  }) async {
    final now = DateTime.now();
    if (artist.isEmpty || title.isEmpty) {
      return AlbumArt(
        artist: artist,
        title: title,
        imageUrl: null,
        source: 'none',
        fetchedAt: now,
      );
    }

    final viaLastfm = await _lookupLastfm(artist, title);
    if (viaLastfm != null) {
      return AlbumArt(
        artist: artist,
        title: title,
        imageUrl: viaLastfm,
        source: 'lastfm',
        fetchedAt: now,
      );
    }

    final viaItunes = await _lookupItunes(artist, title);
    if (viaItunes != null) {
      return AlbumArt(
        artist: artist,
        title: title,
        imageUrl: viaItunes,
        source: 'itunes',
        fetchedAt: now,
      );
    }

    return AlbumArt(
      artist: artist,
      title: title,
      imageUrl: null,
      source: 'none',
      fetchedAt: now,
    );
  }

  Future<String?> _lookupLastfm(String artist, String title) async {
    try {
      final res = await _lastfmDio.get('', queryParameters: {
        'method': 'track.getInfo',
        'api_key': LastfmConfig.apiKey,
        'artist': artist,
        'track': title,
        'autocorrect': '1',
        'format': 'json',
      });
      final data = res.data;
      if (data is! Map) {
        if (kDebugMode) {
          debugPrint('[albumart/lastfm] unexpected response type: ${data.runtimeType}');
        }
        return null;
      }
      if (data['error'] != null) {
        if (kDebugMode) {
          debugPrint(
            '[albumart/lastfm] api error ${data['error']}: ${data['message']}',
          );
        }
        return null;
      }
      final track = data['track'];
      final album = track is Map ? track['album'] : null;
      final images = album is Map ? album['image'] : null;
      if (images is! List) {
        if (kDebugMode) {
          debugPrint(
            '[albumart/lastfm] no track.album.image in response for "$artist - $title" (track=${track != null}, album=${album != null})',
          );
        }
        return null;
      }
      // Walk from largest to smallest and return the first non-empty URL.
      // Last.fm returns size labels small / medium / large / extralarge /
      // mega in practice; mega isn't documented everywhere but appears in
      // real responses, so check it first.
      const preferred = ['mega', 'extralarge', 'large', 'medium', 'small'];
      for (final size in preferred) {
        for (final img in images) {
          if (img is Map &&
              img['size'] == size &&
              img['#text'] is String &&
              (img['#text'] as String).isNotEmpty) {
            final url = img['#text'] as String;
            if (kDebugMode) {
              debugPrint('[albumart/lastfm] hit size=$size url=$url');
            }
            return url;
          }
        }
      }
      if (kDebugMode) {
        final sizes = images
            .whereType<Map>()
            .map((m) => '${m['size']}=${(m['#text'] as String?)?.isEmpty ?? true ? "empty" : "ok"}')
            .join(', ');
        debugPrint(
          '[albumart/lastfm] all image entries empty for "$artist - $title" — sizes: $sizes',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[albumart/lastfm] exception: $e');
    }
    return null;
  }

  Future<String?> _lookupItunes(String artist, String title) async {
    try {
      final term = '$artist $title';
      final res = await _itunesDio.get('/search', queryParameters: {
        'term': term,
        'media': 'music',
        'entity': 'song',
        'limit': 1,
      });
      final data = res.data;
      if (data is! Map) {
        if (kDebugMode) {
          debugPrint('[albumart/itunes] unexpected response type: ${data.runtimeType}');
        }
        return null;
      }
      final results = data['results'];
      if (results is! List || results.isEmpty) {
        if (kDebugMode) {
          debugPrint('[albumart/itunes] no results for "$artist $title"');
        }
        return null;
      }
      final first = results.first;
      if (first is! Map) return null;
      final raw = first['artworkUrl100'];
      if (raw is! String || raw.isEmpty) {
        if (kDebugMode) debugPrint('[albumart/itunes] result has no artworkUrl100');
        return null;
      }
      // iTunes default is a low-res 100x100; the URL ends with /100x100bb.jpg.
      // Swap in 600x600 for a display-worthy asset. Falls back gracefully
      // if the URL doesn't match the pattern.
      final upscaled = raw.replaceFirst(
        RegExp(r'/\d+x\d+bb\.(jpg|jpeg|png)$'),
        '/600x600bb.jpg',
      );
      if (kDebugMode) debugPrint('[albumart/itunes] hit url=$upscaled');
      return upscaled;
    } catch (e) {
      if (kDebugMode) debugPrint('[albumart/itunes] exception: $e');
    }
    return null;
  }
}
