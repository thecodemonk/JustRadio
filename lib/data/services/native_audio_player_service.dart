import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/radio_station.dart';
import '../models/now_playing.dart';
import 'audio_player_service.dart';

// Flip to true to print one log line per incoming metadata event — one per
// ID3 frame on HLS streams, which gets noisy fast. Off by default; state
// and error lines still print under kDebugMode.
const _verboseLogging = false;

/// Talks to the native platform audio engine (iOS + macOS AVPlayer,
/// Android ExoPlayer via MediaLibraryService) over two channels:
///   - MethodChannel "justradio/audio": play/pause/stop/setVolume commands
///   - EventChannel "justradio/audio/events": state + metadata updates
///
/// Uniformly handles ICY StreamTitle (Shoutcast/Icecast) and HLS ID3 timed
/// metadata — every platform emits a `{type: "metadata", title: "..."}`
/// payload when a usable title is found, regardless of underlying protocol.
class NativeAudioPlayerService extends AudioPlayerService {
  static const _methodChannel = MethodChannel('justradio/audio');
  static const _eventChannel = EventChannel('justradio/audio/events');

  RadioStation? _currentStation;
  final _nowPlayingController = StreamController<NowPlaying>.broadcast();
  final _stationController = StreamController<RadioStation?>.broadcast();
  final _playbackStateController = StreamController<PlaybackState>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _icyDebugController = StreamController<IcyDebugInfo>.broadcast();
  final _lovedStateController = StreamController<LovedStateEvent>.broadcast();
  // Emitted when the native MediaSession hands us an already-resolved
  // album art URL (e.g. on syncState after Android Auto cold start).
  // RadioPlayerController listens and mirrors into state.albumArtUrl
  // so the phone UI paints without re-running the Dart chain.
  final _syncedAlbumArtController = StreamController<String>.broadcast();

  StreamSubscription? _eventSubscription;
  bool _isPlaying = false;
  String? _lastTitle;
  String? _lastArtist;
  String? _lastAlbum;
  String? _codec;
  String? _streamName;
  String? _genre;
  int? _bitrate;
  String? _lastRawUrl;

  NativeAudioPlayerService() {
    _waitForPluginThenSubscribe();
  }

  Future<void> _waitForPluginThenSubscribe() async {
    // On Android the plugin can attach slightly after Dart starts running,
    // so subscribing to the event channel eagerly hits a fire-and-forget
    // MissingPluginException inside Flutter's services layer (we can't
    // catch it via onError). Call a ping method with retry until the
    // plugin responds, *then* subscribe — guaranteeing the channel is live.
    for (var i = 0; i < 20; i++) {
      try {
        await _methodChannel.invokeMethod<bool>('ping');
        _eventSubscription = _eventChannel
            .receiveBroadcastStream()
            .listen(_handleEvent, onError: _handleError);
        // Ask the native side to emit its current state. Needed when the
        // MediaSession has been running (e.g. Android Auto cold start),
        // because the auto-emit on MediaController.connect may fire
        // before we finish subscribing — events with a null eventSink
        // get dropped. This pull happens *after* onListen attaches the
        // sink, so delivery is guaranteed.
        try {
          await _methodChannel.invokeMethod('requestSync');
        } catch (_) {
          // iOS plugin doesn't implement this yet — harmless.
        }
        return;
      } on MissingPluginException {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    if (kDebugMode) {
      debugPrint('[native] gave up waiting for plugin to register');
    }
  }

  @override
  String get engineName => 'native';

  @override
  RadioStation? get currentStation => _currentStation;

  @override
  Stream<NowPlaying> get nowPlayingStream => _nowPlayingController.stream;
  @override
  Stream<RadioStation?> get stationStream => _stationController.stream;
  @override
  Stream<PlaybackState> get playbackStateStream => _playbackStateController.stream;
  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<IcyDebugInfo> get icyDebugStream => _icyDebugController.stream;
  @override
  Stream<LovedStateEvent> get lovedStateStream => _lovedStateController.stream;
  @override
  Stream<String> get syncedAlbumArtStream => _syncedAlbumArtController.stream;

  @override
  bool get isPlaying => _isPlaying;

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'] as String?;
    switch (type) {
      case 'state':
        _onStateEvent(event);
        break;
      case 'metadata':
        _onMetadataEvent(event);
        break;
      case 'debug':
        if (kDebugMode) {
          debugPrint('[native/debug] ${event['message']}');
        }
        break;
      case 'lovedStateChanged':
        final artist = event['artist'] as String?;
        final title = event['title'] as String?;
        final loved = event['loved'];
        if (artist != null && title != null && loved is bool) {
          _lovedStateController
              .add(LovedStateEvent(artist: artist, title: title, loved: loved));
        }
        break;
      case 'syncState':
        _onSyncState(event);
        break;
    }
  }

  /// Snapshot of what the native MediaSession is already doing — emitted
  /// by the Android plugin on MediaController connect when Android Auto
  /// has started playback before the Flutter activity opened. Without
  /// this event, Dart listens for *changes* on the event channel and
  /// never learns about the current station that's been playing.
  void _onSyncState(Map event) {
    final stationMap = event['station'];
    if (stationMap is! Map) return;
    final station = RadioStation(
      stationuuid: stationMap['stationuuid'] as String? ?? '',
      name: stationMap['name'] as String? ?? '',
      // Native ships the resolved stream URL as `streamUrl`; RadioStation
      // stores it under `url`.
      url: stationMap['streamUrl'] as String? ?? '',
      favicon: stationMap['favicon'] as String? ?? '',
      tags: stationMap['tags'] as String? ?? '',
      bitrate: _asInt(stationMap['bitrate']) ?? 0,
      codec: stationMap['codec'] as String? ?? '',
    );
    _currentStation = station;
    _stationController.add(station);

    final title = (event['title'] as String? ?? '').trim();
    final artist = (event['artist'] as String? ?? '').trim();
    final albumArtUrl = (event['albumArtUrl'] as String? ?? '').trim();
    if (title.isNotEmpty || artist.isNotEmpty) {
      _lastTitle = title.isEmpty ? null : title;
      _lastArtist = artist.isEmpty ? null : artist;
      _nowPlayingController.add(NowPlaying(
        title: title,
        artist: artist,
        rawMetadata: artist.isEmpty ? title : '$artist - $title',
      ));
    }
    // Album art the session already resolved via the native chain —
    // hand it directly to the controller so the phone UI doesn't have
    // to re-run the Dart chain just to paint. Accepted via a stream
    // that RadioPlayerController listens for (added alongside this).
    if (albumArtUrl.isNotEmpty) {
      _syncedAlbumArtController.add(albumArtUrl);
    }

    final isPlaying = event['isPlaying'];
    if (isPlaying is bool) {
      _isPlaying = isPlaying;
      _playingController.add(isPlaying);
      _playbackStateController
          .add(isPlaying ? PlaybackState.playing : PlaybackState.paused);
    }

    if (kDebugMode) {
      debugPrint(
          '[native] syncState: station="${station.name}" artist="$artist" title="$title" playing=$isPlaying');
    }
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  void _handleError(Object err) {
    if (kDebugMode) {
      debugPrint('[native] event channel error: $err');
    }
  }

  void _onStateEvent(Map event) {
    final state = event['state'] as String?;
    if (kDebugMode) {
      debugPrint('[native] state=$state message=${event['message']}');
    }
    switch (state) {
      case 'loading':
        _playbackStateController.add(PlaybackState.loading);
        break;
      case 'playing':
        _isPlaying = true;
        _playingController.add(true);
        _playbackStateController.add(PlaybackState.playing);
        break;
      case 'paused':
        _isPlaying = false;
        _playingController.add(false);
        _playbackStateController.add(PlaybackState.paused);
        break;
      case 'stopped':
        _isPlaying = false;
        _playingController.add(false);
        _playbackStateController.add(PlaybackState.stopped);
        break;
      case 'error':
        _playbackStateController.add(PlaybackState.error);
        _nowPlayingController.add(NowPlaying.empty());
        break;
      case 'idle':
        _playbackStateController.add(PlaybackState.idle);
        break;
    }
  }

  void _onMetadataEvent(Map event) {
    final identifier = event['identifier'] as String?;
    final stringValue = event['stringValue'] as String?;
    final title = event['title'] as String?;
    final artist = event['artist'] as String?;
    final album = event['album'] as String?;

    // Any event may carry stream-level info (bitrate/name/genre/codec). Pick
    // up whichever fields are present — ICY headers populate all of them,
    // stream/info events populate bitrate only, ID3 TFLT populates codec.
    final b = event['bitrate'];
    // Prefer-max: access log on HLS emits multiple entries with varying
    // observed rates; don't regress to a lower value once we've seen a
    // higher (more credible) one for the same session.
    if (b is int && b > 0 && (_bitrate == null || b > _bitrate!)) _bitrate = b;
    final sn = event['streamName'];
    if (sn is String && sn.isNotEmpty) _streamName = sn;
    final g = event['genre'];
    if (g is String && g.isNotEmpty) _genre = g;
    final su = event['streamUrl'];
    if (su is String && su.isNotEmpty) _lastRawUrl = su;
    final c = event['codec'];
    if (c is String && c.isNotEmpty) _codec = c;

    if (kDebugMode && _verboseLogging) {
      final br = event['bitrate'];
      final brStr = br == null ? '' : ' bitrate=$br';
      final desc = event['txxxDescriptor'];
      final descStr = desc == null ? '' : ' txxx=$desc';
      debugPrint(
        '[native] metadata id=$identifier title=$title artist=$artist stringValue=$stringValue$brStr$descStr',
      );
    }

    bool changed = false;
    if (artist != null && artist.isNotEmpty && artist != _lastArtist) {
      _lastArtist = artist;
      changed = true;
    }
    if (album != null && album.isNotEmpty && album != _lastAlbum) {
      _lastAlbum = album;
      // Not surfaced on NowPlaying yet; tracked for future album-art lookups.
    }
    if (title != null && title.isNotEmpty && title != _lastTitle) {
      _lastTitle = title;
      changed = true;
    }

    if (changed && _lastTitle != null) {
      _emitPaired(_lastTitle!, _lastArtist);
    }

    _icyDebugController.add(IcyDebugInfo(
      engine: engineName,
      rawTitle: title ?? stringValue,
      rawUrl: _lastRawUrl,
      streamName: _streamName,
      genre: _genre,
      bitrate: _bitrate,
      codec: _codec,
    ));
  }

  void _emitPaired(String title, String? artist) {
    NowPlaying nowPlaying;
    if (artist != null && artist.isNotEmpty) {
      // Paired fields arrived from HLS ID3 (TIT2 + TPE1) or similar —
      // trust them directly instead of splitting the title string.
      nowPlaying = NowPlaying(
        title: title,
        artist: artist,
        rawMetadata: '$artist - $title',
      );
    } else if (title.contains(' - ')) {
      // ICY StreamTitle typically packs "Artist - Title" into one field.
      final parts = title.split(' - ');
      nowPlaying = NowPlaying(
        artist: parts[0].trim(),
        title: parts.sublist(1).join(' - ').trim(),
        rawMetadata: title,
      );
    } else {
      nowPlaying = NowPlaying(title: title, artist: '', rawMetadata: title);
    }
    _nowPlayingController.add(nowPlaying);
  }

  @override
  Future<void> playStation(RadioStation station) async {
    _currentStation = station;
    _stationController.add(station);
    _nowPlayingController.add(NowPlaying.empty());
    _playbackStateController.add(PlaybackState.loading);
    _lastTitle = null;
    _lastArtist = null;
    _lastAlbum = null;
    _codec = null;
    _streamName = null;
    _genre = null;
    _bitrate = null;
    _lastRawUrl = null;
    // Push a cleared IcyDebugInfo so UI widgets reading the stream don't
    // keep showing the previous station's bitrate/codec until the new
    // station emits its first metadata event.
    _icyDebugController.add(IcyDebugInfo.empty(engineName));

    if (kDebugMode) {
      debugPrint('[native] Playing stream: ${station.streamUrl}');
    }

    try {
      // Pass station identity alongside the URL so the native media session
      // can attribute metadata to the right MediaItem. Android Auto uses
      // the mediaId + favicon; iOS uses the name in MPNowPlayingInfoCenter.
      await _methodChannel.invokeMethod('playStation', {
        'url': station.streamUrl,
        'stationuuid': station.stationuuid,
        'name': station.name,
        'favicon': station.favicon,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[native] Error playing stream: $e');
      }
      _playbackStateController.add(PlaybackState.error);
      _nowPlayingController.add(NowPlaying.empty());
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    await _methodChannel.invokeMethod('play');
  }

  @override
  Future<void> pause() async {
    await _methodChannel.invokeMethod('pause');
  }

  @override
  Future<void> stop() async {
    await _methodChannel.invokeMethod('stop');
    _currentStation = null;
    _stationController.add(null);
    _nowPlayingController.add(NowPlaying.empty());
    _lastTitle = null;
  }

  @override
  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    // Human hearing is logarithmic, so amplitude has to grow exponentially
    // in the slider for perceived loudness to feel linear. `x^2.5` (cube-
    // ish audio taper) is the classic fit: slider 0.5 → ~0.18 amplitude
    // (~half perceived loudness), slider 1.0 → 1.0. Past formula was
    // log(1 + 9x) which went the wrong way — made the lower half of the
    // slider jump to ~90% loudness by the midpoint.
    final linear = volume.clamp(0.0, 1.0);
    final amplitude = math.pow(linear, 2.5).toDouble();
    await _methodChannel.invokeMethod('setVolume', {'volume': amplitude});
  }

  // ------------------------------------------------------------------
  // Library-tree mirrors. Android Auto can start the PlaybackService cold
  // (driver plugs in the phone without opening the app first), so we mirror
  // favorites / recent / genre catalogs into SharedPreferences. The native
  // MediaLibraryService reads from that same store to serve browse results.
  // iOS currently ignores these calls (the CarPlay work picks them up in
  // Phase 3).
  // ------------------------------------------------------------------

  @override
  Future<void> syncFavorites(List<RadioStation> stations) async {
    await _tryInvoke('syncFavorites', {
      'stations': stations.map(_stationToMap).toList(),
    });
  }

  @override
  Future<void> syncRecent(List<RadioStation> stations) async {
    await _tryInvoke('syncRecent', {
      'stations': stations.map(_stationToMap).toList(),
    });
  }

  @override
  Future<void> syncGenres(List<String> tagNames) async {
    await _tryInvoke('syncGenres', {
      'genres': tagNames.map((n) => {'name': n}).toList(),
    });
  }

  @override
  Future<void> syncGenreStations(String tag, List<RadioStation> stations) async {
    await _tryInvoke('syncGenreStations', {
      'tag': tag,
      'stations': stations.map(_stationToMap).toList(),
    });
  }

  @override
  Future<void> setAlbumArt(String? url) async {
    await _tryInvoke('setAlbumArt', {'url': url ?? ''});
  }

  @override
  Future<void> syncLastfmSession(
      {String? sessionKey, String? username}) async {
    await _tryInvoke('syncLastfmSession', {
      'sessionKey': sessionKey ?? '',
      'username': username ?? '',
    });
  }

  @override
  Future<void> syncLastfmConfig(
      {required String apiKey, required String apiSecret}) async {
    await _tryInvoke('syncLastfmConfig', {
      'apiKey': apiKey,
      'apiSecret': apiSecret,
    });
  }

  @override
  Future<void> setLovedState(
      {required String artist,
      required String title,
      required bool loved}) async {
    await _tryInvoke('setLovedState', {
      'artist': artist,
      'title': title,
      'loved': loved,
    });
  }

  Map<String, dynamic> _stationToMap(RadioStation s) => {
        'stationuuid': s.stationuuid,
        'name': s.name,
        'streamUrl': s.streamUrl,
        'favicon': s.favicon,
        'tags': s.tags,
        'bitrate': s.bitrate,
        'codec': s.codec,
      };

  Future<void> _tryInvoke(String method, Map<String, dynamic> args) async {
    try {
      await _methodChannel.invokeMethod(method, args);
    } catch (e) {
      // iOS plugin doesn't handle these yet; ignore notImplemented noise.
      if (kDebugMode) debugPrint('[native] $method skipped: $e');
    }
  }

  @override
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _nowPlayingController.close();
    await _stationController.close();
    await _playbackStateController.close();
    await _playingController.close();
    await _icyDebugController.close();
    await _lovedStateController.close();
    await _syncedAlbumArtController.close();
    try {
      await _methodChannel.invokeMethod('stop');
    } catch (_) {}
  }
}
