import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/radio_station.dart';
import '../../providers/audio_player_provider.dart';
import '../search/widgets/station_list_tile.dart';
import 'widgets/genres_tab.dart';
import 'widgets/recent_tab.dart';

final topStationsProvider = FutureProvider<List<RadioStation>>((ref) async {
  final repository = ref.read(radioBrowserRepositoryProvider);
  return repository.getTopStations(limit: 50);
});

final trendingStationsProvider =
    FutureProvider<List<RadioStation>>((ref) async {
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
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TONIGHT ON JUST RADIO',
                    style: AppTypography.label(10, letterSpacing: 2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Something mellow?',
                    style: AppTypography.display(38),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.onBgMuted(0.55),
              labelStyle: AppTypography.body(13, weight: FontWeight.w500),
              unselectedLabelStyle: AppTypography.body(13),
              indicatorColor: AppColors.accent,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              dividerColor: AppColors.border(0.06),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              tabs: const [
                Tab(text: 'Popular'),
                Tab(text: 'Trending'),
                Tab(text: 'Genres'),
                Tab(text: 'Recent'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _StationListView(provider: topStationsProvider),
                  _StationListView(provider: trendingStationsProvider),
                  const GenresTab(),
                  const RecentTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationListView extends ConsumerWidget {
  final FutureProvider<List<RadioStation>> provider;
  const _StationListView({required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(provider);

    return stations.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text(
              'No stations available',
              style: AppTypography.body(14, color: AppColors.onBgMuted(0.6)),
            ),
          );
        }
        return RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.bgElevated,
          onRefresh: () async => ref.invalidate(provider),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final station = list[index];
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
        );
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
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 40, color: AppColors.onBgMuted(0.6)),
              const SizedBox(height: 16),
              Text('Failed to load stations',
                  style: AppTypography.display(22)),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: AppTypography.body(12,
                    color: AppColors.onBgMuted(0.55)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: const Color(0xFF0A0A0A),
                ),
                onPressed: () => ref.invalidate(provider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
