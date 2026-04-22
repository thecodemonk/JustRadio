import 'package:hive/hive.dart';

/// Cached album art lookup result for a (artist, title) pair. Cached
/// indefinitely — track artwork doesn't meaningfully change, and we want
/// offline robustness on flaky cell connections. Invalidate only when the
/// user asks to refresh.
class AlbumArt {
  final String artist;
  final String title;

  /// Largest available image URL, or null if no source returned art.
  final String? imageUrl;

  /// Which source supplied the image: "lastfm" | "itunes" | "none".
  /// Used for attribution credits in settings and as a hint for fallback
  /// ordering on future re-lookups.
  final String source;

  final DateTime fetchedAt;

  AlbumArt({
    required this.artist,
    required this.title,
    required this.imageUrl,
    required this.source,
    required this.fetchedAt,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
}

class AlbumArtAdapter extends TypeAdapter<AlbumArt> {
  @override
  final int typeId = 3;

  @override
  AlbumArt read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AlbumArt(
      artist: fields[0] as String,
      title: fields[1] as String,
      imageUrl: fields[2] as String?,
      source: fields[3] as String,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fields[4] as int),
    );
  }

  @override
  void write(BinaryWriter writer, AlbumArt obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.artist)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.imageUrl)
      ..writeByte(3)
      ..write(obj.source)
      ..writeByte(4)
      ..write(obj.fetchedAt.millisecondsSinceEpoch);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlbumArtAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
