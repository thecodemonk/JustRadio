import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/station_art.dart';
import '../../../providers/audio_player_provider.dart';
import '../../../providers/recent_plays_provider.dart';

class RecentTab extends ConsumerWidget {
  const RecentTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentPlaysProvider);
    final currentStation = ref.watch(
      radioPlayerControllerProvider.select((s) => s.currentStation),
    );

    if (recents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history,
                size: 48, color: AppColors.accentGlow(0.5)),
            const SizedBox(height: 12),
            Text('No recent plays',
                style: AppTypography.display(22)),
            const SizedBox(height: 6),
            Text(
              'Stations you play will appear here.',
              style: AppTypography.body(13,
                  color: AppColors.onBgMuted(0.55)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 140),
      itemCount: recents.length,
      itemBuilder: (context, index) {
        final entry = recents[index];
        final station = entry.station;
        final active = currentStation?.stationuuid == station.stationuuid;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => playStationFromList(
              ref: ref,
              context: context,
              station: station,
            ),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.surface(0.05)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  bottom: BorderSide(color: AppColors.border(0.04)),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 76,
                    child: Text(
                      _relative(entry.playedAt),
                      style: AppTypography.mono(10,
                          color: AppColors.onBgMuted(0.45),
                          letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  StationArt(station: station, size: 36, radius: 4),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          station.name,
                          style: AppTypography.body(13,
                              color: AppColors.onBgStrong),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (station.country.isNotEmpty ||
                            station.tagList.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (station.country.isNotEmpty) station.country,
                              if (station.tagList.isNotEmpty)
                                station.tagList.first,
                            ].join(' · '),
                            style: AppTypography.body(11,
                                color: AppColors.onBgMuted(0.5)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (active)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.accentGlow(0.6),
                              blurRadius: 8),
                        ],
                      ),
                    )
                  else
                    Icon(Icons.play_arrow_rounded,
                        size: 18, color: AppColors.accent),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _relative(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) {
    return '${diff.inHours} hr${diff.inHours == 1 ? '' : 's'} ago';
  }
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  if (diff.inDays < 30) {
    final w = (diff.inDays / 7).floor();
    return '$w week${w == 1 ? '' : 's'} ago';
  }
  final months = (diff.inDays / 30).floor();
  return '$months month${months == 1 ? '' : 's'} ago';
}
