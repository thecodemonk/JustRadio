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

  /// One-shot migration: the album-art chain dropped Last.fm as a
  /// provider. Old cached entries attributed to `lastfm` may carry URLs
  /// that Last.fm has since deprecated. Remove them so the next lookup
  /// re-resolves via iTunes/Deezer/MusicBrainz.
  /// Returns the number of entries purged.
  Future<int> purgeLastfmEntries() async {
    return _purgeBySource({'lastfm'});
  }

  /// One-shot migration: early versions of the MusicBrainz+CAA lookup
  /// would cache whatever release CAA had cover art for, including
  /// compilation albums whose covers have nothing to do with the track.
  /// Clear MB-sourced entries so they re-resolve under the new
  /// compilation-skipping logic.
  Future<int> purgeMusicbrainzEntries() async {
    return _purgeBySource({'musicbrainz'});
  }

  /// One-shot migration: wipes every cached entry. Used after a chain-
  /// level logic change (e.g. iTunes compilation filter, artist/title
  /// swap acceptance) so all tracks re-resolve under the new matcher
  /// on next play.
  Future<int> purgeAll() async {
    final count = _artBox.length;
    await _artBox.clear();
    return count;
  }

  Future<int> _purgeBySource(Set<String> sources) async {
    final toDelete = <String>[];
    for (final key in _artBox.keys) {
      final art = _artBox.get(key);
      if (art != null && sources.contains(art.source)) {
        toDelete.add(key.toString());
      }
    }
    await _artBox.deleteAll(toDelete);
    return toDelete.length;
  }
}
