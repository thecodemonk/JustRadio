import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/station_art.dart';
import '../../providers/audio_player_provider.dart';
import 'player_screen.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(radioPlayerControllerProvider);
    final station = playerState.currentStation;
    if (station == null) return const SizedBox.shrink();

    final np = playerState.nowPlaying;
    final subtitle = np.isNotEmpty ? np.displayText : station.name;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            border: Border(
              top: BorderSide(color: AppColors.border(0.08)),
            ),
          ),
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => PlayerScreen(station: station),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  NowPlayingArt(
                    station: station,
                    albumArtUrl: playerState.albumArtUrl,
                    size: 44,
                    radius: 4,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          np.isNotEmpty ? np.title : station.name,
                          style: AppTypography.body(13,
                              color: AppColors.onBgStrong,
                              weight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          np.isNotEmpty
                              ? '${np.artist} · ${station.name}'
                              : subtitle,
                          style: AppTypography.body(11,
                              color: AppColors.onBgMuted(0.55)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (playerState.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.accent)),
                      ),
                    )
                  else
                    _MiniButton(
                      icon: playerState.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onTap: () => ref
                          .read(radioPlayerControllerProvider.notifier)
                          .togglePlayPause(),
                      primary: true,
                    ),
                  const SizedBox(width: 4),
                  _MiniButton(
                    icon: Icons.close,
                    onTap: () => ref
                        .read(radioPlayerControllerProvider.notifier)
                        .stop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  const _MiniButton(
      {required this.icon, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary
                ? Colors.white
                : AppColors.surface(0.06),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: AppColors.accentGlow(0.35),
                      blurRadius: 16,
                    )
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 18,
            color: primary
                ? const Color(0xFF0A0A0A)
                : AppColors.onBgMuted(0.75),
          ),
        ),
      ),
    );
  }
}
