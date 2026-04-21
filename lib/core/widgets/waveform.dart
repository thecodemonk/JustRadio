import 'dart:math' as math;
import 'package:flutter/material.dart';

class Waveform extends StatefulWidget {
  final String seedKey;
  final int bars;
  final double height;
  final Color color;
  final double progress;
  final bool animate;

  const Waveform({
    super.key,
    required this.seedKey,
    this.bars = 80,
    this.height = 56,
    this.color = Colors.white,
    this.progress = 1.0,
    this.animate = true,
  });

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<double> _baseValues;
  late List<double> _phases;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _buildShape();
    if (widget.animate) _controller.repeat();
  }

  void _buildShape() {
    final seed = widget.seedKey.codeUnits.fold<int>(0, (a, b) => a + b);
    _baseValues = List<double>.generate(widget.bars, (i) {
      final x = (math.sin(i * 0.37 + seed) +
                  math.sin(i * 0.13 + seed * 0.5)) *
              0.5 +
          0.5;
      final env = math.sin((i / widget.bars) * math.pi);
      return 0.15 + (x * 0.85) * (0.4 + env * 0.6);
    });
    _phases = List<double>.generate(
      widget.bars,
      (i) => (i * 0.37 + seed * 0.11) % (2 * math.pi),
    );
  }

  @override
  void didUpdateWidget(Waveform old) {
    super.didUpdateWidget(old);
    if (old.seedKey != widget.seedKey || old.bars != widget.bars) {
      _buildShape();
    }
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _WaveformPainter(
          listenable: _controller,
          baseValues: _baseValues,
          phases: _phases,
          color: widget.color,
          progress: widget.progress,
          animate: widget.animate,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Listenable listenable;
  final List<double> baseValues;
  final List<double> phases;
  final Color color;
  final double progress;
  final bool animate;

  _WaveformPainter({
    required this.listenable,
    required this.baseValues,
    required this.phases,
    required this.color,
    required this.progress,
    required this.animate,
  }) : super(repaint: listenable);

  @override
  void paint(Canvas canvas, Size size) {
    final bars = baseValues.length;
    if (bars == 0) return;

    final t = animate
        ? (listenable as AnimationController).value * 2 * math.pi
        : 0.0;
    final barSlot = size.width / bars;
    const barGap = 1.6; // 0.8px padding on each side

    for (int i = 0; i < bars; i++) {
      final base = baseValues[i];
      double v = base;
      if (animate) {
        // Two layered sines at different speeds/phases per bar for an
        // organic, non-repeating "breathing" look.
        final osc = 0.22 *
            math.sin(t * 2.3 + phases[i]) *
            (0.6 + 0.4 * math.sin(t * 0.9 + phases[i] * 0.5));
        v = (base + osc).clamp(0.08, 1.0);
      }
      final h = v * size.height;
      final x = i * barSlot + barGap / 2;
      final w = barSlot - barGap;
      final y = (size.height - h) / 2;

      final lit = i / bars < progress;
      final paint = Paint()
        ..color = color.withValues(alpha: lit ? 1.0 : 0.28);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w.clamp(0.5, double.infinity), h),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.color != color ||
      old.progress != progress ||
      old.animate != animate ||
      old.baseValues != baseValues;
}
