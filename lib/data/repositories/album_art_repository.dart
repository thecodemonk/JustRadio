import 'package:hive/hive.dart';
import '../models/album_art.dart';

/// Hive-backed cache for `(artist, title) → AlbumArt`. Keyed by a
/// normalized compound key (`lowercased(artist)|lowercased(title)`) so
/// small casing/whitespace differences from different metadata sources
/// don't miss the cache. Practically permanent TTL.
class AlbumArtRepository {
  static const _boxName = 'album_art';

  Box<AlbumArt>? _box;

  Future<void> init() async {
    _box = await Hive.openBox<AlbumArt>(_boxName);
  }

  Box<AlbumArt> get _artBox {
    if (_box == null || !_box!.isOpen) {
      throw StateError('Album art box not initialized. Call init() first.');
    }
    return _box!;
  }

  String _key(String artist, String title) =>
      '${artist.trim().toLowerCase()}|${title.trim().toLowerCase()}';

  AlbumArt? get(String artist, String title) {
    if (artist.isEmpty || title.isEmpty) return null;
    return _artBox.get(_key(artist, title));
  }

  Future<void> put(AlbumArt art) async {
    await _artBox.put(_key(art.artist, art.title), art);
  }

  Future<void> clear() async {
    await _artBox.clear();
  }
}
