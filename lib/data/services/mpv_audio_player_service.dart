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
  String _lastMetadata = '';
  bool _observingProperty = false;
  static const _mediaTitleProp = 'media-title';
  static const _icyTitleProp = 'metadata/by-key/icy-title';
  static const _icyNameProp = 'metadata/by-key/icy-name';
  static const _icyGenreProp = 'metadata/by-key/icy-genre';
  static const _icyUrlProp = 'metadata/by-key/icy-url';

  String? _streamName;
  String? _genre;
  String? _icyUrl;

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
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Could not setup metadata observer: $e');
      }
    }
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
      bitrate: null,
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
  }

  @override
  Future<void> togglePlayPause() async => _player.playOrPause();

  @override
  Future<void> setVolume(double volume) async {
    // Logarithmic curve for perceptually linear volume (human hearing is log).
    final linear = volume.clamp(0.0, 1.0);
    final logarithmic = linear <= 0 ? 0.0 : math.log(1 + linear * 9) / math.log(10);
    await _player.setVolume(logarithmic * 100);
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
    await _nowPlayingController.close();
    await _stationController.close();
    await _playbackStateController.close();
    await _playingController.close();
    await _icyDebugController.close();
    await _player.dispose();
  }
}
