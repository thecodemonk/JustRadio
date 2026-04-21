import 'package:hive/hive.dart';

class AppSettingsRepository {
  static const _boxName = 'app_settings';
  static const _unsplashKey = 'unsplash_access_key';

  Box? _box;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  Box get _settingsBox {
    if (_box == null || !_box!.isOpen) {
      throw StateError(
          'App settings box not initialized. Call init() first.');
    }
    return _box!;
  }

  String? get unsplashAccessKey {
    final v = _settingsBox.get(_unsplashKey);
    if (v is! String || v.isEmpty) return null;
    return v;
  }

  Future<void> setUnsplashAccessKey(String? key) async {
    if (key == null || key.trim().isEmpty) {
      await _settingsBox.delete(_unsplashKey);
    } else {
      await _settingsBox.put(_unsplashKey, key.trim());
    }
  }
}
