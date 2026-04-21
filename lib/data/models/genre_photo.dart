import 'package:hive/hive.dart';

class GenrePhoto {
  final String genre;
  final String imageUrl;
  final String photoPageUrl;
  final String photographerName;
  final String photographerUrl;
  final String downloadLocation;
  final DateTime fetchedAt;

  GenrePhoto({
    required this.genre,
    required this.imageUrl,
    required this.photoPageUrl,
    required this.photographerName,
    required this.photographerUrl,
    required this.downloadLocation,
    required this.fetchedAt,
  });
}

class GenrePhotoAdapter extends TypeAdapter<GenrePhoto> {
  @override
  final int typeId = 2;

  @override
  GenrePhoto read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GenrePhoto(
      genre: fields[0] as String,
      imageUrl: fields[1] as String,
      photoPageUrl: fields[2] as String,
      photographerName: fields[3] as String,
      photographerUrl: fields[4] as String,
      downloadLocation: fields[5] as String,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fields[6] as int),
    );
  }

  @override
  void write(BinaryWriter writer, GenrePhoto obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.genre)
      ..writeByte(1)
      ..write(obj.imageUrl)
      ..writeByte(2)
      ..write(obj.photoPageUrl)
      ..writeByte(3)
      ..write(obj.photographerName)
      ..writeByte(4)
      ..write(obj.photographerUrl)
      ..writeByte(5)
      ..write(obj.downloadLocation)
      ..writeByte(6)
      ..write(obj.fetchedAt.millisecondsSinceEpoch);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenrePhotoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
