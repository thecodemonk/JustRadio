import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../data/models/radio_station.dart';
import '../theme/app_theme.dart';
import 'station_art.dart';

class AmbientBg extends StatefulWidget {
  final RadioStation? station;
  final double intensity;

  const AmbientBg({super.key, this.station, this.intensity = 1.0});

  @override
  State<AmbientBg> createState() => _AmbientBgState();
}

class _AmbientBgState extends State<AmbientBg>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    if (station == null) {
      return const ColoredBox(color: AppColors.bgBase);
    }

    final hues = stationHues(station);
    final c1 = HSLColor.fromAHSL(
            0.55 * widget.intensity, hues.h1.toDouble(), 0.7, 0.45)
        .toColor();
    final c2 = HSLColor.fromAHSL(
            0.45 * widget.intensity, hues.h2.toDouble(), 0.65, 0.38)
        .toColor();

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          final t = _controller.value * 2 * math.pi;
          // Slow orbital drift. Opposite directions so the two blobs
          // breathe relative to each other, not in lockstep.
          final c1x = -0.5 + 0.22 * math.sin(t);
          final c1y = -0.8 + 0.18 * math.cos(t * 0.7);
          final c2x = 0.6 + 0.2 * math.sin(t + math.pi);
          final c2y = 0.7 + 0.16 * math.cos(t * 0.8 + math.pi / 3);

          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppColors.bgBase),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(c1x, c1y),
                    radius: 1.4,
                    colors: [c1, Colors.transparent],
                    stops: const [0.0, 0.65],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(c2x, c2y),
                    radius: 1.2,
                    colors: [c2, Colors.transparent],
                    stops: const [0.0, 0.6],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
