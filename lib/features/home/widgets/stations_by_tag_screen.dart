import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ambient_bg.dart';
import '../../../data/repositories/radio_browser_repository.dart';
import '../../../providers/audio_player_provider.dart';
import '../../player/player_screen.dart';
import '../../search/search_provider.dart';
import '../../search/widgets/station_list_tile.dart';

class StationsByTagScreen extends ConsumerWidget {
  final Tag tag;
  const StationsByTagScreen({super.key, required this.tag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(stationsByTagProvider(tag.name));
    final currentStation = ref.watch(
      radioPlayerControllerProvider.select((s) => s.currentStation),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: AmbientBg(station: currentStation)),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('GENRE',
                          style:
                              AppTypography.label(10, letterSpacing: 2)),
                      const SizedBox(height: 6),
                      Text(_capitalize(tag.name),
                          style: AppTypography.display(38)),
                      const SizedBox(height: 2),
                      Text('${tag.stationCount} stations available',
                          style: AppTypography.body(13,
                              color: AppColors.onBgMuted(0.6))),
                    ],
                  ),
                ),
                Expanded(
                  child: stations.when(
                    data: (list) {
                      if (list.isEmpty) {
                        return Center(
                          child: Text(
                            'No stations found',
                            style: AppTypography.body(14,
                                color: AppColors.onBgMuted(0.6)),
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final station = list[index];
                          return StationListTile(
                            station: station,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PlayerScreen(station: station),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.accent),
                        ),
                      ),
                    ),
                    error: (e, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Error: $e',
                          style: AppTypography.body(12,
                              color: AppColors.onBgMuted(0.55)),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
