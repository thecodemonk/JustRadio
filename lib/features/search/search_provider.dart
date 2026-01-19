import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/radio_station.dart';
import '../../data/repositories/radio_browser_repository.dart';
import '../../providers/audio_player_provider.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider =
    FutureProvider.autoDispose<List<RadioStation>>((ref) async {
  final query = ref.watch(searchQueryProvider);

  if (query.isEmpty) {
    return [];
  }

  // Debounce
  await Future.delayed(const Duration(milliseconds: 300));

  // Check if query has changed during debounce
  if (ref.read(searchQueryProvider) != query) {
    throw Exception('Query changed');
  }

  final repository = ref.read(radioBrowserRepositoryProvider);
  return repository.searchStations(name: query);
});

final countriesProvider = FutureProvider<List<Country>>((ref) async {
  final repository = ref.read(radioBrowserRepositoryProvider);
  return repository.getCountries();
});

final tagsProvider = FutureProvider<List<Tag>>((ref) async {
  final repository = ref.read(radioBrowserRepositoryProvider);
  return repository.getTags(limit: 100);
});

final stationsByCountryProvider =
    FutureProvider.family<List<RadioStation>, String>((ref, countryCode) async {
  final repository = ref.read(radioBrowserRepositoryProvider);
  return repository.getStationsByCountry(countryCode);
});

final stationsByTagProvider =
    FutureProvider.family<List<RadioStation>, String>((ref, tag) async {
  final repository = ref.read(radioBrowserRepositoryProvider);
  return repository.getStationsByTag(tag);
});

// Search filter state
enum SearchFilter { name, country, genre }

final searchFilterProvider = StateProvider<SearchFilter>((ref) => SearchFilter.name);

final selectedCountryProvider = StateProvider<Country?>((ref) => null);
final selectedTagProvider = StateProvider<Tag?>((ref) => null);

// Filtered search results based on selected filter
final filteredSearchResultsProvider =
    FutureProvider.autoDispose<List<RadioStation>>((ref) async {
  final filter = ref.watch(searchFilterProvider);
  final repository = ref.read(radioBrowserRepositoryProvider);

  switch (filter) {
    case SearchFilter.name:
      final query = ref.watch(searchQueryProvider);
      if (query.isEmpty) return [];
      await Future.delayed(const Duration(milliseconds: 300));
      if (ref.read(searchQueryProvider) != query) {
        throw Exception('Query changed');
      }
      return repository.searchStations(name: query);

    case SearchFilter.country:
      final country = ref.watch(selectedCountryProvider);
      if (country == null) return [];
      return repository.getStationsByCountry(country.iso3166);

    case SearchFilter.genre:
      final tag = ref.watch(selectedTagProvider);
      if (tag == null) return [];
      return repository.getStationsByTag(tag.name);
  }
});
