import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/audio_player_service.dart';
import '../../../providers/audio_player_provider.dart';

/// Debug-only card showing live ICY metadata from whichever engine is active.
/// Used during the just_audio-vs-mpv metadata comparison spike.
class IcyDebugOverlay extends ConsumerWidget {
  const IcyDebugOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) return const SizedBox.shrink();

    final service = ref.watch(audioPlayerServiceProvider);
    final asyncDebug = ref.watch(icyDebugStreamProvider);
    final info = asyncDebug.valueOrNull ??
        IcyDebugInfo.empty(service.engineName);

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ICY DEBUG · ${service.engineName.toUpperCase()}',
                style: AppTypography.mono(10,
                    color: AppColors.accent, letterSpacing: 1.4),
              ),
              const Spacer(),
              Text(
                info.timestamp.millisecondsSinceEpoch == 0
                    ? '—'
                    : _formatTs(info.timestamp),
                style: AppTypography.mono(10,
                    color: AppColors.onBgMuted(0.6)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _row('title', info.rawTitle),
          _row('url', info.rawUrl),
          _row('name', info.streamName),
          _row('genre', info.genre),
          _row('bitrate', info.bitrate?.toString()),
        ],
      ),
    );
  }

  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: AppTypography.mono(10,
                  color: AppColors.onBgMuted(0.5)),
            ),
          ),
          Expanded(
            child: Text(
              value == null || value.isEmpty ? '—' : value,
              style: AppTypography.mono(11,
                  color: AppColors.onBgStrong),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTs(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
