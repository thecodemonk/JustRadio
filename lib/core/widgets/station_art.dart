import 'package:cached_network_image/cached_network_image.dart';
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

/// Station art with an optional track-level album art overlay. When
/// `albumArtUrl` is non-null, the album art fades in over the station logo
/// and stays until the track changes. The underlying [StationArt] is the
/// fallback — we never show a blank box if the album art fails to load.
class NowPlayingArt extends StatelessWidget {
  final RadioStation station;
  final String? albumArtUrl;
  final double size;
  final double radius;
  final BoxShadow? shadow;

  const NowPlayingArt({
    super.key,
    required this.station,
    this.albumArtUrl,
    this.size = 64,
    this.radius = 6,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    final base = StationArt(
      station: station,
      size: size,
      radius: radius,
      shadow: shadow,
    );

    final url = albumArtUrl;
    if (url == null || url.isEmpty) return base;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          base,
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            // AnimatedSwitcher keyed on URL so a new track cross-fades
            // instead of snapping — feels more like a music app.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: CachedNetworkImage(
                key: ValueKey(url),
                imageUrl: url,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
