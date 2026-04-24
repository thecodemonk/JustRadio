import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/radio_station.dart';
import '../data/models/now_playing.dart';
import '../data/services/audio_player_service.dart';
import '../data/services/mpv_audio_player_service.dart';
import '../data/services/native_audio_player_service.dart';
import '../data/repositories/radio_browser_repository.dart';
import 'album_art_provider.dart';
import 'lastfm_provider.dart';
import 'recent_plays_provider.dart';
import 'unsplash_provider.dart' show appSettingsRepositoryProvider;

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  // Apple platforms + Android use the native platform bridge:
  //   - iOS + macOS both go through AudioPlayerPlugin.swift (AVPlayer +
  //     AVAssetResourceLoader for ICY + AVPlayerItemMetadataOutput for HLS ID3)
  //   - Android uses AudioPlayerPlugin.kt (MediaLibraryService + ExoPlayer)
  // Windows and Linux stay on media_kit/mpv — mpv's HLS ID3 support is
  // absent (mpv#14756), but on Apple platforms AVPlayer handles it natively.
  final hasNativeBridge =
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  final AudioPlayerService service = hasNativeBridge
      ? NativeAudioPlayerService()
      : MpvAudioPlayerService();

  ref.onDispose(() {
    // Fire-and-forget: Provider.onDispose is sync. The service awaits its
    // own internal teardown (observers, streams, player); we just kick it off.
    service.dispose();
  });
  return service;
});

final icyDebugStreamProvider = StreamProvider<IcyDebugInfo>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.icyDebugStream;
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

  /// Album art URL for the current [nowPlaying] track, when lookup has
  /// succeeded. Null when lookup is pending, missed, or the track has no
  /// artist/title yet. UI falls back to station logo.
  final String? albumArtUrl;

  RadioPlayerState({
    this.currentStation,
    NowPlaying? nowPlaying,
    this.isPlaying = false,
    this.isLoading = false,
    this.error,
    this.albumArtUrl,
  }) : nowPlaying = nowPlaying ?? NowPlaying.empty();

  RadioPlayerState copyWith({
    RadioStation? currentStation,
    NowPlaying? nowPlaying,
    bool? isPlaying,
    bool? isLoading,
    String? error,
    String? albumArtUrl,
    bool clearStation = false,
    bool clearError = false,
    bool clearAlbumArt = false,
  }) {
    return RadioPlayerState(
      currentStation: clearStation ? null : (currentStation ?? this.currentStation),
      nowPlaying: nowPlaying ?? this.nowPlaying,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      albumArtUrl: clearAlbumArt ? null : (albumArtUrl ?? this.albumArtUrl),
    );
  }
}

class RadioPlayerController extends StateNotifier<RadioPlayerState> {
  final Ref _ref;
  StreamSubscription? _playbackStateSubscription;
  StreamSubscription? _stationSubscription;
  StreamSubscription? _nowPlayingSubscription;
  StreamSubscription? _syncedAlbumArtSubscription;
  DateTime? _trackStartTime;
  NowPlaying? _lastScrobbledTrack;

  // Album-art lookup debouncing. Metadata often arrives in bursts (HLS sends
  // TIT2 and TPE1 as separate frames) — debounce so we don't fire a lookup
  // against the half-filled pair. Dedupe by the resolved key to avoid
  // repeated lookups when the same track's metadata arrives twice.
  Timer? _albumArtDebounce;
  NowPlaying? _lastArtLookupKey;

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
      // Clear stale album art whenever the track identity changes — the
      // new lookup will fill it back in below (or leave it null on miss).
      final artChanged = nowPlaying != previousNowPlaying;
      state = state.copyWith(
        nowPlaying: nowPlaying,
        clearAlbumArt: artChanged,
      );

      // NowPlaying.empty() is the "fresh session" signal the service
      // emits on playStation / stop. Drop the lookup dedupe cache here so
      // restarting the same station mid-song re-resolves art instead of
      // short-circuiting on a stale _lastArtLookupKey match.
      if (nowPlaying.isEmpty) {
        _lastArtLookupKey = null;
        _albumArtDebounce?.cancel();
      }

      // Handle Last.fm integration + album art lookup
      if (nowPlaying.isNotEmpty && artChanged) {
        _handleTrackChange(nowPlaying, previousNowPlaying);
        _scheduleAlbumArtLookup(nowPlaying);
      }
    });

    // Native side may hand us an already-resolved art URL (syncState
    // after AA cold start, or a cached hit in native's SharedPreferences
    // cache that arrived before Dart's chain). Mirror into state and
    // mark it as already-looked-up so we don't redundantly fire the
    // Dart chain for the same track.
    _syncedAlbumArtSubscription =
        _playerService.syncedAlbumArtStream.listen((url) {
      if (url.isEmpty) return;
      if (state.albumArtUrl == url) return;
      state = state.copyWith(albumArtUrl: url);
      _lastArtLookupKey = state.nowPlaying;
    });
  }

  void _scheduleAlbumArtLookup(NowPlaying nowPlaying) {
    if (nowPlaying.artist.isEmpty || nowPlaying.title.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[albumart] skip: missing artist/title (artist="${nowPlaying.artist}" title="${nowPlaying.title}")',
        );
      }
      return;
    }
    if (_looksLikeStationId(nowPlaying.artist)) {
      if (kDebugMode) {
        debugPrint(
          '[albumart] skip: "${nowPlaying.artist}" looks like a station id',
        );
      }
      return;
    }
    if (_lastArtLookupKey == nowPlaying) return;

    if (kDebugMode) {
      debugPrint(
        '[albumart] scheduling lookup: artist="${nowPlaying.artist}" title="${nowPlaying.title}"',
      );
    }
    _albumArtDebounce?.cancel();
    // 250ms is enough to swallow the HLS metadata burst (TIT2 + TPE1
    // typically land within 50-100ms of each other) while not adding
    // noticeable latency to the art swap.
    _albumArtDebounce = Timer(const Duration(milliseconds: 250), () {
      _runAlbumArtLookup(nowPlaying);
    });
  }

  bool _looksLikeStationId(String candidate) {
    // Station IDs tend to contain a colon and a space (e.g. "SomaFM: ...")
    // or match the currently-playing station's name.
    if (candidate.contains(': ')) return true;
    final station = state.currentStation;
    if (station != null &&
        candidate.toLowerCase() == station.name.toLowerCase()) {
      return true;
    }
    return false;
  }

  Future<void> _runAlbumArtLookup(NowPlaying nowPlaying) async {
    _lastArtLookupKey = nowPlaying;
    try {
      final art = await _ref.read(albumArtProvider((
        artist: nowPlaying.artist,
        title: nowPlaying.title,
      )).future);
      if (kDebugMode) {
        debugPrint(
          '[albumart] lookup result: source=${art?.source} url=${art?.imageUrl}',
        );
      }
      // Drop the result if the user has since moved on to another track.
      if (state.nowPlaying != nowPlaying) return;
      if (art != null && art.hasImage) {
        state = state.copyWith(albumArtUrl: art.imageUrl);
        await _playerService.setAlbumArt(art.imageUrl);
      }
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[albumart] lookup failed: $e\n$stack');
      }
    }
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
    _syncedAlbumArtSubscription?.cancel();
    _albumArtDebounce?.cancel();
    super.dispose();
  }
}

final radioBrowserRepositoryProvider = Provider<RadioBrowserRepository>((ref) {
  return RadioBrowserRepository();
});

// Volume control provider. State seeded from the persisted Hive setting,
// so the slider position survives app restarts. Every change writes back
// to the same store on the way to the native player.
final volumeProvider = StateNotifierProvider<VolumeController, double>((ref) {
  return VolumeController(ref);
});

class VolumeController extends StateNotifier<double> {
  final Ref _ref;

  VolumeController(Ref ref)
      : _ref = ref,
        super(ref.read(appSettingsRepositoryProvider).volume) {
    // Push the persisted volume down to the native player so stations
    // start at the right level even before the user touches the slider.
    // Best-effort: if the native plugin hasn't attached yet, this
    // invocation is effectively dropped and the user adjusting the slider
    // will re-push via setVolume() below. The iOS/macOS plugin has its
    // own `lastVolume` field that catches up newly-created AVPlayers; the
    // Android plugin mirrors that on controller connect.
    Future.microtask(() async {
      try {
        await _ref.read(audioPlayerServiceProvider).setVolume(state);
      } catch (_) {}
    });
  }

  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    state = clamped;
    await _ref.read(appSettingsRepositoryProvider).setVolume(clamped);
    await _ref.read(audioPlayerServiceProvider).setVolume(clamped);
  }
}
