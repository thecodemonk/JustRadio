// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radio_station.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RadioStationAdapter extends TypeAdapter<RadioStation> {
  @override
  final int typeId = 0;

  @override
  RadioStation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RadioStation(
      stationuuid: fields[0] as String,
      name: fields[1] as String,
      url: fields[2] as String,
      urlResolved: fields[3] as String,
      homepage: fields[4] as String,
      favicon: fields[5] as String,
      country: fields[6] as String,
      countryCode: fields[7] as String,
      state: fields[8] as String,
      language: fields[9] as String,
      tags: fields[10] as String,
      votes: fields[11] as int,
      clickcount: fields[12] as int,
      bitrate: fields[13] as int,
      codec: fields[14] as String,
    );
  }

  @override
  void write(BinaryWriter writer, RadioStation obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.stationuuid)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.url)
      ..writeByte(3)
      ..write(obj.urlResolved)
      ..writeByte(4)
      ..write(obj.homepage)
      ..writeByte(5)
      ..write(obj.favicon)
      ..writeByte(6)
      ..write(obj.country)
      ..writeByte(7)
      ..write(obj.countryCode)
      ..writeByte(8)
      ..write(obj.state)
      ..writeByte(9)
      ..write(obj.language)
      ..writeByte(10)
      ..write(obj.tags)
      ..writeByte(11)
      ..write(obj.votes)
      ..writeByte(12)
      ..write(obj.clickcount)
      ..writeByte(13)
      ..write(obj.bitrate)
      ..writeByte(14)
      ..write(obj.codec);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RadioStationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
