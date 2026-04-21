import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/radio_station.dart';
import '../data/models/now_playing.dart';
import '../data/services/audio_player_service.dart';
import '../data/repositories/radio_browser_repository.dart';
import 'lastfm_provider.dart';
import 'recent_plays_provider.dart';

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = AudioPlayerService();
  ref.onDispose(() {
    // Fire-and-forget: Provider.onDispose is sync. The service awaits its
    // own internal teardown (observers, streams, player); we just kick it off.
    service.dispose();
  });
  return service;
});

final currentStationProvider = StreamProvider<RadioStation?>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.stationStream;
});

final nowPlayingProvider = StreamProvider<NowPlaying>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.nowPlayingStream;
});

final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.playbackStateStream;
});

final isPlayingProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.playingStream;
});

final radioPlayerControllerProvider =
    StateNotifierProvider<RadioPlayerController, RadioPlayerState>((ref) {
  return RadioPlayerController(ref);
});

class RadioPlayerState {
  final RadioStation? currentStation;
  final NowPlaying nowPlaying;
  final bool isPlaying;
  final bool isLoading;
  final String? error;

  RadioPlayerState({
    this.currentStation,
    NowPlaying? nowPlaying,
    this.isPlaying = false,
    this.isLoading = false,
    this.error,
  }) : nowPlaying = nowPlaying ?? NowPlaying.empty();

  RadioPlayerState copyWith({
    RadioStation? currentStation,
    NowPlaying? nowPlaying,
    bool? isPlaying,
    bool? isLoading,
    String? error,
    bool clearStation = false,
    bool clearError = false,
  }) {
    return RadioPlayerState(
      currentStation: clearStation ? null : (currentStation ?? this.currentStation),
      nowPlaying: nowPlaying ?? this.nowPlaying,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class RadioPlayerController extends StateNotifier<RadioPlayerState> {
  final Ref _ref;
  StreamSubscription? _playbackStateSubscription;
  StreamSubscription? _stationSubscription;
  StreamSubscription? _nowPlayingSubscription;
  DateTime? _trackStartTime;
  NowPlaying? _lastScrobbledTrack;

  RadioPlayerController(this._ref) : super(RadioPlayerState()) {
    _initListeners();
  }

  AudioPlayerService get _playerService =>
      _ref.read(audioPlayerServiceProvider);

  void _initListeners() {
    _playbackStateSubscription = _playerService.playbackStateStream.listen((playbackState) {
      state = state.copyWith(
        isPlaying: playbackState == PlaybackState.playing,
        isLoading: playbackState == PlaybackState.loading,
      );
    });

    _stationSubscription = _playerService.stationStream.listen((station) {
      state = state.copyWith(
        currentStation: station,
        clearStation: station == null,
      );
    });

    _nowPlayingSubscription = _playerService.nowPlayingStream.listen((nowPlaying) {
      final previousNowPlaying = state.nowPlaying;
      state = state.copyWith(nowPlaying: nowPlaying);

      // Handle Last.fm integration
      if (nowPlaying.isNotEmpty && nowPlaying != previousNowPlaying) {
        _handleTrackChange(nowPlaying, previousNowPlaying);
      }
    });
  }

  // Last.fm's scrobble policy requires "played for at least half the track or
  // 4 minutes, whichever comes first, and longer than 30 seconds." For radio
  // streams we don't know track length, so we use a 30s floor — matching the
  // copy in the Last.fm settings screen.
  static const _scrobbleMinSeconds = 30;

  void _handleTrackChange(NowPlaying current, NowPlaying previous) {
    if (previous.isNotEmpty && _trackStartTime != null) {
      final playDuration = DateTime.now().difference(_trackStartTime!);
      if (playDuration.inSeconds >= _scrobbleMinSeconds) {
        _scrobbleTrack(previous, _trackStartTime!);
      }
    }

    _trackStartTime = DateTime.now();
    _updateNowPlaying(current);
  }

  Future<void> _updateNowPlaying(NowPlaying nowPlaying) async {
    if (nowPlaying.artist.isEmpty || nowPlaying.title.isEmpty) return;

    final lastfmService = _ref.read(lastfmAuthServiceProvider);
    if (lastfmService.isAuthenticated) {
      await lastfmService.repository.updateNowPlaying(
        artist: nowPlaying.artist,
        track: nowPlaying.title,
      );
    }
  }

  Future<void> _scrobbleTrack(NowPlaying track, DateTime timestamp) async {
    if (track.artist.isEmpty || track.title.isEmpty) return;
    if (_lastScrobbledTrack == track) return; // Avoid duplicate scrobbles

    final lastfmService = _ref.read(lastfmAuthServiceProvider);
    if (lastfmService.isAuthenticated) {
      final success = await lastfmService.repository.scrobble(
        artist: track.artist,
        track: track.title,
        timestamp: timestamp.millisecondsSinceEpoch ~/ 1000,
      );

      if (success) {
        _lastScrobbledTrack = track;
      }
    }
  }

  Future<void> playStation(RadioStation station) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Register click with Radio Browser
      final repository = _ref.read(radioBrowserRepositoryProvider);
      repository.registerClick(station.stationuuid);

      await _playerService.playStation(station);
      _trackStartTime = DateTime.now();

      // Record in recently played history
      _ref.read(recentPlaysProvider.notifier).record(station);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to play station: ${e.toString()}',
      );
    }
  }

  Future<void> play() async {
    await _playerService.play();
  }

  Future<void> pause() async {
    await _playerService.pause();
  }

  Future<void> stop() async {
    // Scrobble current track before stopping
    final nowPlaying = state.nowPlaying;
    if (nowPlaying.isNotEmpty && _trackStartTime != null) {
      final playDuration = DateTime.now().difference(_trackStartTime!);
      if (playDuration.inSeconds >= _scrobbleMinSeconds) {
        _scrobbleTrack(nowPlaying, _trackStartTime!);
      }
    }

    await _playerService.stop();
    _trackStartTime = null;
  }

  Future<void> togglePlayPause() async {
    await _playerService.togglePlayPause();
  }

  @override
  void dispose() {
    _playbackStateSubscription?.cancel();
    _stationSubscription?.cancel();
    _nowPlayingSubscription?.cancel();
    super.dispose();
  }
}

final radioBrowserRepositoryProvider = Provider<RadioBrowserRepository>((ref) {
  return RadioBrowserRepository();
});

// Volume control provider
final volumeProvider = StateNotifierProvider<VolumeController, double>((ref) {
  return VolumeController(ref);
});

class VolumeController extends StateNotifier<double> {
  final Ref _ref;

  VolumeController(this._ref) : super(1.0);

  Future<void> setVolume(double volume) async {
    state = volume.clamp(0.0, 1.0);
    await _ref.read(audioPlayerServiceProvider).setVolume(state);
  }
}
