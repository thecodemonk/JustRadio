import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/album_art.dart';
import '../data/repositories/album_art_repository.dart';
import '../data/services/album_art_service.dart';

final albumArtRepositoryProvider = Provider<AlbumArtRepository>((ref) {
  return AlbumArtRepository();
});

final albumArtServiceProvider = Provider<AlbumArtService>((ref) {
  return AlbumArtService();
});

/// Family provider keyed by `(artist, title)` tuple (encoded as a record).
/// Repo-first on cache HIT with an image; on cache miss (or cached empty
/// result), fires a fresh lookup. Mirrors `genrePhotoProvider`.
///
/// We intentionally DON'T cache misses — if Last.fm / iTunes coverage was
/// missing when we first asked, a retry later is cheap and may succeed
/// (new track metadata syncs, artist corrections, etc.).
final albumArtProvider = FutureProvider.family
    .autoDispose<AlbumArt?, ({String artist, String title})>(
  (ref, key) async {
    final artist = key.artist.trim();
    final title = key.title.trim();
    if (artist.isEmpty || title.isEmpty) return null;

    final repo = ref.read(albumArtRepositoryProvider);
    final cached = repo.get(artist, title);
    if (cached != null && cached.hasImage) return cached;

    final service = ref.read(albumArtServiceProvider);
    final art = await service.lookup(artist: artist, title: title);
    // Only persist positive hits — see doc above.
    if (art.hasImage) {
      await repo.put(art);
    }
    return art;
  },
);
