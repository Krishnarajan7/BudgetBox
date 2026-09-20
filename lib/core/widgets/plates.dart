import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import '../typography.dart';
import 'motion.dart';

/// The component kit the money pages are built from since September 2026:
/// tonal plates instead of ruled lines, medallion rows, gliding pill
/// controls, stat tiles, and filled charts. Borrowed from the apps whose
/// surfaces read as finished — Copilot's cards, Monzo's medallions, the
/// gliding segmented control every good iOS app ships — and set in this
/// book's own inks and faces, so nothing here could be mistaken for a
/// template.

/// A soft rounded surface a group of rows sits on. Tone, not outline:
/// [paperRaised] on [paper], a whisper of shadow by day, none at night
/// (a shadow on black is mud).
class Plate extends StatelessWidget {
  const Plate({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
    this.margin = const EdgeInsets.only(top: Gap.x3),
    this.radius = 22,
    this.onTap,
    this.tone,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;
  final VoidCallback? onTap;

  /// A wash laid over the plate — a category ink at low alpha, say.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final night = c.paper.computeLuminance() < 0.2;
    final box = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: tone == null ? c.paperRaised : Color.alphaBlend(tone!, c.paperRaised),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: night
            ? null
            : [
                BoxShadow(
                  color: c.ink.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: child,
    );
    return onTap == null ? box : Pressable(scale: 0.985, onTap: onTap, child: box);
  }
}

/// A plate's title line: the label, and what it adds up to.
class PlateHead extends StatelessWidget {
  const PlateHead(this.label, {super.key, this.trailing, this.sub});

  final String label;
  final Widget? trailing;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.ink),
          ),
          if (sub != null) ...[
            const SizedBox(width: Gap.x2),
            Text(
              sub!,
              style: LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint),
            ),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// The tinted disc a row wears: the mark in its ink on a wash of the same
/// ink. Colour follows the entity, and the disc is what makes a list
/// scannable at arm's length.
class Medallion extends StatelessWidget {
  const Medallion({
    super.key,
    required this.icon,
    this.ink,
    this.size = 36,
    this.iconSize = 17,
    this.square = false,
  });

  final IconData icon;
  final Color? ink;
  final double size;
  final double iconSize;

  /// Full circle by default — a disc reads as a mark, a rounded square
  /// reads as a box. Square only where a grid of them wants it.
  final bool square;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final tint = ink ?? c.inkFaint;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(square ? size * 0.3 : size),
      ),
      child: Icon(icon, size: iconSize, color: tint),
    );
  }
}

/// One row on a plate: medallion, title over a subline, the figure on the
/// right in mono with an optional line beneath it. No hairline — the
/// spacing is the separator.
class PlateRow extends StatelessWidget {
  const PlateRow({
    super.key,
    required this.title,
    this.sub,
    this.leading,
    this.amount,
    this.amountWidget,
    this.amountColor,
    this.amountSub,
    this.trailing,
    this.struck = false,
    this.onTap,
    this.onLongPress,
    this.dense = false,
  });

  final String title;
  final String? sub;

  /// Usually a [Medallion]. Null keeps the text flush left.
  final Widget? leading;
  final String? amount;
  final Widget? amountWidget;
  final Color? amountColor;

  /// A quiet line under the figure — a percent, a change.
  final Widget? amountSub;
  final Widget? trailing;
  final bool struck;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final strike = struck ? TextDecoration.lineThrough : null;
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 6 : 8),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: Gap.x3)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 14.5,
                    color: struck ? c.inkFaint : c.ink,
                    decoration: strike,
                  ),
                ),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 12,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Gap.x3),
          if (amountWidget != null || amount != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                amountWidget ??
                    Text(
                      amount!,
                      style: LedgerType.amountTotal.copyWith(
                        fontSize: 15,
                        color: struck ? c.inkFaint : (amountColor ?? c.ink),
                        decoration: strike,
                      ),
                    ),
                ?amountSub,
              ],
            ),
          if (trailing != null) ...[const SizedBox(width: Gap.x2), trailing!],
        ],
      ),
    );
    if (onTap == null && onLongPress == null) return row;
    return Pressable(
      scale: 0.99,
      haptic: false,
      onTap: onTap,
      onLongPress: onLongPress,
      child: row,
    );
  }
}

/// A segmented control whose thumb glides to the chosen segment. Track in
/// the raised tone, thumb in ink, the chosen word in paper; the others in
/// faint ink on the track.
class PillSegments extends StatelessWidget {
  const PillSegments({
    super.key,
    required this.labels,
    required this.index,
    required this.onSelect,
    this.height = 34,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final reduced = Motion.reduced(context);
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.paperRaised,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: reduced ? Duration.zero : const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.quill,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (i, label) in labels.indexed)
                    Expanded(
                      child: Pressable(
                        key: ValueKey('pill-$label'),
                        haptic: false,
                        scale: 0.97,
                        onTap: () {
                          if (i == index) return;
                          HapticFeedback.selectionClick();
                          onSelect(i);
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: reduced ? Duration.zero : Motion.quick,
                            style: LedgerType.bodyStrong.copyWith(
                              fontSize: 12.5,
                              color: i == index ? c.paper : c.inkFaint,
                            ),
                            child: Text(label),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One stat, open on the paper: a small label, the figure, a line under
/// it. No surface of its own — three of these side by side, parted by a
/// hairline, are a strip of answers under a hero, not a row of boxes.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.valueWidget,
    this.sub,
    this.tone,
    this.onTap,
  });

  final String label;
  final String value;
  final Widget? valueWidget;
  final String? sub;

  /// The figure's ink — credit green for a gain, plain otherwise.
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: LedgerType.label.copyWith(fontSize: 11, color: c.inkFaint),
          ),
          const SizedBox(height: 3),
          valueWidget ??
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LedgerType.amountTotal.copyWith(
                  fontSize: 19,
                  color: tone ?? c.ink,
                ),
              ),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LedgerType.bodyText.copyWith(
                  fontSize: 11.5,
                  color: c.inkFaint,
                ),
              ),
            ),
        ],
      ),
    );
    return onTap == null ? body : Pressable(haptic: false, onTap: onTap, child: body);
  }
}

/// Stats in a row, parted by hairlines rather than boxed.
class StatTiles extends StatelessWidget {
  const StatTiles({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, t) in tiles.indexed) ...[
              if (i > 0)
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(
                    horizontal: Gap.x3,
                    vertical: 2,
                  ),
                  color: c.rule,
                ),
              Expanded(child: t),
            ],
          ],
        ),
      ),
    );
  }
}

/// A filled, smoothed area chart: the line drawn as a curve through its
/// points, a gradient pooling beneath it, a lit dot at the end. A finger
/// on it reads the point underneath. Draws itself in with [progress].
class AreaChart extends StatefulWidget {
  const AreaChart({
    super.key,
    required this.points,
    this.height = 132,
    this.ink,
    this.markIndex,
    this.labelFor,
    this.onScrub,
    this.baselineIndex,
  });

  final List<double> points;
  final double height;
  final Color? ink;

  /// A faint dashed rule at this point's height — a high-water mark.
  final int? markIndex;

  /// What to print above the finger for point [i]. Null hides the label.
  final String Function(int i)? labelFor;
  final ValueChanged<int?>? onScrub;

  /// A point whose height is ruled across as the comparison line.
  final int? baselineIndex;

  @override
  State<AreaChart> createState() => _AreaChartState();
}

class _AreaChartState extends State<AreaChart> {
  int? _scrub;

  void _read(Offset local, double width) {
    final n = widget.points.length;
    if (n < 2 || width <= 0) return;
    final i = ((local.dx / width) * (n - 1)).round().clamp(0, n - 1);
    if (i != _scrub) {
      HapticFeedback.selectionClick();
      setState(() => _scrub = i);
      widget.onScrub?.call(i);
    }
  }

  void _lift() {
    if (_scrub != null) {
      setState(() => _scrub = null);
      widget.onScrub?.call(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final ink = widget.ink ?? c.quill;
    final n = widget.points.length;
    final scrub = _scrub;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        key: const ValueKey('area-chart-touch'),
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (d) => _read(d.localPosition, box.maxWidth),
        onLongPressMoveUpdate: (d) => _read(d.localPosition, box.maxWidth),
        onLongPressEnd: (_) => _lift(),
        onLongPressCancel: _lift,
        onHorizontalDragStart: (d) => _read(d.localPosition, box.maxWidth),
        onHorizontalDragUpdate: (d) => _read(d.localPosition, box.maxWidth),
        onHorizontalDragEnd: (_) => _lift(),
        onHorizontalDragCancel: _lift,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            children: [
              Positioned.fill(
                top: 18,
                child: DrawIn(
                  duration: const Duration(milliseconds: 800),
                  builder: (context, t) => CustomPaint(
                    painter: _AreaPainter(
                      points: widget.points,
                      ink: ink,
                      rule: c.rule,
                      faint: c.inkFaint,
                      progress: t,
                      markIndex: widget.markIndex,
                      scrubIndex: scrub,
                    ),
                  ),
                ),
              ),
              if (scrub != null && widget.labelFor != null && n > 1)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment((scrub / (n - 1)) * 2 - 1, 0),
                    child: Text(
                      key: const ValueKey('area-chart-scrub'),
                      widget.labelFor!(scrub),
                      style: LedgerType.amount.copyWith(
                        fontSize: 11,
                        color: c.ink,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({
    required this.points,
    required this.ink,
    required this.rule,
    required this.faint,
    required this.progress,
    this.markIndex,
    this.scrubIndex,
  });

  final List<double> points;
  final Color ink;
  final Color rule;
  final Color faint;
  final double progress;
  final int? markIndex;
  final int? scrubIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final base = size.height - 4;
    final min = points.reduce(math.min);
    final max = points.reduce(math.max);
    final range = (max - min) == 0 ? 1.0 : max - min;
    Offset at(int i) => Offset(
      size.width * i / (points.length - 1),
      base - (base - 14) * ((points[i] - min) / range) * 0.9 - 2,
    );

    // A cubic through the points: each segment's control handles lean a
    // third of the way toward the neighbours, which is the smoothing every
    // finance chart uses and none of them credits.
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? at(0) : at(i - 1);
      final p1 = at(i);
      final p2 = at(i + 1);
      final p3 = i + 2 < points.length ? at(i + 2) : p2;
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    // The pool under the line, revealed with the line.
    final revealW = size.width * progress.clamp(0.0, 1.0);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, revealW, size.height));
    final fill = Path.from(path)
      ..lineTo(size.width, base)
      ..lineTo(0, base)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ink.withValues(alpha: 0.28), ink.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.restore();

    // The high-water mark, dashed.
    final mark = markIndex;
    if (mark != null && mark >= 0 && mark < points.length) {
      final y = at(mark).dy;
      final p = Paint()
        ..color = faint.withValues(alpha: 0.45 * progress)
        ..strokeWidth = 1;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 3, size.width), y), p);
        x += 7;
      }
    }

    // The line, drawn to progress.
    final drawn = Path();
    for (final m in path.computeMetrics()) {
      drawn.addPath(m.extractPath(0, m.length * progress.clamp(0.0, 1.0)), Offset.zero);
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // The lit end.
    if (progress >= 0.98) {
      final end = at(points.length - 1);
      canvas.drawCircle(end, 9, Paint()..color = ink.withValues(alpha: 0.16));
      canvas.drawCircle(end, 4, Paint()..color = ink);
    }

    final s = scrubIndex;
    if (s != null && s >= 0 && s < points.length && progress >= 0.98) {
      final p = at(s);
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, base),
        Paint()
          ..color = faint.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 5, Paint()..color = ink);
      canvas.drawCircle(p, 2.4, Paint()..color = rule);
    }
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.points != points ||
      old.progress != progress ||
      old.markIndex != markIndex ||
      old.scrubIndex != scrubIndex ||
      old.ink != ink;
}

/// A single horizontal progress bar with rounded caps, filled to
/// [fraction] of the track; a small tick can mark a point on it.
class RoundedBar extends StatelessWidget {
  const RoundedBar({
    super.key,
    required this.fraction,
    this.ink,
    this.height = 6,
    this.tick,
    this.animate = true,
  });

  final double fraction;
  final Color? ink;
  final double height;

  /// 0..1 position of a tick (to-day's mark on a month bar).
  final double? tick;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    Widget bar(double t) => CustomPaint(
      size: Size(double.infinity, height),
      painter: _RoundedBarPainter(
        fraction: (fraction * t).clamp(0.0, 1.0),
        ink: ink ?? c.quill,
        track: c.rule,
        tick: tick,
        faint: c.inkFaint,
      ),
    );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: animate
          ? DrawIn(duration: const Duration(milliseconds: 550), builder: (context, t) => bar(t))
          : bar(1),
    );
  }
}

class _RoundedBarPainter extends CustomPainter {
  _RoundedBarPainter({
    required this.fraction,
    required this.ink,
    required this.track,
    required this.faint,
    this.tick,
  });

  final double fraction;
  final Color ink;
  final Color track;
  final Color faint;
  final double? tick;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, r),
      Paint()..color = track,
    );
    final w = size.width * fraction;
    if (w > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, math.max(w, size.height), size.height),
          r,
        ),
        Paint()..color = ink,
      );
    }
    if (tick case final t?) {
      final x = size.width * t.clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(x, -2),
        Offset(x, size.height + 2),
        Paint()
          ..color = faint
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_RoundedBarPainter old) =>
      old.fraction != fraction || old.ink != ink || old.tick != tick;
}

/// A donut: thick arcs with rounded caps and a breath of paper between
/// them, drawn clockwise from the top over a faint track, with whatever
/// belongs in the middle set there. The track is the remainder — what is
/// left to a target — so a half-full ring is half the story at a glance.
class Donut extends StatelessWidget {
  const Donut({
    super.key,
    required this.segments,
    this.total,
    this.size = 128,
    this.thickness = 12,
    this.center,
  });

  /// (value, ink) in the order they are drawn.
  final List<(double, Color)> segments;

  /// What a full ring means. Null makes the segments fill the ring.
  final double? total;
  final double size;
  final double thickness;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: DrawIn(
        duration: const Duration(milliseconds: 750),
        builder: (context, t) => CustomPaint(
          painter: _DonutPainter(
            segments: segments,
            total: total,
            track: c.rule,
            thickness: thickness,
            progress: t,
          ),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.total,
    required this.track,
    required this.thickness,
    required this.progress,
  });

  final List<(double, Color)> segments;
  final double? total;
  final Color track;
  final double thickness;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      thickness / 2,
      thickness / 2,
      size.width - thickness,
      size.height - thickness,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness,
    );
    final sum = segments.fold(0.0, (s, e) => s + e.$1);
    final whole = (total == null || total! <= 0) ? sum : math.max(total!, sum);
    if (whole <= 0) return;
    // The gap between arcs, in radians, sized to the ring so it stays a
    // breath and never a bite.
    final r = rect.width / 2;
    final gap = (thickness * 0.55) / r;
    var start = -math.pi / 2;
    final drawn = segments.where((s) => s.$1 > 0).toList();
    for (final (value, ink) in drawn) {
      final sweep = (value / whole) * math.pi * 2 * progress;
      final inner = math.max(0.0, sweep - (drawn.length > 1 ? gap : 0));
      if (inner > 0) {
        canvas.drawArc(
          rect,
          start + (sweep - inner) / 2,
          inner,
          false,
          Paint()
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = thickness
            ..strokeCap = StrokeCap.round,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.segments != segments ||
      old.progress != progress ||
      old.total != total;
}
