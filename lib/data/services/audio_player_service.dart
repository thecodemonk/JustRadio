import 'dart:async';
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

class IcyDebugInfo {
  final String engine;
  final String? rawTitle;
  final String? rawUrl;
  final String? streamName;
  final String? genre;
  final int? bitrate;
  final String? codec;
  final DateTime timestamp;

  IcyDebugInfo({
    required this.engine,
    this.rawTitle,
    this.rawUrl,
    this.streamName,
    this.genre,
    this.bitrate,
    this.codec,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory IcyDebugInfo.empty(String engine) =>
      IcyDebugInfo(engine: engine, timestamp: DateTime.fromMillisecondsSinceEpoch(0));

  bool get isEmpty =>
      (rawTitle == null || rawTitle!.isEmpty) &&
      (rawUrl == null || rawUrl!.isEmpty) &&
      (streamName == null || streamName!.isEmpty);
}

abstract class AudioPlayerService {
  Stream<NowPlaying> get nowPlayingStream;
  Stream<RadioStation?> get stationStream;
  Stream<PlaybackState> get playbackStateStream;
  Stream<bool> get playingStream;
  Stream<IcyDebugInfo> get icyDebugStream;

  RadioStation? get currentStation;
  bool get isPlaying;
  String get engineName;

  Future<void> playStation(RadioStation station);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> togglePlayPause();
  Future<void> setVolume(double volume);
  Future<void> dispose();

  static Future<void> init() async {
    MediaKit.ensureInitialized();
  }
}
