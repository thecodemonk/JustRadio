import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Stylized backdrop for a genre tile: layered color blobs + grain + a
/// genre-appropriate icon silhouette. Fully deterministic per tag name so
/// the same genre always renders the same way across sessions.
class ProceduralGenreArt extends StatelessWidget {
  final String tagName;
  const ProceduralGenreArt({super.key, required this.tagName});

  @override
  Widget build(BuildContext context) {
    final baseHue = _hashHue(tagName);
    final hueA = baseHue.toDouble();
    final hueB = (baseHue + 42) % 360;
    final hueC = (baseHue + 320) % 360; // analogous shift

    final c1 =
        HSLColor.fromAHSL(1.0, hueA, 0.62, 0.44).toColor();
    final c2 =
        HSLColor.fromAHSL(1.0, hueB.toDouble(), 0.58, 0.3).toColor();
    final c3 =
        HSLColor.fromAHSL(1.0, hueC.toDouble(), 0.55, 0.2).toColor();
    final base =
        HSLColor.fromAHSL(1.0, hueA, 0.35, 0.1).toColor();

    final seed = tagName.codeUnits.fold<int>(0, (a, b) => a + b * 7);
    final rng = math.Random(seed);
    final c1x = (rng.nextDouble() * 1.6) - 0.8;
    final c1y = (rng.nextDouble() * 1.6) - 0.8;
    final c2x = (rng.nextDouble() * 1.6) - 0.8;
    final c2y = (rng.nextDouble() * 1.6) - 0.8;
    final c3x = (rng.nextDouble() * 1.6) - 0.8;
    final c3y = (rng.nextDouble() * 1.6) - 0.8;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: base),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(c1x, c1y),
                radius: 0.9,
                colors: [c1, Colors.transparent],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(c2x, c2y),
                radius: 0.8,
                colors: [c2, Colors.transparent],
                stops: const [0.0, 0.65],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(c3x, c3y),
                radius: 0.7,
                colors: [c3, Colors.transparent],
                stops: const [0.0, 0.6],
              ),
            ),
          ),
          // Icon silhouette: offset toward the top-right so the bottom-left
          // text area stays clean.
          Positioned(
            top: -18,
            right: -14,
            child: Icon(
              iconForGenre(tagName),
              size: 120,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          CustomPaint(painter: _GrainPainter(seed: seed)),
          // Vignette darkening toward the bottom so text reads cleanly
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.35),
                ],
                stops: const [0.5, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

int _hashHue(String name) {
  if (name.isEmpty) return 265;
  final sum = name.codeUnits.fold<int>(0, (a, b) => a + b * 17);
  return sum.abs() % 360;
}

/// Maps a Radio Browser tag name to a Material icon that evokes the genre.
/// Matches on lowercase substrings so compound tags ("chill house",
/// "classic rock", "hip-hop") resolve to the dominant motif.
IconData iconForGenre(String raw) {
  final g = raw.toLowerCase().trim();

  if (g.contains('news')) return Icons.campaign;
  if (g.contains('sport')) return Icons.sports_basketball;
  if (g.contains('religious') ||
      g.contains('christian') ||
      g.contains('gospel') ||
      g.contains('worship')) {
    return Icons.church;
  }
  if (g.contains('talk') || g.contains('podcast')) return Icons.chat;

  if (g.contains('classical') ||
      g.contains('orchestra') ||
      g.contains('symphony') ||
      g.contains('opera')) {
    return Icons.piano;
  }

  if (g.contains('jazz') || g.contains('swing') || g.contains('bossa')) {
    return Icons.nightlife;
  }
  if (g.contains('blues')) return Icons.nights_stay;

  if (g.contains('electronic') ||
      g.contains('techno') ||
      g.contains('house') ||
      g.contains('edm') ||
      g.contains('trance') ||
      g.contains('dance') ||
      g.contains('dubstep') ||
      g.contains('drum') ||
      g.contains('synth')) {
    return Icons.graphic_eq;
  }

  if (g.contains('ambient') ||
      g.contains('chill') ||
      g.contains('lounge') ||
      g.contains('meditation') ||
      g.contains('relax')) {
    return Icons.waves;
  }

  if (g.contains('metal') || g.contains('punk') || g.contains('hardcore')) {
    return Icons.bolt;
  }
  if (g.contains('rock')) return Icons.whatshot;

  if (g.contains('country') ||
      g.contains('folk') ||
      g.contains('bluegrass') ||
      g.contains('americana')) {
    return Icons.park;
  }

  if (g.contains('hip') ||
      g.contains('rap') ||
      g.contains('r&b') ||
      g.contains('rnb') ||
      g.contains('soul') ||
      g.contains('funk')) {
    return Icons.headphones;
  }

  if (g.contains('pop') || g.contains('top 40') || g.contains('top40') ||
      g.contains('hits') || g.contains('chart')) {
    return Icons.star;
  }

  if (g.contains('latin') ||
      g.contains('salsa') ||
      g.contains('reggaeton') ||
      g.contains('bachata')) {
    return Icons.local_fire_department;
  }
  if (g.contains('reggae') || g.contains('ska') || g.contains('dub')) {
    return Icons.wb_sunny;
  }
  if (g.contains('world') ||
      g.contains('international') ||
      g.contains('global')) {
    return Icons.public;
  }

  if (g.contains('indie') || g.contains('alternative') || g.contains('alt')) {
    return Icons.auto_awesome;
  }

  if (g.contains('variety') ||
      g.contains('eclectic') ||
      g.contains('mix')) {
    return Icons.palette;
  }

  if (g.contains('community') ||
      g.contains('college') ||
      g.contains('university') ||
      g.contains('public radio')) {
    return Icons.groups;
  }

  if (g.contains('children') || g.contains('kids') || g.contains('family')) {
    return Icons.family_restroom;
  }

  if (g.contains('oldies') ||
      g.contains('80s') ||
      g.contains('70s') ||
      g.contains('60s') ||
      g.contains('90s') ||
      g.contains('retro') ||
      g.contains('vintage')) {
    return Icons.album;
  }

  return Icons.music_note;
}

class _GrainPainter extends CustomPainter {
  final int seed;
  _GrainPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final light = Paint()..color = Colors.white.withValues(alpha: 0.035);
    final dark = Paint()..color = Colors.black.withValues(alpha: 0.09);
    final count = (size.width * size.height / 180).round().clamp(120, 700);
    for (int i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 0.55, light);
    }
    for (int i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 0.55, dark);
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.seed != seed;
}
