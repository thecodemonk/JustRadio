import 'dart:async';

import 'package:flutter/material.dart';

/// Single-line text that scrolls horizontally (ping-pong) only when the
/// text overflows the available width. If the text fits, renders a
/// plain static Text — no animation, no scroll controller work.
///
/// The cadence is `[pause] → scroll to end → [pause] → scroll back →
/// repeat`. Re-measures whenever the layout width or the text changes.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// How long to linger at each end of the scroll before reversing.
  final Duration pause;

  /// Pixels per second — the scroll animation scales its duration
  /// based on the overflow distance so long titles don't feel rushed
  /// and short overflows don't look glacial.
  final double velocityPxPerSec;

  /// Padding applied to the right edge during measurement so a
  /// fully-visible-but-barely-fitting title doesn't tickle the
  /// scroll-needed threshold on sub-pixel rounding.
  final double safetyMargin;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.pause = const Duration(milliseconds: 1600),
    this.velocityPxPerSec = 55,
    this.safetyMargin = 4,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final _controller = ScrollController();
  Timer? _scheduled;
  double? _lastOverflow;
  bool _disposed = false;

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      // New track (or any text change) resets the animation. Cancel
      // any pending scroll so we don't chase the old offset.
      _lastOverflow = null;
      _scheduled?.cancel();
      _scheduled = null;
      if (_controller.hasClients) {
        _controller.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scheduled?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Duration _scrollDuration(double distance) {
    final seconds = distance / widget.velocityPxPerSec;
    return Duration(milliseconds: (seconds * 1000).clamp(1500, 12000).round());
  }

  Future<void> _runCycle(double distance) async {
    if (_disposed || !_controller.hasClients) return;
    // Pause at start.
    await _wait(widget.pause);
    if (_disposed || !_controller.hasClients) return;
    // Scroll to end.
    await _controller.animateTo(
      distance,
      duration: _scrollDuration(distance),
      curve: Curves.easeInOut,
    );
    if (_disposed || !_controller.hasClients) return;
    // Pause at end.
    await _wait(widget.pause);
    if (_disposed || !_controller.hasClients) return;
    // Scroll back.
    await _controller.animateTo(
      0,
      duration: _scrollDuration(distance),
      curve: Curves.easeInOut,
    );
    if (_disposed || !_controller.hasClients) return;
    // Loop as long as the text still overflows the same distance.
    if (_lastOverflow == distance) _runCycle(distance);
  }

  Future<void> _wait(Duration d) async {
    final c = Completer<void>();
    _scheduled = Timer(d, () {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final textWidth = painter.size.width;
        final maxWidth = constraints.maxWidth;
        final overflow = textWidth + widget.safetyMargin - maxWidth;

        if (overflow <= 0) {
          // Cancel any running scroll if a previous track overflowed.
          if (_lastOverflow != null) {
            _scheduled?.cancel();
            _lastOverflow = null;
            if (_controller.hasClients) _controller.jumpTo(0);
          }
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          );
        }

        // Only (re)kick the cycle when the overflow distance actually
        // changes — rebuild-on-every-frame scenarios shouldn't restart
        // the animation.
        if (_lastOverflow != overflow) {
          _lastOverflow = overflow;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_disposed || !mounted) return;
            if (_lastOverflow == overflow) _runCycle(overflow);
          });
        }

        return ClipRect(
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        );
      },
    );
  }
}
