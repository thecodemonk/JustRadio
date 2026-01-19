import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/lastfm_auth_service.dart';
import '../data/repositories/lastfm_repository.dart';

final lastfmAuthServiceProvider = Provider<LastfmAuthService>((ref) {
  return LastfmAuthService();
});

final lastfmStateProvider =
    StateNotifierProvider<LastfmStateNotifier, LastfmState>((ref) {
  final service = ref.watch(lastfmAuthServiceProvider);
  return LastfmStateNotifier(service);
});

class LastfmState {
  final bool isAuthenticated;
  final bool hasPendingToken;
  final String? username;
  final UserInfo? userInfo;
  final bool isLoading;
  final String? error;

  LastfmState({
    this.isAuthenticated = false,
    this.hasPendingToken = false,
    this.username,
    this.userInfo,
    this.isLoading = false,
    this.error,
  });

  LastfmState copyWith({
    bool? isAuthenticated,
    bool? hasPendingToken,
    String? username,
    UserInfo? userInfo,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearUserInfo = false,
  }) {
    return LastfmState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      hasPendingToken: hasPendingToken ?? this.hasPendingToken,
      username: username ?? this.username,
      userInfo: clearUserInfo ? null : (userInfo ?? this.userInfo),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class LastfmStateNotifier extends StateNotifier<LastfmState> {
  final LastfmAuthService _service;

  LastfmStateNotifier(this._service) : super(LastfmState()) {
    _refreshState();
  }

  void _refreshState() {
    state = state.copyWith(
      isAuthenticated: _service.isAuthenticated,
      hasPendingToken: _service.hasPendingToken,
      username: _service.username,
    );
  }

  Future<void> startAuth() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await _service.startAuthFlow();
      _refreshState();
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to start authentication: ${e.toString()}',
      );
    }

    state = state.copyWith(isLoading: false);
  }

  Future<bool> completeAuth() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final success = await _service.completeAuth();
      if (success) {
        _refreshState();
        await fetchUserInfo();
      } else {
        state = state.copyWith(
          error: 'Failed to authenticate with Last.fm. Make sure you authorized the app in the browser.',
        );
      }
      state = state.copyWith(isLoading: false);
      return success;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Authentication error: ${e.toString()}',
      );
      return false;
    }
  }

  Future<void> cancelAuth() async {
    await _service.cancelAuth();
    _refreshState();
  }

  Future<void> fetchUserInfo() async {
    if (!_service.isAuthenticated) return;

    try {
      final userInfo = await _service.getUserInfo();
      state = state.copyWith(userInfo: userInfo);
    } catch (e) {
      // Silently fail - user info is not critical
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);

    try {
      await _service.logout();
      state = LastfmState(isAuthenticated: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to logout: ${e.toString()}',
      );
    }
  }
}
