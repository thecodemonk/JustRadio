import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import '../models/radio_station.dart';
import '../models/now_playing.dart';
import 'audio_player_service.dart';

class MpvAudioPlayerService extends AudioPlayerService {
  final Player _player;
  RadioStation? _currentStation;
  final _nowPlayingController = StreamController<NowPlaying>.broadcast();
  final _stationController = StreamController<RadioStation?>.broadcast();
  final _playbackStateController = StreamController<PlaybackState>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _icyDebugController = StreamController<IcyDebugInfo>.broadcast();

  StreamSubscription? _playingSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _logSubscription;
  StreamSubscription? _tracksSubscription;
  String _lastMetadata = '';
  bool _observingProperty = false;
  static const _mediaTitleProp = 'media-title';
  // ICY metadata from Shoutcast/Icecast streams — surfaced by mpv under
  // the icy-* tag namespace when the server sends Icy-MetaData.
  static const _icyTitleProp = 'metadata/by-key/icy-title';
  static const _icyNameProp = 'metadata/by-key/icy-name';
  static const _icyGenreProp = 'metadata/by-key/icy-genre';
  static const _icyUrlProp = 'metadata/by-key/icy-url';
  // Plain metadata keys — mpv populates these for Ogg/Vorbis and other
  // sources that use standard tag names. HLS streams *also* embed ID3
  // frames (TIT2/TPE1), but mpv doesn't parse them yet (mpv#14756); Apple
  // platforms route around that by using the native AVPlayer bridge.
  // Keeping the observers registered is harmless — they just stay silent
  // for HLS streams.
  static const _hlsTitleProp = 'metadata/by-key/title';
  static const _hlsArtistProp = 'metadata/by-key/artist';
  // Bits per second — throttled updates, so observing is fine.
  static const _audioBitrateProp = 'audio-bitrate';

  String? _streamName;
  String? _genre;
  String? _icyUrl;
  String? _codec;
  int? _bitrate; // kbps
  String? _hlsTitle;
  String? _hlsArtist;

  MpvAudioPlayerService() : _player = Player() {
    _initListeners();
  }

  @override
  String get engineName => 'mpv';

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
  bool get isPlaying => _player.state.playing;

  void _initListeners() {
    _playingSubscription = _player.stream.playing.listen((playing) {
      _playingController.add(playing);
      if (playing) {
        _playbackStateController.add(PlaybackState.playing);
      } else if (_currentStation != null) {
        _playbackStateController.add(PlaybackState.paused);
      }
    });

    _errorSubscription = _player.stream.error.listen((error) {
      if (error.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('Player error: $error');
        }
        _playbackStateController.add(PlaybackState.error);
        _nowPlayingController.add(NowPlaying.empty());
      }
    });

    _logSubscription = _player.stream.log.listen((log) {
      if (kDebugMode) {
        debugPrint('mpv log [${log.level}]: ${log.prefix} - ${log.text}');
      }
    });

    // Codec comes from the selected audio track. media_kit broadcasts the
    // track list whenever it changes, which for our use is right after the
    // stream opens (and if mpv switches a rendition mid-stream).
    _tracksSubscription = _player.stream.tracks.listen((tracks) {
      final audio = tracks.audio;
      if (audio.isEmpty) return;
      // The currently-selected audio track is reflected in player.state;
      // fall back to first track if selection hasn't been read yet.
      final selectedId = _player.state.track.audio.id;
      final active = audio.firstWhere(
        (t) => t.id == selectedId,
        orElse: () => audio.first,
      );
      final codec = active.codec;
      if (codec != null && codec.isNotEmpty && codec != _codec) {
        _codec = codec;
        _emitDebug();
      }
    });
  }

  Future<void> _setupMetadataObserver() async {
    if (_observingProperty) return;

    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.observeProperty(_mediaTitleProp, (String? value) async {
          if (value != null && value.isNotEmpty && value != _lastMetadata) {
            _lastMetadata = value;
            _processMetadata(value);
          }
        });
        _observingProperty = true;

        await platform.observeProperty(_icyTitleProp, (String? value) async {
          if (value != null && value.isNotEmpty && value != _lastMetadata) {
            _lastMetadata = value;
            _processMetadata(value);
          }
        });

        await platform.observeProperty(_icyNameProp, (String? value) async {
          _streamName = value;
          _emitDebug();
        });
        await platform.observeProperty(_icyGenreProp, (String? value) async {
          _genre = value;
          _emitDebug();
        });
        await platform.observeProperty(_icyUrlProp, (String? value) async {
          _icyUrl = value;
          _emitDebug();
        });

        // HLS ID3 frames — title / artist / album arrive as separate
        // properties, so we collect them and emit a paired NowPlaying
        // once both artist + title are present (same as the mobile
        // service's HLS flow).
        await platform.observeProperty(_hlsTitleProp, (String? value) async {
          if (value == null || value.isEmpty) return;
          _hlsTitle = value;
          _emitHlsNowPlayingIfReady();
        });
        await platform.observeProperty(_hlsArtistProp, (String? value) async {
          if (value == null || value.isEmpty) return;
          _hlsArtist = value;
          _emitHlsNowPlayingIfReady();
        });
        // NowPlaying doesn't surface album yet, so we don't observe
        // metadata/by-key/album. Add here when album-driven album-art
        // lookup becomes a thing (see Phase 5).

        // audio-bitrate is reported by mpv in bits/sec. Throttled updates
        // from the demuxer — no need to rate-limit on our end.
        await platform.observeProperty(_audioBitrateProp, (String? value) async {
          final bps = int.tryParse(value ?? '');
          if (bps == null || bps <= 0) return;
          final kbps = (bps / 1000).round();
          if (kbps == _bitrate) return;
          _bitrate = kbps;
          _emitDebug();
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Could not setup metadata observer: $e');
      }
    }
  }

  void _emitHlsNowPlayingIfReady() {
    final title = _hlsTitle;
    final artist = _hlsArtist;
    if (title == null || title.isEmpty) return;
    final np = NowPlaying(
      title: title,
      artist: artist ?? '',
      rawMetadata: artist == null || artist.isEmpty
          ? title
          : '$artist - $title',
    );
    _nowPlayingController.add(np);
    _emitDebug(rawTitle: np.rawMetadata);
  }

  @override
  Future<void> playStation(RadioStation station) async {
    _currentStation = station;
    _stationController.add(station);
    _nowPlayingController.add(NowPlaying.empty());
    _playbackStateController.add(PlaybackState.loading);
    _lastMetadata = '';
    _streamName = null;
    _genre = null;
    _icyUrl = null;
    _codec = null;
    _bitrate = null;
    _hlsTitle = null;
    _hlsArtist = null;
    // Reset the debug surface so stale bitrate/codec doesn't persist while
    // the new station is loading.
    _icyDebugController.add(IcyDebugInfo.empty(engineName));

    try {
      await _setupMetadataObserver();

      final media = Media(
        station.streamUrl,
        httpHeaders: {'Icy-MetaData': '1'},
      );

      if (kDebugMode) {
        debugPrint('Playing stream: ${station.streamUrl}');
      }
      await _player.open(media, play: true);
      if (kDebugMode) {
        debugPrint('Stream opened successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error playing stream: $e');
      }
      _playbackStateController.add(PlaybackState.error);
      _nowPlayingController.add(NowPlaying.empty());
      rethrow;
    }
  }

  void _processMetadata(String title) {
    NowPlaying nowPlaying;

    if (title.contains(' - ')) {
      final parts = title.split(' - ');
      nowPlaying = NowPlaying(
        artist: parts[0].trim(),
        title: parts.sublist(1).join(' - ').trim(),
        rawMetadata: title,
      );
    } else {
      nowPlaying = NowPlaying(
        title: title,
        artist: '',
        rawMetadata: title,
      );
    }

    _nowPlayingController.add(nowPlaying);
    _emitDebug(rawTitle: title);
  }

  void _emitDebug({String? rawTitle}) {
    _icyDebugController.add(IcyDebugInfo(
      engine: engineName,
      rawTitle: rawTitle ?? (_lastMetadata.isEmpty ? null : _lastMetadata),
      rawUrl: _icyUrl,
      streamName: _streamName,
      genre: _genre,
      bitrate: _bitrate,
      codec: _codec,
    ));
  }

  @override
  Future<void> play() async => _player.play();

  @override
  Future<void> pause() async => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    _currentStation = null;
    _stationController.add(null);
    _nowPlayingController.add(NowPlaying.empty());
    _playbackStateController.add(PlaybackState.stopped);
    _lastMetadata = '';
    _streamName = null;
    _genre = null;
    _icyUrl = null;
    _codec = null;
    _bitrate = null;
    _hlsTitle = null;
    _hlsArtist = null;
  }

  @override
  Future<void> togglePlayPause() async => _player.playOrPause();

  @override
  Future<void> setVolume(double volume) async {
    // Cube-ish audio taper — see native_mobile_audio_player_service for
    // the rationale. Amplitude = linear^2.5 so the slider feels linear to
    // the ear. mpv.setVolume takes 0..100.
    final linear = volume.clamp(0.0, 1.0);
    final amplitude = math.pow(linear, 2.5).toDouble();
    await _player.setVolume(amplitude * 100);
  }

  @override
  Future<void> dispose() async {
    // mpv throws if you unobserve after dispose — do this first.
    if (_observingProperty) {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        for (final prop in const [
          _mediaTitleProp,
          _icyTitleProp,
          _icyNameProp,
          _icyGenreProp,
          _icyUrlProp,
          _hlsTitleProp,
          _hlsArtistProp,
          _audioBitrateProp,
        ]) {
          try {
            await platform.unobserveProperty(prop);
          } catch (_) {}
        }
      }
      _observingProperty = false;
    }

    await _playingSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _logSubscription?.cancel();
    await _tracksSubscription?.cancel();
    await _nowPlayingController.close();
    await _stationController.close();
    await _playbackStateController.close();
    await _playingController.close();
    await _icyDebugController.close();
    await _player.dispose();
  }
}
