import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/radio_station.dart';
import '../models/now_playing.dart';

class AudioPlayerService {
  final AudioPlayer _player;
  RadioStation? _currentStation;
  final _nowPlayingController = StreamController<NowPlaying>.broadcast();
  final _stationController = StreamController<RadioStation?>.broadcast();
  Timer? _metadataTimer;

  AudioPlayerService() : _player = AudioPlayer();

  static Future<void> init() async {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.justradio.channel.audio',
      androidNotificationChannelName: 'JustRadio',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    );
  }

  AudioPlayer get player => _player;
  RadioStation? get currentStation => _currentStation;
  Stream<NowPlaying> get nowPlayingStream => _nowPlayingController.stream;
  Stream<RadioStation?> get stationStream => _stationController.stream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<Duration?> get positionStream => _player.positionStream;

  bool get isPlaying => _player.playing;

  Future<void> playStation(RadioStation station) async {
    _currentStation = station;
    _stationController.add(station);

    final mediaItem = MediaItem(
      id: station.stationuuid,
      title: station.name,
      artist: station.tags.isNotEmpty ? station.tagList.first : 'Radio',
      artUri: station.favicon.isNotEmpty ? Uri.tryParse(station.favicon) : null,
      extras: {'url': station.streamUrl},
    );

    try {
      final audioSource = AudioSource.uri(
        Uri.parse(station.streamUrl),
        tag: mediaItem,
      );

      await _player.setAudioSource(audioSource);
      await _player.play();

      _startMetadataListener();
    } catch (e) {
      _nowPlayingController.add(NowPlaying.empty());
      rethrow;
    }
  }

  void _startMetadataListener() {
    _metadataTimer?.cancel();

    // Listen to ICY metadata from the stream
    _player.icyMetadataStream.listen((metadata) {
      if (metadata != null) {
        final nowPlaying = NowPlaying(
          title: metadata.info?.title ?? '',
          artist: '',
          rawMetadata: metadata.info?.title ?? '',
        );

        // Try to parse artist - title format
        final title = metadata.info?.title ?? '';
        if (title.contains(' - ')) {
          final parts = title.split(' - ');
          final parsed = NowPlaying(
            artist: parts[0].trim(),
            title: parts.sublist(1).join(' - ').trim(),
            rawMetadata: title,
          );
          _nowPlayingController.add(parsed);
          _updateMediaItemWithMetadata(parsed);
        } else {
          _nowPlayingController.add(nowPlaying);
          _updateMediaItemWithMetadata(nowPlaying);
        }
      }
    });
  }

  void _updateMediaItemWithMetadata(NowPlaying nowPlaying) {
    // Note: Media notification updates are handled automatically by just_audio_background
    // through the MediaItem tag set on the audio source
  }

  Future<void> play() async {
    await _player.play();
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    _metadataTimer?.cancel();
    await _player.stop();
    _currentStation = null;
    _stationController.add(null);
    _nowPlayingController.add(NowPlaying.empty());
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  void dispose() {
    _metadataTimer?.cancel();
    _nowPlayingController.close();
    _stationController.close();
    _player.dispose();
  }
}
