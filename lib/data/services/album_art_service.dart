import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../../core/constants/api_constants.dart';
import '../models/album_art.dart';

/// Album art lookup. Chain order: **iTunes → Deezer → MusicBrainz+CAA**.
///
/// Last.fm was removed from this chain — coverage is inconsistent and
/// several of their image URLs have been deprecated. The Last.fm client
/// still exists in the app for scrobble / love / user-info flows.
///
/// Each provider returns `null` when it can't confidently answer. The
/// confidence bar is match-verification: we normalize the query and the
/// candidate's artist + title and require both sides to overlap. This
/// stops us from caching a wrong cover (the cache is effectively
/// permanent) when a provider's top hit is a same-name different-song.
class AlbumArtService {
  final Dio _itunesDio;
  final Dio _deezerDio;
  final Dio _musicbrainzDio;
  final Dio _caaDio;

  /// MusicBrainz caps requests at 1/sec (hard). We only reach MB when
  /// iTunes AND Deezer miss, so this is rare — but the rare back-to-back
  /// case still needs serialization. A single chained future is simpler
  /// than a dedicated queue class.
  Future<void>? _mbLane;

  AlbumArtService({
    Dio? itunesDio,
    Dio? deezerDio,
    Dio? musicbrainzDio,
    Dio? caaDio,
  })  : _itunesDio = itunesDio ??
            Dio(BaseOptions(
              baseUrl: ApiConstants.itunesBaseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            )),
        _deezerDio = deezerDio ??
            Dio(BaseOptions(
              baseUrl: ApiConstants.deezerBaseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            )),
        _musicbrainzDio = musicbrainzDio ??
            Dio(BaseOptions(
              baseUrl: ApiConstants.musicbrainzBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {
                'User-Agent': ApiConstants.musicbrainzUserAgent,
                'Accept': 'application/json',
              },
            )),
        _caaDio = caaDio ??
            Dio(BaseOptions(
              baseUrl: ApiConstants.coverArtArchiveBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {
                'User-Agent': ApiConstants.musicbrainzUserAgent,
              },
              // Dio follows redirects by default; CAA always 307s.
              followRedirects: true,
              maxRedirects: 5,
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

    final sw = Stopwatch()..start();
    for (final provider in _providers) {
      final providerStart = sw.elapsedMilliseconds;
      final url = await provider.lookup(artist, title);
      if (url != null) {
        if (kDebugMode) {
          debugPrint(
              '[albumart] resolved via=${provider.name} in ${sw.elapsedMilliseconds}ms (this provider ${sw.elapsedMilliseconds - providerStart}ms) "$artist - $title" url=$url');
        }
        return AlbumArt(
          artist: artist,
          title: title,
          imageUrl: url,
          source: provider.name,
          fetchedAt: now,
        );
      }
    }

    if (kDebugMode) {
      debugPrint(
          '[albumart] miss all providers in ${sw.elapsedMilliseconds}ms for "$artist - $title"');
    }
    return AlbumArt(
      artist: artist,
      title: title,
      imageUrl: null,
      source: 'none',
      fetchedAt: now,
    );
  }

  /// Iterated by [lookup]. Each record pairs a source name with its
  /// lookup method.
  late final List<({String name, Future<String?> Function(String, String) lookup})>
      _providers = [
    (name: 'itunes', lookup: _lookupItunes),
    (name: 'deezer', lookup: _lookupDeezer),
    (name: 'musicbrainz', lookup: _lookupMusicBrainz),
  ];

  // ------------------------------------------------------------------
  // iTunes
  // ------------------------------------------------------------------

  /// iTunes catalog is partitioned by country — a track in one store may
  /// be completely absent from another. US is the biggest single
  /// catalog, so try it alone first; on miss, race GB + DE + ZA in
  /// parallel so a regional-only track (e.g. iTunes ZA) doesn't cost
  /// three sequential round-trips.
  static const _itunesPrimaryCountry = 'us';
  static const _itunesFallbackCountries = ['gb', 'de', 'za'];

  Future<String?> _lookupItunes(String artist, String title) async {
    final primary =
        await _lookupItunesCountry(artist, title, _itunesPrimaryCountry);
    if (primary != null) return primary;

    // Race the fallback regions. First positive match wins.
    final futures = _itunesFallbackCountries.map((cc) async {
      final url = await _lookupItunesCountry(artist, title, cc);
      return url == null ? null : (country: cc, url: url);
    }).toList();
    // Collect all results — simplest way to "return first non-null" is
    // to wait for the lot and pick. We're bounded at 3 requests and
    // each has its own timeout, so total latency is max(3 requests),
    // not sum. That's the whole point of parallelization.
    final settled = await Future.wait(futures);
    for (final hit in settled) {
      if (hit != null) return hit.url;
    }
    return null;
  }

  Future<String?> _lookupItunesCountry(
      String artist, String title, String country) async {
    try {
      final res = await _itunesDio.get('/search', queryParameters: {
        'term': '$artist $title',
        'media': 'music',
        'entity': 'song',
        'country': country,
        'limit': 3,
      });
      final data = _asJsonMap(res.data);
      if (data == null) return null;
      final results = data['results'];
      if (results is! List || results.isEmpty) {
        if (kDebugMode) {
          debugPrint('[albumart/itunes:$country] no results for "$artist $title"');
        }
        return null;
      }
      for (final entry in results) {
        if (entry is! Map) continue;
        final candArtist = entry['artistName'] as String? ?? '';
        final candTitle = entry['trackName'] as String? ?? '';
        if (!_matchesQuery(
            candArtist: candArtist,
            candTitle: candTitle,
            qArtist: artist,
            qTitle: title)) {
          continue;
        }
        // Skip DJ-mix / various-artists compilations. iTunes signals
        // these by setting `collectionArtistName` to someone other than
        // the track's `artistName` (e.g. track by David Holmes on an
        // album credited to Kruder & Dorfmeister). On the artist's own
        // album, `collectionArtistName` is absent.
        final collArtist = entry['collectionArtistName'] as String?;
        if (collArtist != null &&
            collArtist.isNotEmpty &&
            _normalize(collArtist) != _normalize(candArtist)) {
          if (kDebugMode) {
            debugPrint(
                '[albumart/itunes:$country] skip compilation: collectionArtistName="$collArtist" vs trackArtist="$candArtist"');
          }
          continue;
        }
        final raw = entry['artworkUrl100'];
        if (raw is! String || raw.isEmpty) continue;
        if (kDebugMode) {
          debugPrint('[albumart/itunes:$country] hit "$candArtist - $candTitle"');
        }
        // iTunes serves larger sizes at the same path. 600x600 is a good
        // balance between fidelity and bandwidth for our art sizes.
        return raw.replaceFirst(
          RegExp(r'/\d+x\d+bb\.(jpg|jpeg|png)$'),
          '/600x600bb.jpg',
        );
      }
      if (kDebugMode) {
        debugPrint(
          '[albumart/itunes:$country] ${results.length} results failed match-check for "$artist - $title"',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[albumart/itunes:$country] exception: $e');
    }
    return null;
  }

  // ------------------------------------------------------------------
  // Deezer
  // ------------------------------------------------------------------

  Future<String?> _lookupDeezer(String artist, String title) async {
    try {
      final res = await _deezerDio.get('/search', queryParameters: {
        // Plain query. Advanced `artist:"X" track:"Y"` exists but is
        // flaky in practice — it returned zero results for known tracks
        // during testing. Plain query + match-verifier is more robust.
        'q': '$artist $title',
        'limit': 3,
      });
      final data = _asJsonMap(res.data);
      if (data == null) return null;
      final hits = data['data'];
      if (hits is! List || hits.isEmpty) {
        if (kDebugMode) {
          debugPrint('[albumart/deezer] no results for "$artist $title"');
        }
        return null;
      }
      for (final entry in hits) {
        if (entry is! Map) continue;
        final candTitle = entry['title'] as String? ?? '';
        final candArtistObj = entry['artist'];
        final candArtist =
            candArtistObj is Map ? (candArtistObj['name'] as String? ?? '') : '';
        if (!_matchesQuery(
            candArtist: candArtist,
            candTitle: candTitle,
            qArtist: artist,
            qTitle: title)) {
          continue;
        }
        final album = entry['album'];
        if (album is! Map) continue;
        // Prefer cover_xl, fall back smaller if the xl size happens to be
        // missing on an older release.
        for (final field in const ['cover_xl', 'cover_big', 'cover_medium']) {
          final url = album[field];
          if (url is String && url.isNotEmpty) return url;
        }
      }
      if (kDebugMode) {
        debugPrint(
          '[albumart/deezer] all ${hits.length} results failed match-check for "$artist - $title"',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[albumart/deezer] exception: $e');
    }
    return null;
  }

  // ------------------------------------------------------------------
  // MusicBrainz + Cover Art Archive
  // ------------------------------------------------------------------

  Future<String?> _lookupMusicBrainz(String artist, String title) =>
      _mbSerialized(() => _lookupMusicBrainzUnguarded(artist, title));

  Future<String?> _lookupMusicBrainzUnguarded(
      String artist, String title) async {
    try {
      // Query by recording title only. Filtering by both artist AND
      // recording is brittle: MB's Lucene index is space-sensitive,
      // so "Leggobeast" (ICY one-word form) misses the canonical
      // "Leggo Beast". Let the space-tolerant match verifier filter on
      // artist downstream — titles are more stable across catalogs
      // than artist names.
      final query = 'recording:"${_lucene(title)}"';
      final res = await _musicbrainzDio.get('/ws/2/recording/',
          queryParameters: {
            'query': query,
            'fmt': 'json',
            'limit': 25,
          });
      final data = _asJsonMap(res.data);
      if (data == null) return null;
      final recordings = data['recordings'];
      if (recordings is! List || recordings.isEmpty) {
        if (kDebugMode) {
          debugPrint('[albumart/mb] no recordings for "$artist - $title"');
        }
        return null;
      }
      var skippedCompilations = 0;
      for (final rec in recordings.take(15)) {
        if (rec is! Map) continue;
        final candTitle = rec['title'] as String? ?? '';
        final credits = rec['artist-credit'];
        final candArtist = credits is List && credits.isNotEmpty
            ? ((credits.first as Map?)?['name'] as String? ?? '')
            : '';
        if (!_matchesQuery(
            candArtist: candArtist,
            candTitle: candTitle,
            qArtist: artist,
            qTitle: title)) {
          continue;
        }
        final releases = rec['releases'];
        if (releases is! List || releases.isEmpty) continue;
        for (final rel in releases.take(3)) {
          if (rel is! Map) continue;
          if (_isCompilation(rel)) {
            skippedCompilations++;
            continue;
          }
          final mbid = rel['id'] as String? ?? '';
          if (mbid.isEmpty) continue;
          final coverUrl = await _caaFront(mbid);
          if (coverUrl != null) {
            if (kDebugMode) {
              debugPrint(
                  '[albumart/mb] hit mbid=$mbid release="${rel['title']}"');
            }
            return coverUrl;
          }
        }
      }
      if (kDebugMode) {
        debugPrint(
          '[albumart/mb] no non-compilation art for "$artist - $title"'
          ' (skipped $skippedCompilations compilation release(s))',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[albumart/mb] exception: $e');
    }
    return null;
  }

  /// True when a release is on a compilation. We skip these because the
  /// compilation's cover is almost always aesthetically disconnected from
  /// the track (e.g. "Rolling Stone Rare Trax Vol 18" for an electronic
  /// single). Better to show the station favicon than a misleading cover.
  bool _isCompilation(Map rel) {
    final group = rel['release-group'];
    if (group is! Map) return false;
    final secondary = group['secondary-types'];
    if (secondary is! List) return false;
    return secondary.any((t) => t is String && t.toLowerCase() == 'compilation');
  }

  /// HEAD the CAA front-500 endpoint. If it 30x/200s, the image exists
  /// and the URL is safe to return (the consumer's HTTP client follows
  /// the redirect). 404 means no cover art registered for this release.
  Future<String?> _caaFront(String mbid) async {
    final url = '/release/$mbid/front-500';
    try {
      final res = await _caaDio.head(url,
          options: Options(
            // Accept any 2xx/3xx; Dio normally treats some 3xx as errors.
            validateStatus: (s) => s != null && s >= 200 && s < 400,
          ));
      if (res.statusCode != null &&
          res.statusCode! >= 200 &&
          res.statusCode! < 400) {
        return ApiConstants.coverArtArchiveBaseUrl + url;
      }
    } catch (e) {
      // 404 or network error — no art here.
      if (kDebugMode) debugPrint('[albumart/caa] miss mbid=$mbid: $e');
    }
    return null;
  }

  /// Serialize calls to MusicBrainz with a >1s gap between them. MB's
  /// rate limit is firm; exceeding it can IP-block the app.
  Future<String?> _mbSerialized(Future<String?> Function() task) {
    final previous = _mbLane ?? Future<void>.value();
    final completer = Completer<String?>();
    _mbLane = previous.then((_) async {
      try {
        final result = await task();
        completer.complete(result);
      } catch (e) {
        completer.completeError(e);
      } finally {
        // Pad 1100ms so we're safely below 1/sec even with clock jitter.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      }
    });
    return completer.future;
  }

  /// Escape Lucene special characters so we don't break the query when
  /// the artist/title legitimately contains `:` or `"` or similar.
  String _lucene(String s) => s.replaceAll(RegExp(r'[\\+\-!\(\)\{\}\[\]\^"~*?:/]'), r' ');

  /// Tolerant JSON coercer. Dio only auto-parses when the response's
  /// content-type matches `application/json` — iTunes Search returns
  /// `text/javascript`, so `res.data` arrives as a raw String. Parse
  /// manually when that happens. Returns null for genuinely unparseable
  /// bodies.
  static Map<String, dynamic>? _asJsonMap(dynamic raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }

  // ------------------------------------------------------------------
  // Normalization + match verification
  // ------------------------------------------------------------------

  /// Lowercase, strip punctuation, collapse whitespace, and drop common
  /// suffixes that vary across catalogs — `feat. X`, `(Remix)`,
  /// `(Live)`, `- Remastered 2011`, etc. Result is meant only for
  /// comparison, never for display.
  static String _normalize(String s) {
    var out = s.toLowerCase();
    // Strip trailing feat./ft./featuring clauses so "Track feat. X" and
    // "Track" match.
    out = out.replaceAll(
        RegExp(r'\s+(feat\.?|ft\.?|featuring)\s.+$', caseSensitive: false), '');
    // Strip parenthetical versions / suffixes.
    out = out.replaceAll(
        RegExp(r'\s*\((remix|live|acoustic|remaster(ed)?|radio edit|edit|version|mix)\b[^)]*\)',
            caseSensitive: false),
        '');
    // Strip dash-suffix versions ("- Remix", "- Remastered 2015").
    out = out.replaceAll(
        RegExp(r'\s*-\s*(remix|live|acoustic|remaster(ed)?|radio edit|edit|version|mix)\b.*$',
            caseSensitive: false),
        '');
    // Punctuation → space (keeps letters, numbers, whitespace).
    out = out.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  /// True when a candidate result can be trusted as the same song as the
  /// query. We require both artist and title to match (either equal, or
  /// one-contains-the-other after normalization).
  ///
  /// Also accepts the artist/title swap case: SomaFM (and other radio
  /// streams) sometimes announce "Artist - Title" where the music
  /// services' canonical metadata has them the other way around
  /// (observed: "Northern Lights - Lux" on ICY vs. iTunes' "Lux -
  /// Northern Lights"). The swap check only succeeds when *both* fields
  /// match under the transpose, which is strong enough that random
  /// same-word collisions are unlikely.
  static bool _matchesQuery({
    required String candArtist,
    required String candTitle,
    required String qArtist,
    required String qTitle,
  }) {
    final a = _normalize(candArtist);
    final t = _normalize(candTitle);
    final qa = _normalize(qArtist);
    final qt = _normalize(qTitle);
    if (a.isEmpty || t.isEmpty || qa.isEmpty || qt.isEmpty) return false;
    if (_loosely(a, qa) && _loosely(t, qt)) return true;
    // Swap fallback.
    return _loosely(a, qt) && _loosely(t, qa);
  }

  /// Loose match that ALSO tolerates whitespace differences. Artist
  /// names commonly differ in spacing between stream ICY metadata and
  /// catalog entries ("Freshmoods" vs "Fresh Moods", "Linkin Park" vs
  /// "LinkinPark"). Falling back to a space-stripped comparison
  /// handles those without opening the matcher to unrelated collisions
  /// — any false positive here already existed under the contains
  /// check, which is itself forgiving.
  static bool _loosely(String x, String y) {
    if (x == y || x.contains(y) || y.contains(x)) return true;
    final xt = x.replaceAll(' ', '');
    final yt = y.replaceAll(' ', '');
    if (xt.isEmpty || yt.isEmpty) return false;
    return xt == yt || xt.contains(yt) || yt.contains(xt);
  }
}
