import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/models/radio_station.dart';
import '../theme/app_theme.dart';
import 'station_art.dart';

class AmbientBg extends StatefulWidget {
  final RadioStation? station;

  /// When set, the widget renders a heavily blurred, darkened copy of
  /// this album art as a full-bleed backdrop. Cross-fades when the URL
  /// changes. Leave null to get the station-hue gradient (used on the
  /// browse/shell surfaces where art-derived colors would be noisy).
  final String? albumArtUrl;

  final double intensity;

  const AmbientBg({
    super.key,
    this.station,
    this.albumArtUrl,
    this.intensity = 1.0,
  });

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

    // Album-art backdrop — opt-in via `albumArtUrl`. Uses the resolved
    // track art as a heavily blurred full-screen wash, with a dark
    // gradient over the top for foreground-text contrast. Keeps a
    // subtle station-hue wash underneath so the transition between
    // "art resolved" and "art missing" feels unified.
    final artUrl = widget.albumArtUrl;
    if (artUrl != null && artUrl.isNotEmpty) {
      return IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.bgBase),
            // Custom layoutBuilder forces StackFit.expand on the
            // AnimatedSwitcher's internal Stack. Without it, the
            // intrinsic 200×200 of our ResizeImage determines the
            // rendered size and the backdrop paints as a small box
            // instead of filling the viewport.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  ...previous,
                  if (current != null) current,
                ],
              ),
              child: _AlbumArtBackdrop(
                key: ValueKey(artUrl),
                url: artUrl,
              ),
            ),
            // Bottom-heavy darkening — readable text over busy art.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.70),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
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

/// Full-bleed blurred album-art layer. We downscale through
/// `ResizeImage` before the `ImageFilter.blur` so the GPU work stays
/// cheap (blur cost is quadratic in pixel count). Scale up slightly in
/// the transform to hide blur edges at the screen boundary.
class _AlbumArtBackdrop extends StatelessWidget {
  final String url;

  const _AlbumArtBackdrop({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    // SizedBox.expand anchors the layout chain against the parent's
    // fill constraints. Without it, ResizeImage's intrinsic 200×200
    // propagates back up through ImageFiltered/Transform/ClipRect and
    // the whole thing paints at 200px.
    return SizedBox.expand(
      child: ClipRect(
        child: Transform.scale(
          scale: 1.18,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 40,
              sigmaY: 40,
              tileMode: TileMode.mirror,
            ),
            child: Image(
              image: ResizeImage(
                CachedNetworkImageProvider(url),
                // Pre-downscale to ~200px before blur. The blurred
                // result still looks identical at screen size and
                // costs ~9x less GPU than blurring the full image.
                width: 200,
                height: 200,
              ),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              frameBuilder: (_, child, frame, wasSyncLoaded) {
                if (wasSyncLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame != null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: child,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
