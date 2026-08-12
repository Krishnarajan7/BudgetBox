import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Marks drawn with the pen, not typed from a font.
///
/// Material's icon set is the most recognised drawing on any phone screen —
/// one glyph of it and a page reads as "an app" rather than as this book.
/// The few marks the chrome truly needs are drawn here by hand instead:
/// pen-weight strokes, rounded caps, and the half-degree of slack a nib
/// leaves. Category marks stay in [LedgerIcons] for now; this kit is the
/// chrome's.

/// The writing mark: a plus laid down in two strokes.
///
/// It sits a breath off square — a stamp pressed by a hand, not a glyph
/// centred by a compositor.
class PenPlus extends StatelessWidget {
  const PenPlus({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PenPlusPainter(color),
    );
  }
}

class _PenPlusPainter extends CustomPainter {
  const _PenPlusPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final arm = size.width * 0.30;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(1.2 * math.pi / 180);
    // The downstroke lands first, as it would on paper; the crossbar rides
    // a hair high of centre.
    canvas.drawLine(Offset(0, -arm), Offset(0, arm), pen);
    canvas.drawLine(Offset(-arm, -size.height * 0.015),
        Offset(arm, -size.height * 0.015), pen);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PenPlusPainter old) => old.color != color;
}

/// The box's mark: three short rules, each with its slider drawn as an ink
/// dot sitting on the line. Settings as a ledger would show them —
/// adjustments on rules — rather than machinery.
class PenSliders extends StatelessWidget {
  const PenSliders({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PenSlidersPainter(color),
    );
  }
}

class _PenSlidersPainter extends CustomPainter {
  const _PenSlidersPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = color;

    final w = size.width;
    final inset = w * 0.12;
    // Dots land staggered — set by a hand, not mirrored by a machine.
    final rows = [
      (y: size.height * 0.26, dotX: w * 0.62),
      (y: size.height * 0.52, dotX: w * 0.32),
      (y: size.height * 0.78, dotX: w * 0.72),
    ];
    for (final r in rows) {
      canvas.drawLine(Offset(inset, r.y), Offset(w - inset, r.y), rule);
      canvas.drawCircle(Offset(r.dotX, r.y), w * 0.10, dot);
    }
  }

  @override
  bool shouldRepaint(_PenSlidersPainter old) => old.color != color;
}

/// A small opening chevron for the wordmark — one bent pen stroke.
class PenChevron extends StatelessWidget {
  const PenChevron({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PenChevronPainter(color),
    );
  }
}

class _PenChevronPainter extends CustomPainter {
  const _PenChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final path = Path()
      ..moveTo(w * 0.24, size.height * 0.38)
      ..lineTo(w * 0.50, size.height * 0.64)
      ..lineTo(w * 0.76, size.height * 0.38);
    canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(_PenChevronPainter old) => old.color != color;
}

/// The chop before it lands: an empty seal outline, the same rounded-square
/// geometry as [Seal], waiting for the day to be closed onto it.
class SealOutline extends StatelessWidget {
  const SealOutline({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SealOutlinePainter(color),
    );
  }
}

class _SealOutlinePainter extends CustomPainter {
  const _SealOutlinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.09
      ..style = PaintingStyle.stroke;
    canvas.save();
    // The seal's resting tilt, faint here: the mark this button will make.
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-5 * math.pi / 180);
    final side = size.width * 0.72;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: side, height: side),
        Radius.circular(side * 0.28),
      ),
      pen,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SealOutlinePainter old) => old.color != color;
}

/// A magnifier drawn in two strokes: the glass, then the handle.
class PenSearch extends StatelessWidget {
  const PenSearch({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PenSearchPainter(color),
    );
  }
}

class _PenSearchPainter extends CustomPainter {
  const _PenSearchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final r = size.width * 0.28;
    final centre = Offset(size.width * 0.42, size.height * 0.42);
    canvas.drawCircle(centre, r, pen);
    final dir = const Offset(0.707, 0.707);
    canvas.drawLine(
      centre + dir * r,
      centre + dir * (size.width * 0.46),
      pen,
    );
  }

  @override
  bool shouldRepaint(_PenSearchPainter old) => old.color != color;
}

/// The month grid in miniature: four ruled cells, the book's own calendar.
class PenGrid extends StatelessWidget {
  const PenGrid({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PenGridPainter(color),
    );
  }
}

class _PenGridPainter extends CustomPainter {
  const _PenGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.08
      ..style = PaintingStyle.stroke;
    final inset = size.width * 0.14;
    final rect = Rect.fromLTRB(
        inset, inset, size.width - inset, size.height - inset);
    canvas.drawRect(rect, pen);
    canvas.drawLine(Offset(size.width / 2, inset),
        Offset(size.width / 2, size.height - inset), pen);
    canvas.drawLine(Offset(inset, size.height / 2),
        Offset(size.width - inset, size.height / 2), pen);
  }

  @override
  bool shouldRepaint(_PenGridPainter old) => old.color != color;
}

/// Ruled lines with entries on them — the list view's mark.
class PenLines extends StatelessWidget {
  const PenLines({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PenLinesPainter(color),
    );
  }
}

class _PenLinesPainter extends CustomPainter {
  const _PenLinesPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.085
      ..strokeCap = StrokeCap.round;
    final inset = size.width * 0.14;
    for (final t in [0.28, 0.52, 0.76]) {
      canvas.drawLine(Offset(inset, size.height * t),
          Offset(size.width - inset, size.height * t), pen);
    }
  }

  @override
  bool shouldRepaint(_PenLinesPainter old) => old.color != color;
}

/// A tick laid down in one bent stroke.
class PenTick extends StatelessWidget {
  const PenTick({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PenTickPainter(color),
    );
  }
}

class _PenTickPainter extends CustomPainter {
  const _PenTickPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.55)
      ..lineTo(size.width * 0.42, size.height * 0.74)
      ..lineTo(size.width * 0.78, size.height * 0.30);
    canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(_PenTickPainter old) => old.color != color;
}

/// Three resting dots — "more", said quietly.
class PenDots extends StatelessWidget {
  const PenDots({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PenDotsPainter(color),
    );
  }
}

class _PenDotsPainter extends CustomPainter {
  const _PenDotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = color;
    final y = size.height / 2;
    for (final t in [0.22, 0.5, 0.78]) {
      canvas.drawCircle(Offset(size.width * t, y), size.width * 0.08, dot);
    }
  }

  @override
  bool shouldRepaint(_PenDotsPainter old) => old.color != color;
}

/// A closing cross: two strokes, the pen's "never mind".
class PenCross extends StatelessWidget {
  const PenCross({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PenCrossPainter(color),
    );
  }
}

class _PenCrossPainter extends CustomPainter {
  const _PenCrossPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.10
      ..strokeCap = StrokeCap.round;
    final a = size.width * 0.26;
    final b = size.width * 0.74;
    canvas.drawLine(Offset(a, a), Offset(b, b), pen);
    canvas.drawLine(Offset(b, a), Offset(a, b), pen);
  }

  @override
  bool shouldRepaint(_PenCrossPainter old) => old.color != color;
}

/// A forward stroke with its head — the pen moving on.
class PenArrow extends StatelessWidget {
  const PenArrow({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PenArrowPainter(color),
    );
  }
}

class _PenArrowPainter extends CustomPainter {
  const _PenArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    canvas.drawLine(Offset(size.width * 0.16, y), Offset(size.width * 0.80, y), pen);
    final head = Path()
      ..moveTo(size.width * 0.58, size.height * 0.30)
      ..lineTo(size.width * 0.82, y)
      ..lineTo(size.width * 0.58, size.height * 0.70);
    canvas.drawPath(head, pen);
  }

  @override
  bool shouldRepaint(_PenArrowPainter old) => old.color != color;
}

/// The book with a face — the app's character. A monogram is a logo; a face
/// is someone to be glad to see at 6 a.m. Folder-tab silhouette, two uneven
/// pen-stroke eyes (one mid-wink), a smile a touch too wide.
class MarkFace extends StatelessWidget {
  const MarkFace({
    super.key,
    required this.width,
    required this.body,
    required this.face,
  });

  final double width;
  final Color body;
  final Color face;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, width * 0.82),
      painter: MarkFacePainter(body: body, face: face),
    );
  }
}

class MarkFacePainter extends CustomPainter {
  const MarkFacePainter({required this.body, required this.face});

  final Color body;
  final Color face;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // The folder-book: rounded slab, tab rising on the LEFT shoulder —
    // centred tabs read as cameras.
    final tabTop = h * 0.06;
    final bodyTop = h * 0.24;
    final r = w * 0.10;
    final slab = Path()
      ..moveTo(w * 0.04, h - r)
      ..lineTo(w * 0.04, tabTop + r)
      ..arcToPoint(Offset(w * 0.04 + r, tabTop), radius: Radius.circular(r))
      ..lineTo(w * 0.34, tabTop)
      // the shoulder falling to the body line
      ..lineTo(w * 0.46, bodyTop)
      ..lineTo(w * 0.96 - r, bodyTop)
      ..arcToPoint(Offset(w * 0.96, bodyTop + r), radius: Radius.circular(r))
      ..lineTo(w * 0.96, h - r)
      ..arcToPoint(Offset(w * 0.96 - r, h), radius: Radius.circular(r))
      ..lineTo(w * 0.04 + r, h)
      ..arcToPoint(Offset(w * 0.04, h - r), radius: Radius.circular(r))
      ..close();
    canvas.drawPath(slab, Paint()..color = body);

    final pen = Paint()
      ..color = face
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final eyeTop = h * 0.46;
    final eyeBottom = h * 0.62;
    // Left eye: a bar with a curled foot — mid-wink.
    final left = Path()
      ..moveTo(w * 0.34, eyeTop)
      ..lineTo(w * 0.34, eyeBottom - h * 0.045)
      ..arcToPoint(Offset(w * 0.27, eyeBottom - h * 0.045),
          radius: Radius.circular(w * 0.045), clockwise: true);
    canvas.drawPath(left, pen);
    // Right eye: straight, a touch taller — the one paying attention.
    canvas.drawLine(
        Offset(w * 0.62, eyeTop - h * 0.03), Offset(w * 0.62, eyeBottom), pen);

    // The smile, a touch too wide, riding low.
    final smile = Path()
      ..moveTo(w * 0.30, h * 0.74)
      ..quadraticBezierTo(w * 0.48, h * 0.92, w * 0.68, h * 0.73);
    canvas.drawPath(smile, pen);
  }

  @override
  bool shouldRepaint(MarkFacePainter old) =>
      old.body != body || old.face != face;
}


