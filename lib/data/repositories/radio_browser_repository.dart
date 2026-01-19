import 'package:dio/dio.dart';
import '../models/radio_station.dart';
import '../../core/constants/api_constants.dart';

class RadioBrowserRepository {
  final Dio _dio;
  int _currentServerIndex = 0;

  RadioBrowserRepository({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: ApiConstants.radioBrowserBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {
                'User-Agent': 'JustRadio/1.0',
              },
            ));

  Future<T> _executeWithFallback<T>(
    Future<T> Function(String baseUrl) request,
  ) async {
    Exception? lastException;

    for (int i = 0; i < ApiConstants.radioBrowserServers.length; i++) {
      try {
        final serverIndex =
            (_currentServerIndex + i) % ApiConstants.radioBrowserServers.length;
        final baseUrl = ApiConstants.radioBrowserServers[serverIndex];
        final result = await request(baseUrl);
        _currentServerIndex = serverIndex;
        return result;
      } catch (e) {
        lastException = e as Exception;
        continue;
      }
    }

    throw lastException ?? Exception('All servers failed');
  }

  Future<List<RadioStation>> searchStations({
    String? name,
    String? country,
    String? countryCode,
    String? tag,
    String? language,
    int limit = ApiConstants.defaultSearchLimit,
    int offset = 0,
    String order = 'clickcount',
    bool reverse = true,
  }) async {
    return _executeWithFallback((baseUrl) async {
      final response = await _dio.get(
        '$baseUrl${ApiConstants.stationsSearch}',
        queryParameters: {
          if (name != null && name.isNotEmpty) 'name': name,
          if (country != null && country.isNotEmpty) 'country': country,
          if (countryCode != null && countryCode.isNotEmpty)
            'countrycode': countryCode,
          if (tag != null && tag.isNotEmpty) 'tag': tag,
          if (language != null && language.isNotEmpty) 'language': language,
          'limit': limit,
          'offset': offset,
          'order': order,
          'reverse': reverse,
          'hidebroken': true,
        },
      );

      return _parseStations(response.data);
    });
  }

  Future<List<RadioStation>> getTopStations({
    int limit = ApiConstants.defaultTopLimit,
  }) async {
    return _executeWithFallback((baseUrl) async {
      final response = await _dio.get(
        '$baseUrl${ApiConstants.stationsTopClick}',
        queryParameters: {
          'limit': limit,
          'hidebroken': true,
        },
      );

      return _parseStations(response.data);
    });
  }

  Future<List<RadioStation>> getTrendingStations({
    int limit = ApiConstants.defaultTopLimit,
  }) async {
    return _executeWithFallback((baseUrl) async {
      final response = await _dio.get(
        '$baseUrl${ApiConstants.stationsTopVote}',
        queryParameters: {
          'limit': limit,
          'hidebroken': true,
        },
      );

      return _parseStations(response.data);
    });
  }

  Future<List<RadioStation>> getStationsByCountry(
    String countryCode, {
    int limit = ApiConstants.defaultSearchLimit,
  }) async {
    return _executeWithFallback((baseUrl) async {
      final response = await _dio.get(
        '$baseUrl${ApiConstants.stationsByCountry}/$countryCode',
        queryParameters: {
          'limit': limit,
          'order': 'clickcount',
          'reverse': true,
          'hidebroken': true,
        },
      );

      return _parseStations(response.data);
    });
  }

  Future<List<RadioStation>> getStationsByTag(
    String tag, {
    int limit = ApiConstants.defaultSearchLimit,
  }) async {
    return _executeWithFallback((baseUrl) async {
      final response = await _dio.get(
        '$baseUrl${ApiConstants.stationsByTag}/$tag',
        queryParameters: {
          'limit': limit,
          'order': 'clickcount',
          'reverse': true,
          'hidebroken': true,
        },
      );

      return _parseStations(response.data);
    });
  }

  Future<List<Country>> getCountries() async {
    return _executeWithFallback((baseUrl) async {
      final response = await _dio.get(
        '$baseUrl${ApiConstants.countries}',
        queryParameters: {
          'order': 'stationcount',
          'reverse': true,
        },
      );

      final List<dynamic> data = response.data;
      return data.map((json) => Country.fromJson(json)).toList();
    });
  }

  Future<List<Tag>> getTags({int limit = 100}) async {
    return _executeWithFallback((baseUrl) async {
      final response = await _dio.get(
        '$baseUrl${ApiConstants.tags}',
        queryParameters: {
          'order': 'stationcount',
          'reverse': true,
          'limit': limit,
        },
      );

      final List<dynamic> data = response.data;
      return data.map((json) => Tag.fromJson(json)).toList();
    });
  }

  Future<void> registerClick(String stationUuid) async {
    try {
      await _executeWithFallback((baseUrl) async {
        await _dio.get('$baseUrl${ApiConstants.stationClick}/$stationUuid');
      });
    } catch (_) {
      // Silently fail - click tracking is not critical
    }
  }

  List<RadioStation> _parseStations(dynamic data) {
    if (data is! List) return [];
    return data
        .map((json) => RadioStation.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

class Country {
  final String name;
  final String iso3166;
  final int stationCount;

  Country({
    required this.name,
    required this.iso3166,
    required this.stationCount,
  });

  factory Country.fromJson(Map<String, dynamic> json) {
    return Country(
      name: json['name'] ?? '',
      iso3166: json['iso_3166_1'] ?? '',
      stationCount: json['stationcount'] ?? 0,
    );
  }
}

class Tag {
  final String name;
  final int stationCount;

  Tag({
    required this.name,
    required this.stationCount,
  });

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      name: json['name'] ?? '',
      stationCount: json['stationcount'] ?? 0,
    );
  }
}
