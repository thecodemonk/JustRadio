import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/now_playing.dart';
import '../data/services/native_audio_player_service.dart';
import 'audio_player_provider.dart';
import 'lastfm_provider.dart';

/// Per-track Last.fm "love" state for whatever song is currently on-air.
///
/// PlayerScreen and DesktopShell both render a heart button against this
/// provider. Native code (Android Auto's custom button, CarPlay's
/// likeCommand) toggles the same state via a `lovedStateChanged` event.
class LovedTrackState {
  final String artist;
  final String title;
  final bool isLoved;
  final bool isBusy;

  const LovedTrackState({
    required this.artist,
    required this.title,
    required this.isLoved,
    required this.isBusy,
  });

  const LovedTrackState.empty()
      : artist = '',
        title = '',
        isLoved = false,
        isBusy = false;

  bool get hasTrack => artist.isNotEmpty && title.isNotEmpty;

  LovedTrackState copyWith({
    String? artist,
    String? title,
    bool? isLoved,
    bool? isBusy,
  }) =>
      LovedTrackState(
        artist: artist ?? this.artist,
        title: title ?? this.title,
        isLoved: isLoved ?? this.isLoved,
        isBusy: isBusy ?? this.isBusy,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LovedTrackState &&
          artist == other.artist &&
          title == other.title &&
          isLoved == other.isLoved &&
          isBusy == other.isBusy;

  @override
  int get hashCode => Object.hash(artist, title, isLoved, isBusy);
}

final lovedTrackProvider =
    StateNotifierProvider<LovedTrackNotifier, LovedTrackState>((ref) {
  final notifier = LovedTrackNotifier(ref);

  ref.listen<RadioPlayerState>(
    radioPlayerControllerProvider,
    (prev, next) {
      if (prev?.nowPlaying != next.nowPlaying) {
        notifier.onTrackChanged(next.nowPlaying);
      }
    },
    fireImmediately: true,
  );

  // When the user links or unlinks Last.fm, re-resolve loved state (or clear
  // it). Without this, toggling auth leaves the heart in a stale state.
  ref.listen(
    lastfmStateProvider,
    (prev, next) {
      if (prev?.isAuthenticated == next.isAuthenticated) return;
      final current = ref.read(radioPlayerControllerProvider).nowPlaying;
      notifier.onAuthChanged(current);
    },
  );

  // Native surfaces (Android Auto, CarPlay) can toggle the state
  // independently. Mirror those events into our state.
  final sub = ref
      .read(audioPlayerServiceProvider)
      .lovedStateStream
      .listen((e) => notifier.applyNativeLovedState(
            artist: e.artist,
            title: e.title,
            loved: e.loved,
          ));
  ref.onDispose(sub.cancel);

  return notifier;
});

class LovedTrackNotifier extends StateNotifier<LovedTrackState> {
  final Ref _ref;
  // Stamps the most recent track we've seen — used to ignore late responses
  // when the user has already moved on to a different song.
  String _currentKey = '';

  LovedTrackNotifier(this._ref) : super(const LovedTrackState.empty());

  void onTrackChanged(NowPlaying nowPlaying) {
    if (nowPlaying.artist.isEmpty || nowPlaying.title.isEmpty) {
      _currentKey = '';
      state = const LovedTrackState.empty();
      return;
    }

    final key = '${nowPlaying.artist}|${nowPlaying.title}';
    if (key == _currentKey) return;
    _currentKey = key;

    state = LovedTrackState(
      artist: nowPlaying.artist,
      title: nowPlaying.title,
      isLoved: false,
      isBusy: false,
    );

    _resolveLovedState(nowPlaying.artist, nowPlaying.title, key);
  }

  void onAuthChanged(NowPlaying nowPlaying) {
    // Force a re-resolve even if the track key hasn't changed.
    _currentKey = '';
    onTrackChanged(nowPlaying);
  }

  Future<void> _resolveLovedState(
      String artist, String title, String key) async {
    final service = _ref.read(lastfmAuthServiceProvider);
    final username = _ref.read(lastfmStateProvider).username;
    if (!service.isAuthenticated || username == null) return;

    final loved = await service.repository.isTrackLoved(
      artist: artist,
      track: title,
      username: username,
    );
    if (_currentKey != key) return;
    state = state.copyWith(isLoved: loved);
  }

  Future<void> toggleLove() async {
    if (state.isBusy || !state.hasTrack) return;
    final service = _ref.read(lastfmAuthServiceProvider);
    if (!service.isAuthenticated) return;

    final artist = state.artist;
    final title = state.title;
    final key = '$artist|$title';
    final wantLoved = !state.isLoved;

    state = state.copyWith(isLoved: wantLoved, isBusy: true);

    final success = wantLoved
        ? await service.repository.loveTrack(artist: artist, track: title)
        : await service.repository.unloveTrack(artist: artist, track: title);

    if (_currentKey != key) return;

    if (!success) {
      state = state.copyWith(isLoved: !wantLoved, isBusy: false);
      return;
    }

    state = state.copyWith(isBusy: false);

    // Mirror to native so the AA/CarPlay button matches without a
    // redundant round-trip. Fire-and-forget — the native cache is a
    // best-effort mirror of what Dart already knows.
    final audio = _ref.read(audioPlayerServiceProvider);
    if (audio is NativeAudioPlayerService) {
      audio.setLovedState(
          artist: artist, title: title, loved: wantLoved);
    }
  }

  /// Called when the native side (Android Auto custom button, CarPlay
  /// likeCommand) changes the loved state. Applies only if the event
  /// matches the track we currently think is on-air.
  void applyNativeLovedState({
    required String artist,
    required String title,
    required bool loved,
  }) {
    final key = '$artist|$title';
    if (key != _currentKey) return;
    state = state.copyWith(isLoved: loved, isBusy: false);
  }
}
