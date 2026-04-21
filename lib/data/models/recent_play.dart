import 'package:hive/hive.dart';
import 'radio_station.dart';

class RecentPlay {
  final RadioStation station;
  final DateTime playedAt;

  RecentPlay({required this.station, required this.playedAt});
}

class RecentPlayAdapter extends TypeAdapter<RecentPlay> {
  @override
  final int typeId = 1;

  @override
  RecentPlay read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RecentPlay(
      station: fields[0] as RadioStation,
      playedAt:
          DateTime.fromMillisecondsSinceEpoch(fields[1] as int),
    );
  }

  @override
  void write(BinaryWriter writer, RecentPlay obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.station)
      ..writeByte(1)
      ..write(obj.playedAt.millisecondsSinceEpoch);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecentPlayAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
