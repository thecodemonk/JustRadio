import 'dart:async';
import 'dart:math' as math;
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
  String _lastMetadata = '';
  bool _observingProperty = false;

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
        print('Player error: $error');
        _playbackStateController.add(PlaybackState.error);
        _nowPlayingController.add(NowPlaying.empty());
      }
    });

    // Listen for log messages from mpv
    _player.stream.log.listen((log) {
      print('mpv log [${log.level}]: ${log.prefix} - ${log.text}');
    });
  }

  Future<void> _setupMetadataObserver() async {
    if (_observingProperty) return;

    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        // Observe the media-title property which mpv populates from ICY metadata
        await platform.observeProperty(
          'media-title',
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
          'metadata/by-key/icy-title',
          (String? value) async {
            if (value != null && value.isNotEmpty && value != _lastMetadata) {
              _lastMetadata = value;
              _processMetadata(value);
            }
          },
        );
      }
    } catch (e) {
      // Property observation might not be available on all platforms
      print('Could not setup metadata observer: $e');
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

      print('Playing stream: ${station.streamUrl}');
      await _player.open(media, play: true);
      print('Stream opened successfully');
    } catch (e) {
      print('Error playing stream: $e');
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

  void dispose() {
    _playingSubscription?.cancel();
    _errorSubscription?.cancel();
    _nowPlayingController.close();
    _stationController.close();
    _playbackStateController.close();
    _playingController.close();
    _player.dispose();
  }
}
