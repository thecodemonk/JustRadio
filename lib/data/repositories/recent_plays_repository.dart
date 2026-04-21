import 'package:hive/hive.dart';
import '../models/radio_station.dart';
import '../models/recent_play.dart';

class RecentPlaysRepository {
  static const _boxName = 'recent_plays';
  static const int maxEntries = 30;

  Box<RecentPlay>? _box;

  Future<void> init() async {
    _box = await Hive.openBox<RecentPlay>(_boxName);
  }

  Box<RecentPlay> get _recentBox {
    if (_box == null || !_box!.isOpen) {
      throw StateError(
          'Recent plays box not initialized. Call init() first.');
    }
    return _box!;
  }

  List<RecentPlay> getAll() {
    final entries = _recentBox.values.toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return entries;
  }

  Future<void> add(RadioStation station) async {
    final existing = _recentBox.get(station.stationuuid);
    if (existing != null) {
      await _recentBox.delete(station.stationuuid);
    }
    await _recentBox.put(
      station.stationuuid,
      RecentPlay(station: station, playedAt: DateTime.now()),
    );
    await _trim();
  }

  Future<void> _trim() async {
    if (_recentBox.length <= maxEntries) return;
    final all = _recentBox.values.toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final toRemove = all.skip(maxEntries);
    for (final rp in toRemove) {
      await _recentBox.delete(rp.station.stationuuid);
    }
  }

  Future<void> clear() async {
    await _recentBox.clear();
  }
}
