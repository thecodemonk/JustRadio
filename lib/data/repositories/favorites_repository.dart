import 'package:hive/hive.dart';
import '../models/radio_station.dart';

class FavoritesRepository {
  static const _boxName = 'favorites';
  Box<RadioStation>? _box;

  Future<void> init() async {
    _box = await Hive.openBox<RadioStation>(_boxName);
  }

  Box<RadioStation> get _favoritesBox {
    if (_box == null || !_box!.isOpen) {
      throw StateError('Favorites box not initialized. Call init() first.');
    }
    return _box!;
  }

  List<RadioStation> getAll() {
    return _favoritesBox.values.toList();
  }

  bool isFavorite(String stationUuid) {
    return _favoritesBox.containsKey(stationUuid);
  }

  Future<void> add(RadioStation station) async {
    await _favoritesBox.put(station.stationuuid, station);
  }

  Future<void> addAll(Iterable<RadioStation> stations) async {
    final entries = {
      for (final s in stations) s.stationuuid: s,
    };
    if (entries.isEmpty) return;
    await _favoritesBox.putAll(entries);
  }

  Future<void> remove(String stationUuid) async {
    await _favoritesBox.delete(stationUuid);
  }

  Future<void> toggle(RadioStation station) async {
    if (isFavorite(station.stationuuid)) {
      await remove(station.stationuuid);
    } else {
      await add(station);
    }
  }

  Future<void> clear() async {
    await _favoritesBox.clear();
  }

  Stream<BoxEvent> watch() {
    return _favoritesBox.watch();
  }
}
