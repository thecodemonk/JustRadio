import 'package:hive/hive.dart';

part 'radio_station.g.dart';

@HiveType(typeId: 0)
class RadioStation extends HiveObject {
  @HiveField(0)
  final String stationuuid;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String url;

  @HiveField(3)
  final String urlResolved;

  @HiveField(4)
  final String homepage;

  @HiveField(5)
  final String favicon;

  @HiveField(6)
  final String country;

  @HiveField(7)
  final String countryCode;

  @HiveField(8)
  final String state;

  @HiveField(9)
  final String language;

  @HiveField(10)
  final String tags;

  @HiveField(11)
  final int votes;

  @HiveField(12)
  final int clickcount;

  @HiveField(13)
  final int bitrate;

  @HiveField(14)
  final String codec;

  RadioStation({
    required this.stationuuid,
    required this.name,
    required this.url,
    this.urlResolved = '',
    this.homepage = '',
    this.favicon = '',
    this.country = '',
    this.countryCode = '',
    this.state = '',
    this.language = '',
    this.tags = '',
    this.votes = 0,
    this.clickcount = 0,
    this.bitrate = 0,
    this.codec = '',
  });

  factory RadioStation.fromJson(Map<String, dynamic> json) {
    return RadioStation(
      stationuuid: json['stationuuid'] ?? '',
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      urlResolved: json['url_resolved'] ?? '',
      homepage: json['homepage'] ?? '',
      favicon: json['favicon'] ?? '',
      country: json['country'] ?? '',
      countryCode: json['countrycode'] ?? '',
      state: json['state'] ?? '',
      language: json['language'] ?? '',
      tags: json['tags'] ?? '',
      votes: json['votes'] ?? 0,
      clickcount: json['clickcount'] ?? 0,
      bitrate: json['bitrate'] ?? 0,
      codec: json['codec'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stationuuid': stationuuid,
      'name': name,
      'url': url,
      'url_resolved': urlResolved,
      'homepage': homepage,
      'favicon': favicon,
      'country': country,
      'countrycode': countryCode,
      'state': state,
      'language': language,
      'tags': tags,
      'votes': votes,
      'clickcount': clickcount,
      'bitrate': bitrate,
      'codec': codec,
    };
  }

  String get streamUrl => urlResolved.isNotEmpty ? urlResolved : url;

  List<String> get tagList =>
      tags.isNotEmpty ? tags.split(',').map((t) => t.trim()).toList() : [];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RadioStation &&
          runtimeType == other.runtimeType &&
          stationuuid == other.stationuuid;

  @override
  int get hashCode => stationuuid.hashCode;
}
