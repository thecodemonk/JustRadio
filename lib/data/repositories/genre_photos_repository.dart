import 'package:hive/hive.dart';
import '../models/genre_photo.dart';

class GenrePhotosRepository {
  static const _boxName = 'genre_photos';

  Box<GenrePhoto>? _box;

  Future<void> init() async {
    _box = await Hive.openBox<GenrePhoto>(_boxName);
  }

  Box<GenrePhoto> get _photosBox {
    if (_box == null || !_box!.isOpen) {
      throw StateError(
          'Genre photos box not initialized. Call init() first.');
    }
    return _box!;
  }

  String _key(String genre) => genre.toLowerCase().trim();

  GenrePhoto? get(String genre) => _photosBox.get(_key(genre));

  Future<void> put(GenrePhoto photo) async {
    await _photosBox.put(_key(photo.genre), photo);
  }

  List<GenrePhoto> getAll() {
    final all = _photosBox.values.toList()
      ..sort((a, b) => b.fetchedAt.compareTo(a.fetchedAt));
    return all;
  }

  Future<void> clear() async {
    await _photosBox.clear();
  }
}
