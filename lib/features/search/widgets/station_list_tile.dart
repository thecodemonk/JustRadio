import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/station_art.dart';
import '../../../data/models/radio_station.dart';
import '../../../providers/audio_player_provider.dart';
import '../../../providers/favorites_provider.dart';

class StationListTile extends ConsumerWidget {
  final RadioStation station;
  final VoidCallback onTap;
  final bool showFavoriteToggle;

  const StationListTile({
    super.key,
    required this.station,
    required this.onTap,
    this.showFavoriteToggle = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavorite =
        ref.watch(isFavoriteProvider(station.stationuuid));
    final currentStation = ref.watch(
      radioPlayerControllerProvider.select((s) => s.currentStation),
    );
    final isActive = currentStation?.stationuuid == station.stationuuid;

    final parts = <String>[
      if (station.country.isNotEmpty) station.country,
      if (station.tagList.isNotEmpty) station.tagList.first,
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.surface(0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              bottom: BorderSide(color: AppColors.border(0.04)),
            ),
          ),
          child: Row(
            children: [
              StationArt(station: station, size: 44, radius: 5),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      style: AppTypography.body(14,
                          color: AppColors.onBgStrong),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (parts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        parts.join(' · '),
                        style: AppTypography.body(11,
                            color: AppColors.onBgMuted(0.55)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (station.bitrate > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '${station.bitrate}k',
                  style: AppTypography.mono(10,
                      color: AppColors.onBgMuted(0.4),
                      letterSpacing: 0.5),
                ),
              ],
              if (isActive) ...[
                const SizedBox(width: 10),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentGlow(0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
              if (showFavoriteToggle) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: isFavorite
                        ? AppColors.accent
                        : AppColors.onBgMuted(0.5),
                  ),
                  onPressed: () {
                    ref.read(favoritesProvider.notifier).toggle(station);
                  },
                  visualDensity: VisualDensity.compact,
                  splashRadius: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
