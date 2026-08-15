import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../feel.dart';
import '../widgets/motion.dart';

/// The check-in ring: the four feeling families as one ring of light —
/// deep water into ember into gold into moss — softly bloomed, turning so
/// slowly you only notice if you stare. The invitation, not the answer.
class CheckInRing extends StatefulWidget {
  const CheckInRing({super.key, required this.size, this.child});

  final double size;

  /// Sits at the ring's centre — the plus and its word, usually.
  final Widget? child;

  @override
  State<CheckInRing> createState() => _CheckInRingState();
}

class _CheckInRingState extends State<CheckInRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 36),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _turn,
            builder: (context, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: _RingPainter(angle: _turn.value * 2 * math.pi),
            ),
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.angle});

  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final stroke = size.width * 0.10;
    final r = (size.width - stroke) / 2 - size.width * 0.06;
    final rect = Rect.fromCircle(center: c, radius: r);
    // The families around the wheel: water rising into ember, ember warming
    // into gold, gold easing into moss, moss deepening back into water.
    final shader = ui.Gradient.sweep(
      c,
      const [feelDeep, feelEmber, feelGold, feelMoss, feelDeep],
      const [0.0, 0.28, 0.55, 0.8, 1.0],
      TileMode.clamp,
      0,
      2 * math.pi,
      _rotation(c),
    );
    // The bloom underneath, then the ring itself; a small gap keeps it a
    // brush stroke rather than a wheel.
    const sweep = 2 * math.pi * 0.92;
    const start = -math.pi / 2 + 2 * math.pi * 0.04;
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 1.9
        ..strokeCap = StrokeCap.round
        ..maskFilter = ui.MaskFilter.blur(
          BlurStyle.normal,
          size.width * 0.045,
        ),
    );
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = ui.MaskFilter.blur(
          BlurStyle.normal,
          size.width * 0.012,
        ),
    );
  }

  Float64List _rotation(Offset c) => (Matrix4.identity()
        ..translateByDouble(c.dx, c.dy, 0, 1)
        ..rotateZ(angle)
        ..translateByDouble(-c.dx, -c.dy, 0, 1))
      .storage;

  @override
  bool shouldRepaint(_RingPainter old) => old.angle != angle;
}

/// A word's own mark: a soft organic round, its wobble seeded by the word
/// itself so 'frayed' always draws the same frayed shape — the way the
/// pen kit gives every category its own hand-drawn glyph.
class FeelBlob extends StatelessWidget {
  const FeelBlob({
    super.key,
    required this.word,
    required this.color,
    required this.size,
  });

  final String word;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _BlobPainter(word: word, color: color),
    );
  }
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter({required this.word, required this.color});

  final String word;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      feelBlobPath(word, size),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.word != word || old.color != color;
}

/// The blob's geometry, exposed so the picker can morph a chosen round into
/// its word's own shape. Eight spokes, radii wobbled by a hash of the word,
/// joined with a smooth closed curve.
Path feelBlobPath(String word, Size size, {double wobble = 1}) {
  var seed = 0;
  for (final u in word.codeUnits) {
    seed = (seed * 31 + u) & 0x7fffffff;
  }
  final rnd = math.Random(seed);
  const n = 8;
  final c = size.center(Offset.zero);
  final base = size.width / 2 * 0.86;
  final pts = <Offset>[
    for (var i = 0; i < n; i++)
      () {
        final a = 2 * math.pi * i / n;
        final r = base * (1 + wobble * (rnd.nextDouble() * 0.30 - 0.13));
        return c + Offset(math.cos(a) * r, math.sin(a) * r);
      }(),
  ];
  final path = Path();
  for (var i = 0; i < n; i++) {
    final p0 = pts[i];
    final p1 = pts[(i + 1) % n];
    final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    if (i == 0) path.moveTo(mid.dx, mid.dy);
    final next = pts[(i + 1) % n];
    final nextMid = Offset(
      (next.dx + pts[(i + 2) % n].dx) / 2,
      (next.dy + pts[(i + 2) % n].dy) / 2,
    );
    path.quadraticBezierTo(p1.dx, p1.dy, nextMid.dx, nextMid.dy);
  }
  path.close();
  return path;
}
