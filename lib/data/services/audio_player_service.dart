import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import '../models/radio_station.dart';
import '../models/now_playing.dart';

enum PlaybackState {
  idle,
  loading,
  playing,
  paused,
  stopped,
  error,
}

class AudioPlayerService {
  final Player _player;
  RadioStation? _currentStation;
  final _nowPlayingController = StreamController<NowPlaying>.broadcast();
  final _stationController = StreamController<RadioStation?>.broadcast();
  final _playbackStateController = StreamController<PlaybackState>.broadcast();
  final _playingController = StreamController<bool>.broadcast();

  StreamSubscription? _playingSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _logSubscription;
  String _lastMetadata = '';
  bool _observingProperty = false;
  static const _mediaTitleProp = 'media-title';
  static const _icyTitleProp = 'metadata/by-key/icy-title';

  AudioPlayerService() : _player = Player() {
    _initListeners();
  }

  static Future<void> init() async {
    MediaKit.ensureInitialized();
  }

  Player get player => _player;
  RadioStation? get currentStation => _currentStation;
  Stream<NowPlaying> get nowPlayingStream => _nowPlayingController.stream;
  Stream<RadioStation?> get stationStream => _stationController.stream;
  Stream<PlaybackState> get playbackStateStream => _playbackStateController.stream;
  Stream<bool> get playingStream => _playingController.stream;

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
        // Observe the media-title property which mpv populates from ICY metadata
        await platform.observeProperty(
          _mediaTitleProp,
          (String? value) async {
            if (value != null && value.isNotEmpty && value != _lastMetadata) {
              _lastMetadata = value;
              _processMetadata(value);
            }
          },
        );
        _observingProperty = true;

        // Also try observing the specific ICY title property
        await platform.observeProperty(
          _icyTitleProp,
          (String? value) async {
            if (value != null && value.isNotEmpty && value != _lastMetadata) {
              _lastMetadata = value;
              _processMetadata(value);
            }
          },
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Could not setup metadata observer: $e');
      }
    }
  }

  Future<void> playStation(RadioStation station) async {
    _currentStation = station;
    _stationController.add(station);
    _nowPlayingController.add(NowPlaying.empty());
    _playbackStateController.add(PlaybackState.loading);
    _lastMetadata = '';

    try {
      // Setup metadata observer before playing
      await _setupMetadataObserver();

      // Open the stream URL
      final media = Media(
        station.streamUrl,
        httpHeaders: {
          'Icy-MetaData': '1',
        },
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

    // Try to parse "Artist - Title" format
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
  }

  Future<void> play() async {
    await _player.play();
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
    _currentStation = null;
    _stationController.add(null);
    _nowPlayingController.add(NowPlaying.empty());
    _playbackStateController.add(PlaybackState.stopped);
    _lastMetadata = '';
  }

  Future<void> togglePlayPause() async {
    await _player.playOrPause();
  }

  Future<void> setVolume(double volume) async {
    // Apply logarithmic curve for perceptually linear volume control.
    // Human hearing is logarithmic, so a linear slider feels wrong.
    // This formula maps linear 0-1 to a curve where the midpoint
    // gives more perceived volume (slider 0.5 → ~74% actual volume).
    final linear = volume.clamp(0.0, 1.0);
    final logarithmic = linear <= 0 ? 0.0 : math.log(1 + linear * 9) / math.log(10);
    await _player.setVolume(logarithmic * 100);
  }

  Future<void> dispose() async {
    // Unobserve mpv properties BEFORE disposing the player; NativePlayer
    // throws an AssertionError if you call unobserveProperty after dispose.
    if (_observingProperty) {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        for (final prop in const [_mediaTitleProp, _icyTitleProp]) {
          try {
            await platform.unobserveProperty(prop);
          } catch (_) {
            // Already gone or never successfully observed — safe to ignore.
          }
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
    await _player.dispose();
  }
}
