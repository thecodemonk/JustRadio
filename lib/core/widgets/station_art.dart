import 'package:flutter/material.dart';
import '../../data/models/radio_station.dart';
import '../theme/app_theme.dart';

int stationHue(String id) {
  if (id.isEmpty) return 265;
  final sum = id.codeUnits.fold<int>(0, (a, b) => a + b * 31);
  return (sum.abs()) % 360;
}

({int h1, int h2}) stationHues(RadioStation station) {
  final h1 = stationHue(station.stationuuid.isEmpty
      ? station.name
      : station.stationuuid);
  final h2 = (h1 + 30) % 360;
  return (h1: h1, h2: h2);
}

class StationArt extends StatelessWidget {
  final RadioStation station;
  final double size;
  final double radius;
  final bool showInitials;
  final BoxShadow? shadow;

  const StationArt({
    super.key,
    required this.station,
    this.size = 64,
    this.radius = 6,
    this.showInitials = true,
    this.shadow,
  });

  String get _initials {
    final cleaned = station.name.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '');
    final words = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0]).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hues = stationHues(station);
    final c1 = HSLColor.fromAHSL(1.0, hues.h1.toDouble(), 0.62, 0.5).toColor();
    final c2 = HSLColor.fromAHSL(1.0, hues.h2.toDouble(), 0.55, 0.3).toColor();
    final c3 = HSLColor.fromAHSL(1.0, hues.h2.toDouble(), 0.45, 0.15).toColor();

    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.4),
          radius: 1.2,
          colors: [c1, c2, c3],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showInitials)
            Center(
              child: Text(
                _initials,
                style: AppTypography.display(
                  size * 0.42,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: RadialGradient(
                center: const Alignment(0.7, 0.8),
                radius: 0.8,
                colors: [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.4],
              ),
            ),
          ),
        ],
      ),
    );

    final hasFavicon = station.favicon.isNotEmpty;
    final image = hasFavicon
        ? Image.network(
            station.favicon,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
            loadingBuilder: (ctx, child, progress) =>
                progress == null ? child : fallback,
          )
        : fallback;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow != null ? [shadow!] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(width: size, height: size, child: image),
      ),
    );
  }
}
