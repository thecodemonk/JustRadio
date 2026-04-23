import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/radio_station.dart';
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
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DISCOVER',
                      style: AppTypography.label(10, letterSpacing: 2)),
                  const SizedBox(height: 6),
                  Text('Search', style: AppTypography.display(38)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                style: AppTypography.body(14, color: AppColors.onBg),
                decoration: InputDecoration(
                  hintText: 'Search radio stations…',
                  prefixIcon: Icon(Icons.search,
                      size: 18, color: AppColors.onBgMuted(0.5)),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear,
                              size: 18,
                              color: AppColors.onBgMuted(0.5)),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(searchQueryProvider.notifier).state = '';
                          },
                        )
                      : null,
                ),
                onChanged: (value) {
                  ref.read(searchQueryProvider.notifier).state = value;
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 36,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterPill(
                    label: 'By Name',
                    selected: filter == SearchFilter.name,
                    onTap: () => ref.read(searchFilterProvider.notifier).state =
                        SearchFilter.name,
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: 'By Country',
                    selected: filter == SearchFilter.country,
                    onTap: () {
                      ref.read(searchFilterProvider.notifier).state =
                          SearchFilter.country;
                      _showCountryPicker(context);
                    },
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: 'By Genre',
                    selected: filter == SearchFilter.genre,
                    onTap: () {
                      ref.read(searchFilterProvider.notifier).state =
                          SearchFilter.genre;
                      _showTagPicker(context);
                    },
                  ),
                ],
              ),
            ),
            if (filter == SearchFilter.country) _buildSelectedCountryChip(),
            if (filter == SearchFilter.genre) _buildSelectedTagChip(),
            const SizedBox(height: 10),
            Expanded(
              child: searchResults.when(
                data: (stations) {
                  if (stations.isEmpty) return _buildEmptyState(filter);
                  return _buildStationList(stations);
                },
                loading: () => const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.accent),
                    ),
                  ),
                ),
                error: (error, stack) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline,
                              size: 40,
                              color: AppColors.onBgMuted(0.6)),
                          const SizedBox(height: 12),
                          Text(
                            error.toString(),
                            style: AppTypography.body(12,
                                color: AppColors.onBgMuted(0.55)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(SearchFilter filter) {
    final message = switch (filter) {
      SearchFilter.name => 'Enter a search term to find stations',
      SearchFilter.country => 'Select a country to browse stations',
      SearchFilter.genre => 'Select a genre to browse stations',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.radio_outlined,
              size: 56, color: AppColors.accentGlow(0.5)),
          const SizedBox(height: 14),
          Text(message,
              style:
                  AppTypography.body(14, color: AppColors.onBgMuted(0.6))),
        ],
      ),
    );
  }

  Widget _buildStationList(List<RadioStation> stations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: Text(
            '${stations.length} result${stations.length == 1 ? '' : 's'}',
            style: AppTypography.label(10, letterSpacing: 1.8),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.bgElevated,
            onRefresh: () async =>
                ref.invalidate(filteredSearchResultsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
              itemCount: stations.length,
              itemBuilder: (context, index) {
                final station = stations[index];
                return StationListTile(
                  station: station,
                  onTap: () => playStationFromList(
                    ref: ref,
                    context: context,
                    station: station,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedCountryChip() {
    final country = ref.watch(selectedCountryProvider);
    if (country == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          label: Text(country.name),
          onDeleted: () =>
              ref.read(selectedCountryProvider.notifier).state = null,
          deleteIcon: Icon(Icons.close,
              size: 14, color: AppColors.onBgMuted(0.7)),
        ),
      ),
    );
  }

  Widget _buildSelectedTagChip() {
    final tag = ref.watch(selectedTagProvider);
    if (tag == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          label: Text(tag.name),
          onDeleted: () =>
              ref.read(selectedTagProvider.notifier).state = null,
          deleteIcon: Icon(Icons.close,
              size: 14, color: AppColors.onBgMuted(0.7)),
        ),
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
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Select Country',
                    style: AppTypography.display(24)),
              ),
            ),
            Expanded(
              child: countries.when(
                data: (list) => ListView.builder(
                  controller: scrollController,
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final c = list[index];
                    return ListTile(
                      title: Text(c.name,
                          style: AppTypography.body(14,
                              color: AppColors.onBg)),
                      subtitle: Text('${c.stationCount} stations',
                          style: AppTypography.body(11,
                              color: AppColors.onBgMuted(0.55))),
                      onTap: () {
                        ref.read(selectedCountryProvider.notifier).state = c;
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(AppColors.accent),
                  ),
                ),
                error: (e, s) => Center(
                  child: Text('Error: $e',
                      style: AppTypography.body(12,
                          color: AppColors.onBgMuted(0.55))),
                ),
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
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Select Genre',
                    style: AppTypography.display(24)),
              ),
            ),
            Expanded(
              child: tags.when(
                data: (list) => ListView.builder(
                  controller: scrollController,
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final t = list[index];
                    return ListTile(
                      title: Text(t.name,
                          style: AppTypography.body(14,
                              color: AppColors.onBg)),
                      subtitle: Text('${t.stationCount} stations',
                          style: AppTypography.body(11,
                              color: AppColors.onBgMuted(0.55))),
                      onTap: () {
                        ref.read(selectedTagProvider.notifier).state = t;
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(AppColors.accent),
                  ),
                ),
                error: (e, s) => Center(
                  child: Text('Error: $e',
                      style: AppTypography.body(12,
                          color: AppColors.onBgMuted(0.55))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: selected ? AppColors.accent : AppColors.surface(0.05),
          ),
          child: Text(
            label,
            style: AppTypography.body(12,
                weight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected
                    ? const Color(0xFF0A0A0A)
                    : AppColors.onBgMuted(0.75)),
          ),
        ),
      ),
    );
  }
}
