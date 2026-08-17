import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The row's image torn into a grid of particles that drift up and away in
/// a left-to-right wave — or, reversed, gather back out of the air into the
/// whole line. Drawn from the photograph, so every particle carries the
/// actual ink it was part of.
class ParticleField extends StatefulWidget {
  const ParticleField({
    super.key,
    required this.image,
    required this.reverse,
    required this.duration,
  });

  final ui.Image image;
  final bool reverse;
  final Duration duration;

  @override
  State<ParticleField> createState() => _ParticleFieldState();
}

class _ParticleFieldState extends State<ParticleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _ParticlePainter(
          image: widget.image,
          t: _ac.value,
          reverse: widget.reverse,
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({
    required this.image,
    required this.t,
    required this.reverse,
  });

  final ui.Image image;
  final double t;
  final bool reverse;

  /// Deterministic per-cell scatter — the same line always blows away the
  /// same way, like everything hand-seeded in this book.
  static double _n(int i, int salt) =>
      (math.sin(i * 127.1 + salt * 311.7) + 1) / 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final tt = reverse ? 1 - t : t;
    const cols = 26;
    final rows = math.max(2, (size.height / 12).round());
    final srcW = image.width / cols;
    final srcH = image.height / rows;
    final dstW = size.width / cols;
    final dstH = size.height / rows;
    final paint = Paint()..filterQuality = FilterQuality.low;

    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final i = y * cols + x;
        // The left edge lets go first; the wave crosses the line the same
        // way the pen struck it, and the last column only finishes at the
        // very end — the animation is never cut short.
        final local = ((tt * 1.75) - (x / cols) * 0.75).clamp(0.0, 1.0);
        if (local >= 1) continue;
        final e = Curves.easeIn.transform(local);
        final dx = (24 + 60 * _n(i, 1)) * e;
        final dy = -(14 + 48 * _n(i, 2)) * e;
        paint.color = Color.fromRGBO(0, 0, 0, 1 - local);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(x * srcW, y * srcH, srcW, srcH),
          Rect.fromLTWH(x * dstW + dx, y * dstH + dy, dstW, dstH),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.t != t || old.reverse != reverse || old.image != image;
}
