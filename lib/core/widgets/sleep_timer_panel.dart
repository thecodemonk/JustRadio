import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../../providers/sleep_timer_provider.dart';

class SleepTimerPanel extends ConsumerWidget {
  final bool compact;
  const SleepTimerPanel({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sleepTimerProvider);
    final presets = const [15, 30, 60, 90];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'SLEEP TIMER',
                style: AppTypography.mono(10,
                    color: AppColors.onBgMuted(0.4), letterSpacing: 1.8),
              ),
            ),
            if (state.isActive)
              TextButton(
                onPressed: () =>
                    ref.read(sleepTimerProvider.notifier).cancel(),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Cancel',
                    style: AppTypography.body(11, color: AppColors.accent)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(presets.length, (i) {
            final m = presets[i];
            final active = state.durationMinutes == m;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == presets.length - 1 ? 0 : 6),
                child: _PresetButton(
                  label: '${m}m',
                  active: active,
                  onTap: () {
                    if (active) {
                      ref.read(sleepTimerProvider.notifier).cancel();
                    } else {
                      ref.read(sleepTimerProvider.notifier).start(m);
                    }
                  },
                ),
              ),
            );
          }),
        ),
        if (state.isActive) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Stops in ${state.formattedRemaining}',
              style: AppTypography.mono(11,
                  color: AppColors.accent, letterSpacing: 1.2),
            ),
          ),
        ],
      ],
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PresetButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.surface(0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border(0.05)),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTypography.mono(11,
                  color: active
                      ? const Color(0xFF0A0A0A)
                      : AppColors.onBgMuted(0.8),
                  weight: FontWeight.w500,
                  letterSpacing: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
