import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/radio_station.dart';
import '../data/models/recent_play.dart';
import '../data/repositories/recent_plays_repository.dart';

final recentPlaysRepositoryProvider = Provider<RecentPlaysRepository>((ref) {
  return RecentPlaysRepository();
});

final recentPlaysProvider =
    StateNotifierProvider<RecentPlaysNotifier, List<RecentPlay>>((ref) {
  final repo = ref.watch(recentPlaysRepositoryProvider);
  return RecentPlaysNotifier(repo);
});

class RecentPlaysNotifier extends StateNotifier<List<RecentPlay>> {
  final RecentPlaysRepository _repo;

  RecentPlaysNotifier(this._repo) : super([]) {
    _load();
  }

  void _load() {
    state = _repo.getAll();
  }

  Future<void> record(RadioStation station) async {
    await _repo.add(station);
    _load();
  }

  Future<void> clear() async {
    await _repo.clear();
    _load();
  }
}
