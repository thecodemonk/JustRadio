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

/// Fired when the native side (Android Auto's love button, CarPlay's
/// likeCommand) toggles a track's loved state. The Flutter provider
/// merges this into its own state so the heart icon matches.
class LovedStateEvent {
  final String artist;
  final String title;
  final bool loved;

  const LovedStateEvent({
    required this.artist,
    required this.title,
    required this.loved,
  });
}

abstract class AudioPlayerService {
  Stream<NowPlaying> get nowPlayingStream;
  Stream<RadioStation?> get stationStream;
  Stream<PlaybackState> get playbackStateStream;
  Stream<bool> get playingStream;
  Stream<IcyDebugInfo> get icyDebugStream;

  /// Emits when native code changes the loved state — e.g. the driver
  /// tapped the love button on Android Auto. Desktop engines never emit.
  Stream<LovedStateEvent> get lovedStateStream => const Stream.empty();

  /// Emits when the native session hands us an already-resolved album
  /// art URL (e.g. after AA started playback before Flutter opened).
  /// The phone UI uses this to skip a redundant Dart-side lookup.
  Stream<String> get syncedAlbumArtStream => const Stream.empty();

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

  /// Mirror the Last.fm session key + username into native storage so the
  /// Android MediaSession / iOS remote-command handler can sign Last.fm
  /// requests when the Flutter activity isn't running. Pass null to clear.
  Future<void> syncLastfmSession({String? sessionKey, String? username}) async {}

  /// Mirror the Last.fm API credentials into native storage. Called once
  /// at startup — the values ship with the app regardless, so this is
  /// just a convenience for native code to read them from one place.
  Future<void> syncLastfmConfig(
      {required String apiKey, required String apiSecret}) async {}

  /// Tell the native side that Dart just resolved the loved state for a
  /// track, so the AA/CarPlay button can match without a duplicate HTTP
  /// lookup. The native side caches by "artist|title".
  Future<void> setLovedState(
      {required String artist,
      required String title,
      required bool loved}) async {}

  static Future<void> init() async {
    MediaKit.ensureInitialized();
  }
}
