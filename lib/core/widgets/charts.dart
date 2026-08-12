import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import '../../data/repos/budget_math.dart';
import 'motion.dart';

/// The pace chart: solid ink = actual cumulative spend, dotted = even pace,
/// dashed vertical = today. A verdict, not a decoration.
class PaceChart extends StatelessWidget {
  const PaceChart({
    super.key,
    required this.daily,
    required this.elapsedDays,
    required this.totalDays,
    this.height = 74,
    this.progress = 1,
  });

  /// Cumulative spend per elapsed day, in paise.
  final List<int> daily;
  final int elapsedDays;
  final int totalDays;
  final double height;

  /// 0→1 draws the actual-spend line in, pen-style. Pair with [DrawIn].
  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _PacePainter(
          daily: daily,
          elapsedDays: elapsedDays,
          totalDays: totalDays,
          ink: c.quill,
          faint: c.inkFaint,
          rule: c.rule,
          progress: progress,
        ),
      ),
    );
  }
}

class _PacePainter extends CustomPainter {
  _PacePainter({
    required this.daily,
    required this.elapsedDays,
    required this.totalDays,
    required this.ink,
    required this.faint,
    required this.rule,
    required this.progress,
  });

  final List<int> daily;
  final int elapsedDays;
  final int totalDays;
  final Color ink;
  final Color faint;
  final Color rule;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height - 8;
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = rule
        ..strokeWidth = 1,
    );

    if (daily.isEmpty || totalDays == 0) return;
    final maxSpend = math.max(daily.last, 1);
    // Ideal line: even pace from 0 to the projected month-end at this ceiling.
    final idealEnd = maxSpend * totalDays / math.max(elapsedDays, 1);
    final ceiling = math.max(maxSpend.toDouble(), idealEnd) * 1.05;

    double x(int day) => size.width * day / totalDays;
    double y(num v) => base - (base - 6) * (v / ceiling);

    // Dotted even-pace line.
    final dotted = Paint()
      ..color = faint
      ..strokeWidth = 1.4;
    const dash = 3.0, gapLen = 5.0;
    final end = Offset(size.width, y(idealEnd));
    final dir = (end - Offset(0, base));
    final len = dir.distance;
    final unit = dir / len;
    var t = 0.0;
    while (t < len) {
      final a = Offset(0, base) + unit * t;
      final b = Offset(0, base) + unit * math.min(t + dash, len);
      canvas.drawLine(a, b, dotted);
      t += dash + gapLen;
    }

    // Solid actual line — drawn to [progress], like a pen crossing the page.
    final path = Path()..moveTo(0, base);
    for (var d = 0; d < daily.length; d++) {
      path.lineTo(x(d + 1), y(daily[d]));
    }
    final drawn = Path();
    for (final metric in path.computeMetrics()) {
      drawn.addPath(
        metric.extractPath(0, metric.length * progress.clamp(0, 1)),
        Offset.zero,
      );
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    if (progress >= 0.98) {
      final tip = Offset(x(daily.length), y(daily.last));
      canvas.drawCircle(tip, 3.4, Paint()..color = ink);
    }

    // Dashed vertical today-marker.
    final vx = x(elapsedDays);
    final vpaint = Paint()
      ..color = faint
      ..strokeWidth = 1;
    var vy = 6.0;
    while (vy < base) {
      canvas.drawLine(
        Offset(vx, vy),
        Offset(vx, math.min(vy + 2, base)),
        vpaint,
      );
      vy += 6;
    }
  }

  @override
  bool shouldRepaint(_PacePainter old) =>
      old.daily != daily || old.ink != ink || old.progress != progress;
}

/// A budget's bar, colored by forecast; outlined when the bill hasn't landed.
class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.pace, this.showToday = true});

  final BudgetPace pace;
  final bool showToday;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final color = switch (pace.status) {
      BudgetStatus.onPace => c.jama,
      BudgetStatus.projectedOver => c.warn,
      BudgetStatus.over => c.seal,
      BudgetStatus.pending => c.inkFaint,
    };
    final frac = pace.fractionSpent.clamp(0.0, 1.0);

    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 4,
              left: 0,
              right: 0,
              height: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.rule.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            if (pace.status == BudgetStatus.pending)
              Positioned(
                top: 4,
                left: 0,
                width: box.maxWidth * 0.99,
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: c.inkFaint, width: 1.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              )
            else
              Positioned(
                top: 4,
                left: 0,
                width: math.max(box.maxWidth * frac, 6),
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            if (showToday && pace.status != BudgetStatus.over)
              Positioned(
                top: 0,
                bottom: 0,
                left: box.maxWidth * pace.fractionElapsed,
                child: CustomPaint(
                  size: const Size(1, 14),
                  painter: _VDashPainter(c.inkFaint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VDashPainter extends CustomPainter {
  _VDashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(0, math.min(y + 2, size.height)), p);
      y += 5;
    }
  }

  @override
  bool shouldRepaint(_VDashPainter old) => old.color != color;
}

/// A 44×16 trend whisper inside an account row.
class Sparkline extends StatelessWidget {
  const Sparkline(this.points, {super.key, this.width = 44, this.height = 16});

  final List<double> points;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return CustomPaint(
      size: Size(width, height),
      painter: _SparkPainter(points, c.inkFaint),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.color);
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final min = points.reduce(math.min);
    final max = points.reduce(math.max);
    final range = (max - min) == 0 ? 1 : max - min;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y =
          size.height - (size.height - 2) * ((points[i] - min) / range) - 1;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.points != points || old.color != color;
}

/// The month grid: cell tint = spend intensity, pale = quiet day. Cells can
/// settle in one after another ([stagger]) and answer a touch.
class HeatGrid extends StatelessWidget {
  const HeatGrid({
    super.key,
    required this.dayTotalsPaise,
    this.stagger = false,
    this.totalDays,
    this.today,
    this.onDayTap,
    this.onDayLongPress,
  });

  /// Paise per day of the month, index 0 = the 1st.
  final List<int> dayTotalsPaise;

  /// True inks the cells in top-left to bottom-right, once, on entry.
  final bool stagger;

  /// Rule the whole month: days past [dayTotalsPaise] lie ahead — drawn
  /// fainter, ruled but unwritten, so the table never looks half-finished.
  final int? totalDays;

  /// The day of month (1-based) the pen is resting on. Its cell carries a
  /// small ink mark under the figure.
  final int? today;

  /// Both receive the day of month (1-based).
  final ValueChanged<int>? onDayTap;
  final ValueChanged<int>? onDayLongPress;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final maxSpend = dayTotalsPaise.isEmpty
        ? 1
        : math.max(dayTotalsPaise.reduce(math.max), 1);
    final count = math.max(
      totalDays ?? dayTotalsPaise.length,
      dayTotalsPaise.length,
    );
    // A month ruled into the page: shared hairlines, square corners, ink
    // wash where money moved. Detached rounded tiles are the contribution
    // graph every dashboard wears; a ledger draws its calendar as a table.
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Wider than tall: a table's rows, not a wall of boxes.
      childAspectRatio: 1.45,
      children: [
        for (var i = 0; i < count; i++)
          _cell(
            c,
            i,
            i < dayTotalsPaise.length ? dayTotalsPaise[i] : null,
            maxSpend,
          ),
      ],
    );
  }

  /// One day's cell; [v] null means the day hasn't arrived yet.
  Widget _cell(LedgerColors c, int i, int? v, int maxSpend) {
    final isToday = today != null && i + 1 == today;
    return InkIn(
      play: stagger,
      delay: Duration(milliseconds: 14 * i),
      child: Pressable(
        haptic: v != null && onDayTap != null,
        onTap: v == null || onDayTap == null ? null : () => onDayTap!(i + 1),
        onLongPress: v == null || onDayLongPress == null
            ? null
            : () => onDayLongPress!(i + 1),
        child: Container(
          decoration: BoxDecoration(
            // The wash is the writing ink, not the pen: iron-gall indigo
            // deepening with the day's spend, so the grid reads as pages
            // that took more or less ink — colour without a verdict.
            color: (v == null || v == 0)
                ? null
                : Color.lerp(c.paper, c.heat, 0.12 + 0.62 * v / maxSpend),
            // Half-width strokes meet their neighbours' to rule single
            // hairlines through the table rather than doubled walls.
            border: Border.all(
              color: v == null ? c.rule.withValues(alpha: 0.5) : c.rule,
              width: 0.5,
            ),
          ),
          alignment: Alignment.topLeft,
          padding: const EdgeInsets.only(top: 3, left: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${i + 1}',
                style: LedgerType.amount.copyWith(
                  fontSize: 9,
                  color: v == null
                      ? c.inkFaint.withValues(alpha: 0.45)
                      : v > maxSpend * 0.55
                      ? c.paper
                      : c.inkFaint,
                ),
              ),
              // Where the pen rests: a short stroke under today's figure.
              if (isToday)
                Container(
                  margin: const EdgeInsets.only(top: 1.5),
                  width: 8,
                  height: 1.6,
                  color: (v ?? 0) > maxSpend * 0.55 ? c.paper : c.quill,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
