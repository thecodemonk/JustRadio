import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/radio_station.dart';
import '../data/repositories/favorites_repository.dart';

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  return FavoritesRepository();
});

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<RadioStation>>((ref) {
  final repository = ref.watch(favoritesRepositoryProvider);
  return FavoritesNotifier(repository);
});

class FavoritesNotifier extends StateNotifier<List<RadioStation>> {
  final FavoritesRepository _repository;

  FavoritesNotifier(this._repository) : super([]) {
    _loadFavorites();
  }

  void _loadFavorites() {
    state = _repository.getAll();
  }

  bool isFavorite(String stationUuid) {
    return _repository.isFavorite(stationUuid);
  }

  Future<void> toggle(RadioStation station) async {
    await _repository.toggle(station);
    _loadFavorites();
  }

  Future<void> add(RadioStation station) async {
    await _repository.add(station);
    _loadFavorites();
  }

  Future<void> remove(String stationUuid) async {
    await _repository.remove(stationUuid);
    _loadFavorites();
  }

  Future<void> clear() async {
    await _repository.clear();
    _loadFavorites();
  }
}

// Helper provider to check if a specific station is favorite
final isFavoriteProvider = Provider.family<bool, String>((ref, stationUuid) {
  final favorites = ref.watch(favoritesProvider);
  return favorites.any((s) => s.stationuuid == stationUuid);
});
