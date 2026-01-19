import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/radio_station.dart';
import '../player/player_screen.dart';
import 'search_provider.dart';
import 'widgets/station_list_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(searchFilterProvider);
    final searchResults = ref.watch(filteredSearchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Search input
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search radio stations...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              ref.read(searchQueryProvider.notifier).state = '';
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    ref.read(searchQueryProvider.notifier).state = value;
                  },
                ),
                const SizedBox(height: 12),

                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('By Name'),
                        selected: filter == SearchFilter.name,
                        onSelected: (selected) {
                          if (selected) {
                            ref.read(searchFilterProvider.notifier).state =
                                SearchFilter.name;
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('By Country'),
                        selected: filter == SearchFilter.country,
                        onSelected: (selected) {
                          if (selected) {
                            ref.read(searchFilterProvider.notifier).state =
                                SearchFilter.country;
                            _showCountryPicker(context);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('By Genre'),
                        selected: filter == SearchFilter.genre,
                        onSelected: (selected) {
                          if (selected) {
                            ref.read(searchFilterProvider.notifier).state =
                                SearchFilter.genre;
                            _showTagPicker(context);
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // Selected filter indicator
                if (filter == SearchFilter.country)
                  _buildSelectedCountryChip(),
                if (filter == SearchFilter.genre) _buildSelectedTagChip(),
              ],
            ),
          ),

          // Results
          Expanded(
            child: searchResults.when(
              data: (stations) {
                if (stations.isEmpty) {
                  return _buildEmptyState(filter);
                }
                return _buildStationList(stations);
              },
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (error, stack) {
                if (error.toString().contains('Query changed')) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 16),
                      Text('Error: ${error.toString()}'),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(SearchFilter filter) {
    String message;
    switch (filter) {
      case SearchFilter.name:
        message = 'Enter a search term to find stations';
        break;
      case SearchFilter.country:
        message = 'Select a country to browse stations';
        break;
      case SearchFilter.genre:
        message = 'Select a genre to browse stations';
        break;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.radio,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withAlpha(128),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildStationList(List<RadioStation> stations) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(filteredSearchResultsProvider);
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: stations.length,
        itemBuilder: (context, index) {
          final station = stations[index];
          return StationListTile(
            station: station,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => PlayerScreen(station: station),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSelectedCountryChip() {
    final country = ref.watch(selectedCountryProvider);
    if (country == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Chip(
        label: Text(country.name),
        onDeleted: () {
          ref.read(selectedCountryProvider.notifier).state = null;
        },
      ),
    );
  }

  Widget _buildSelectedTagChip() {
    final tag = ref.watch(selectedTagProvider);
    if (tag == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Chip(
        label: Text(tag.name),
        onDeleted: () {
          ref.read(selectedTagProvider.notifier).state = null;
        },
      ),
    );
  }

  void _showCountryPicker(BuildContext context) {
    final countries = ref.read(countriesProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Country',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: countries.when(
                data: (countryList) => ListView.builder(
                  controller: scrollController,
                  itemCount: countryList.length,
                  itemBuilder: (context, index) {
                    final country = countryList[index];
                    return ListTile(
                      title: Text(country.name),
                      subtitle: Text('${country.stationCount} stations'),
                      onTap: () {
                        ref.read(selectedCountryProvider.notifier).state =
                            country;
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTagPicker(BuildContext context) {
    final tags = ref.read(tagsProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Genre',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: tags.when(
                data: (tagList) => ListView.builder(
                  controller: scrollController,
                  itemCount: tagList.length,
                  itemBuilder: (context, index) {
                    final tag = tagList[index];
                    return ListTile(
                      title: Text(tag.name),
                      subtitle: Text('${tag.stationCount} stations'),
                      onTap: () {
                        ref.read(selectedTagProvider.notifier).state = tag;
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
