import 'package:flutter/material.dart';

import '../../../core/tokens.dart';
import '../../../core/typography.dart';
import '../../../core/widgets/motion.dart';
import '../../../data/api/endpoints/endpoints.dart';

/// The folio's one picture, and the reason funds do not look like spending.
///
/// A spend chart has one line, because a rupee spent is a rupee gone and
/// there is nothing to compare it to. A fund has two numbers that are never
/// the same: what you **put in**, and what it is **worth**. So this draws
/// both — cost as a hard staircase that only ever steps up when money moved,
/// value as a curve that wanders on its own — and shades the space between
/// them. That shaded band is the gain: not a number you are asked to trust,
/// but the visible distance between two lines you can both account for.
///
/// Green above, seal below, and the band flips with it, so a folio under
/// water reads as under water at a glance without a single label.
class GrowthChart extends StatelessWidget {
  const GrowthChart({super.key, required this.points, this.height = 168});

  final List<FolioPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'the lines need a few days to have a shape',
            style: LedgerType.label.copyWith(color: c.inkFaint),
          ),
        ),
      );
    }
    final up = points.last.valuePaise >= points.last.costPaise;
    final chart = CustomPaint(
      painter: _GrowthPainter(
        points: points,
        cost: c.inkFaint,
        value: up ? c.jama : c.seal,
        band: (up ? c.jama : c.seal).withValues(alpha: 0.16),
      ),
      size: Size.infinite,
    );
    return SizedBox(
      height: height,
      child: Motion.reduced(context)
          ? chart
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Motion.draw,
              curve: Curves.easeOutCubic,
              // Both lines ink in left to right together, the way a pen
              // would draw them — the band fills in behind the nib.
              builder: (_, t, _) => ClipRect(
                clipper: _Reveal(t),
                child: chart,
              ),
            ),
    );
  }
}

class _Reveal extends CustomClipper<Rect> {
  const _Reveal(this.t);

  final double t;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * t, size.height);

  @override
  bool shouldReclip(_Reveal old) => old.t != t;
}

class _GrowthPainter extends CustomPainter {
  _GrowthPainter({
    required this.points,
    required this.cost,
    required this.value,
    required this.band,
  });

  final List<FolioPoint> points;
  final Color cost;
  final Color value;
  final Color band;

  @override
  void paint(Canvas canvas, Size size) {
    // One scale for both lines: comparing them is the entire point, so they
    // can never be normalised apart. Zero is always on the floor, because a
    // cropped baseline would make a 2% gain look like a windfall.
    var top = 0;
    for (final p in points) {
      if (p.costPaise > top) top = p.costPaise;
      if (p.valuePaise > top) top = p.valuePaise;
    }
    if (top <= 0) return;
    final headroom = top * 1.08;

    double x(int i) => size.width * (i / (points.length - 1));
    double y(int paise) => size.height * (1 - paise / headroom);

    final costPath = Path();
    final valuePath = Path();
    for (final (i, p) in points.indexed) {
      final px = x(i);
      if (i == 0) {
        costPath.moveTo(px, y(p.costPaise));
        valuePath.moveTo(px, y(p.valuePaise));
      } else {
        // Cost is a staircase on purpose: money went in on a day, not
        // gradually across the week before it.
        costPath.lineTo(px, y(points[i - 1].costPaise));
        costPath.lineTo(px, y(p.costPaise));
        valuePath.lineTo(px, y(p.valuePaise));
      }
    }

    // The band between them, closed back along the cost line.
    final gap = Path.from(valuePath);
    for (var i = points.length - 1; i >= 0; i--) {
      gap.lineTo(x(i), y(points[i].costPaise));
    }
    gap.close();
    canvas.drawPath(gap, Paint()..color = band);

    canvas.drawPath(
      costPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = cost.withValues(alpha: 0.7),
    );
    canvas.drawPath(
      valuePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = value,
    );
    // The nib's last position: where the money stands today.
    canvas.drawCircle(
      Offset(x(points.length - 1), y(points.last.valuePaise)),
      3,
      Paint()..color = value,
    );
  }

  @override
  bool shouldRepaint(_GrowthPainter old) =>
      old.points != points || old.value != value;
}

/// The chart's key. Two words and two marks — enough to read the picture,
/// small enough not to become furniture.
class GrowthKey extends StatelessWidget {
  const GrowthKey({super.key, required this.up});

  final bool up;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Row(
      children: [
        _Mark(color: c.inkFaint.withValues(alpha: 0.7), thin: true),
        const SizedBox(width: 6),
        Text('put in', style: LedgerType.label.copyWith(color: c.inkFaint)),
        const SizedBox(width: Gap.x4),
        _Mark(color: up ? c.jama : c.seal, thin: false),
        const SizedBox(width: 6),
        Text('worth', style: LedgerType.label.copyWith(color: c.inkFaint)),
      ],
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.color, required this.thin});

  final Color color;
  final bool thin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: thin ? 1.2 : 2,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
