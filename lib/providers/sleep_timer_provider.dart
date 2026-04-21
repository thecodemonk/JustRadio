import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'audio_player_provider.dart';

class SleepTimerState {
  final int? durationMinutes;
  final int remainingSeconds;

  const SleepTimerState({this.durationMinutes, this.remainingSeconds = 0});

  bool get isActive => durationMinutes != null;

  String get formattedRemaining {
    final m = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class SleepTimerNotifier extends StateNotifier<SleepTimerState> {
  final Ref _ref;
  Timer? _timer;

  SleepTimerNotifier(this._ref) : super(const SleepTimerState());

  void start(int minutes) {
    _timer?.cancel();
    state = SleepTimerState(
      durationMinutes: minutes,
      remainingSeconds: minutes * 60,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = state.remainingSeconds - 1;
      if (next <= 0) {
        _ref.read(radioPlayerControllerProvider.notifier).stop();
        cancel();
      } else {
        state = SleepTimerState(
          durationMinutes: state.durationMinutes,
          remainingSeconds: next,
        );
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    state = const SleepTimerState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerState>((ref) {
  return SleepTimerNotifier(ref);
});
