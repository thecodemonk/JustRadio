import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/genre_photo.dart';
import '../data/repositories/app_settings_repository.dart';
import '../data/repositories/genre_photos_repository.dart';
import '../data/services/unsplash_service.dart';

final appSettingsRepositoryProvider =
    Provider<AppSettingsRepository>((ref) => AppSettingsRepository());

final genrePhotosRepositoryProvider =
    Provider<GenrePhotosRepository>((ref) => GenrePhotosRepository());

final unsplashServiceProvider = Provider<UnsplashService>((ref) {
  final service = UnsplashService();
  final key = ref.watch(unsplashKeyProvider);
  service.setAccessKey(key);
  return service;
});

final unsplashKeyProvider =
    StateNotifierProvider<UnsplashKeyNotifier, String?>((ref) {
  final repo = ref.watch(appSettingsRepositoryProvider);
  return UnsplashKeyNotifier(repo);
});

class UnsplashKeyNotifier extends StateNotifier<String?> {
  final AppSettingsRepository _repo;
  UnsplashKeyNotifier(this._repo) : super(_repo.unsplashAccessKey);

  Future<void> save(String key) async {
    await _repo.setUnsplashAccessKey(key);
    state = _repo.unsplashAccessKey;
  }

  Future<void> clear() async {
    await _repo.setUnsplashAccessKey(null);
    state = null;
  }
}

/// Resolves a backdrop photo for a given genre tag.
///
/// Flow:
///  1. Return cached photo from Hive if present
///  2. If user has no Unsplash key configured → return null (caller shows gradient)
///  3. Query Unsplash via throttled service, cache + fire-and-forget
///     the `/download` tracking endpoint on success
final genrePhotoProvider =
    FutureProvider.family<GenrePhoto?, String>((ref, genre) async {
  final repo = ref.watch(genrePhotosRepositoryProvider);
  final cached = repo.get(genre);
  if (cached != null) return cached;

  final service = ref.watch(unsplashServiceProvider);
  if (!service.isConfigured) return null;

  final fetched = await service.searchPhoto(genre);
  if (fetched == null) return null;

  await repo.put(fetched);
  // Best-effort tracking ping, per Unsplash TOS.
  if (fetched.downloadLocation.isNotEmpty) {
    service.registerDownload(fetched.downloadLocation);
  }
  return fetched;
});

/// All cached photos — drives the "Photo Credits" screen.
final cachedGenrePhotosProvider = Provider<List<GenrePhoto>>((ref) {
  // Re-read when key changes (user cleared / re-added), though the main
  // driver is that tiles populate lazily.
  ref.watch(unsplashKeyProvider);
  return ref.watch(genrePhotosRepositoryProvider).getAll();
});
