import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The shapes the sky comes in. Fewer than the WMO's ninety-odd codes on
/// purpose: a person glancing at a top bar can tell sun from cloud from
/// rain, and everything finer than that belongs in the words.
enum SkyShape { sun, moon, partCloud, cloud, rain, storm, fog, snow }

/// WMO code → a shape, with the hour deciding between a sun and a moon.
/// Clear at 2 a.m. is a moon; this book would not draw it any other way.
SkyShape skyShapeFor(int code, {required bool night}) => switch (code) {
  0 || 1 => night ? SkyShape.moon : SkyShape.sun,
  2 => night ? SkyShape.cloud : SkyShape.partCloud,
  3 => SkyShape.cloud,
  45 || 48 => SkyShape.fog,
  71 || 73 || 75 || 77 || 85 || 86 => SkyShape.snow,
  95 || 96 || 99 => SkyShape.storm,
  _ when code >= 51 && code <= 82 => SkyShape.rain,
  _ => SkyShape.cloud,
};

/// The sky, drawn in the same pen as the rest of the chrome — one stroke
/// weight, round caps, no fills except the sun's own disc.
class SkyMark extends StatelessWidget {
  const SkyMark({
    super.key,
    required this.shape,
    required this.color,
    this.size = 18,
  });

  final SkyShape shape;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _SkyPainter(shape: shape, color: color),
  );
}

class _SkyPainter extends CustomPainter {
  const _SkyPainter({required this.shape, required this.color});

  final SkyShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final pen = Paint()
      ..color = color
      ..strokeWidth = w * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    switch (shape) {
      case SkyShape.sun:
        _sun(canvas, size, pen, center: Offset(w / 2, w / 2), radius: w * 0.22);
      case SkyShape.moon:
        _moon(canvas, size, pen);
      case SkyShape.partCloud:
        // The sun peers over the shoulder of the cloud.
        _sun(
          canvas,
          size,
          pen,
          center: Offset(w * 0.36, w * 0.32),
          radius: w * 0.15,
          rays: 5,
          rayFrom: -math.pi,
          raySweep: math.pi * 1.1,
        );
        canvas.drawPath(
          _cloud(Rect.fromLTWH(w * 0.10, w * 0.40, w * 0.80, w * 0.44)),
          pen,
        );
      case SkyShape.cloud:
        canvas.drawPath(
          _cloud(Rect.fromLTWH(w * 0.06, w * 0.24, w * 0.88, w * 0.52)),
          pen,
        );
      case SkyShape.rain:
        canvas.drawPath(
          _cloud(Rect.fromLTWH(w * 0.06, w * 0.12, w * 0.88, w * 0.48)),
          pen,
        );
        for (var i = 0; i < 3; i++) {
          final x = w * (0.28 + i * 0.22);
          canvas.drawLine(
            Offset(x, w * 0.70),
            Offset(x - w * 0.07, w * 0.90),
            pen,
          );
        }
      case SkyShape.storm:
        canvas.drawPath(
          _cloud(Rect.fromLTWH(w * 0.06, w * 0.08, w * 0.88, w * 0.46)),
          pen,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.54, w * 0.60)
            ..lineTo(w * 0.40, w * 0.78)
            ..lineTo(w * 0.53, w * 0.78)
            ..lineTo(w * 0.42, w * 0.96),
          pen,
        );
      case SkyShape.fog:
        for (var i = 0; i < 4; i++) {
          final y = w * (0.28 + i * 0.16);
          final inset = i.isEven ? w * 0.10 : w * 0.20;
          canvas.drawLine(Offset(inset, y), Offset(w - inset, y), pen);
        }
      case SkyShape.snow:
        canvas.drawPath(
          _cloud(Rect.fromLTWH(w * 0.06, w * 0.12, w * 0.88, w * 0.48)),
          pen,
        );
        final dot = Paint()..color = color;
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
            Offset(w * (0.28 + i * 0.22), w * 0.82),
            w * 0.055,
            dot,
          );
        }
    }
  }

  /// A disc with rays — the full sun, when the sky is actually clear.
  void _sun(
    Canvas canvas,
    Size size,
    Paint pen, {
    required Offset center,
    required double radius,
    int rays = 8,
    double rayFrom = 0,
    double raySweep = math.pi * 2,
  }) {
    final w = size.width;
    canvas.drawCircle(center, radius, Paint()..color = color);
    for (var i = 0; i < rays; i++) {
      final angle = rayFrom + raySweep * (i / rays);
      final from = center + Offset(math.cos(angle), math.sin(angle)) * (radius + w * 0.10);
      final to = center + Offset(math.cos(angle), math.sin(angle)) * (radius + w * 0.22);
      canvas.drawLine(from, to, pen);
    }
  }

  /// A crescent: one disc with a second bitten out of it.
  void _moon(Canvas canvas, Size size, Paint pen) {
    final w = size.width;
    final full = Path()
      ..addOval(Rect.fromCircle(center: Offset(w * 0.52, w / 2), radius: w * 0.32));
    final bite = Path()
      ..addOval(Rect.fromCircle(center: Offset(w * 0.72, w * 0.40), radius: w * 0.30));
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, bite),
      Paint()..color = color,
    );
  }

  /// A cloud built the way a cloud actually looks: three overlapping discs
  /// sitting on a flat base, unioned into one outline. Arcs alone flatten
  /// into a blob at eighteen pixels — this survives being small, which is
  /// the whole job of chrome.
  Path _cloud(Rect r) {
    final w = r.width;
    final h = r.height;
    final baseY = r.bottom - h * 0.30;
    final puffs = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(r.left + w * 0.27, baseY),
          radius: h * 0.34,
        ),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(r.left + w * 0.50, r.top + h * 0.36),
          radius: h * 0.40,
        ),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(r.left + w * 0.75, baseY - h * 0.04),
          radius: h * 0.32,
        ),
      );
    final base = Path()
      ..addRRect(
        RRect.fromLTRBR(
          r.left + w * 0.10,
          baseY,
          r.right - w * 0.08,
          r.bottom,
          Radius.circular(h * 0.30),
        ),
      );
    return Path.combine(PathOperation.union, puffs, base);
  }

  @override
  bool shouldRepaint(_SkyPainter old) =>
      old.shape != shape || old.color != color;
}
