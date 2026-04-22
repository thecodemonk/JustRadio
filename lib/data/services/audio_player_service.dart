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

  // Library-tree mirrors for Android Auto / CarPlay. Default no-ops — only
  // the native mobile service writes these into SharedPreferences / NSUserDefaults
  // so the platform media sessions can serve the browse tree when the Flutter
  // activity isn't running.
  Future<void> syncFavorites(List<RadioStation> stations) async {}
  Future<void> syncRecent(List<RadioStation> stations) async {}
  Future<void> syncGenres(List<String> tagNames) async {}
  Future<void> syncGenreStations(String tag, List<RadioStation> stations) async {}

  /// Push the current track's album art URL to the native lock-screen /
  /// Android Auto / CarPlay now-playing surface. Null clears it. Default
  /// no-op on desktop (media_kit doesn't need this — album art flows
  /// through the Flutter UI directly).
  Future<void> setAlbumArt(String? url) async {}

  static Future<void> init() async {
    MediaKit.ensureInitialized();
  }
}
