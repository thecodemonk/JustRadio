import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/radio_station.dart';
import '../../providers/audio_player_provider.dart';
import '../search/widgets/station_list_tile.dart';
import '../player/player_screen.dart';

final topStationsProvider = FutureProvider<List<RadioStation>>((ref) async {
  final repository = ref.read(radioBrowserRepositoryProvider);
  return repository.getTopStations(limit: 50);
});

final trendingStationsProvider = FutureProvider<List<RadioStation>>((ref) async {
  final repository = ref.read(radioBrowserRepositoryProvider);
  return repository.getTrendingStations(limit: 50);
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JustRadio'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Popular'),
            Tab(text: 'Trending'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStationList(topStationsProvider),
          _buildStationList(trendingStationsProvider),
        ],
      ),
    );
  }

  Widget _buildStationList(FutureProvider<List<RadioStation>> provider) {
    final stations = ref.watch(provider);

    return stations.when(
      data: (stationList) {
        if (stationList.isEmpty) {
          return const Center(
            child: Text('No stations available'),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(provider);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: stationList.length,
            itemBuilder: (context, index) {
              final station = stationList[index];
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
      },
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(
                'Failed to load stations',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref.invalidate(provider);
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
