import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// The two hand-animated marks the book borrows, both bundled as Lottie.
///
/// They ship **exactly as drawn** — no colour delegates, no filters, nothing
/// remapped. The flame is the artist's white-and-grey fire and the target is
/// its own red; the book takes them as given. `test/lottie_marks_test.dart`
/// paints both and fails if anything ever repaints them.
///
/// Both are driven by an [Animation] the caller owns. Nothing here loops on
/// its own ticker: the streak moment is one timeline, and these are beats on
/// it — which also means reduced-motion and tests inherit the caller's
/// behaviour for free.

/// The streak flame: white fire with a grey body, burning on its own.
class StreakFlame extends StatelessWidget {
  const StreakFlame({super.key, required this.progress, this.height = 62});

  /// 0→1 across the flame's whole take (about three seconds at natural rate).
  final Animation<double> progress;

  /// How tall the fire itself should stand — not the canvas it came on.
  final double height;

  /// Where the fire actually paints inside its 1080² canvas, measured off
  /// rendered frames: the middle 40% across, 60% down. Laying out the whole
  /// square would reserve a box two and a half times the flame and leave the
  /// week nowhere to sit, so the widget takes only the fire's own room and
  /// lets the empty canvas hang over the edges.
  static const _drawnWidth = 0.403;
  static const _drawnHeight = 0.600;

  @override
  Widget build(BuildContext context) {
    final canvas = height / _drawnHeight;
    return SizedBox(
      width: canvas * _drawnWidth,
      height: height,
      child: OverflowBox(
        maxWidth: canvas,
        maxHeight: canvas,
        child: Lottie.asset(
          'assets/animation/streak_fire.json',
          controller: progress,
          width: canvas,
          height: canvas,
          fit: BoxFit.contain,
          // Small and short-lived — exactly what the raster cache is for.
          // Each frame is rasterised once instead of re-walking the shape
          // tree every tick, which is what made the moment feel heavy.
          renderCache: RenderCache.raster,
        ),
      ),
    );
  }
}

/// The dart finding the target — the day's mark, hit. Replaces the tick in a
/// box: a streak is something aimed at, so it lands rather than appearing.
class TargetStamp extends StatelessWidget {
  const TargetStamp({super.key, required this.progress, this.rings = 18});

  /// 0→1 across the throw (about 1.7 seconds at natural rate).
  final Animation<double> progress;

  /// The diameter of the rings themselves — sized to match the plain day
  /// circles beside it, so to-day keeps the week's rhythm instead of
  /// bullying its neighbours.
  final double rings;

  /// Measured off rendered frames: the rings are a perfect square covering
  /// the middle 49% of the 350² canvas, dead centre. The dart is extra — it
  /// flies in from beyond the right edge and, at rest, still juts out past
  /// the rings — so the widget lays out only the rings and lets the dart
  /// overhang. Nothing clips it: it should cross the gap to the next day.
  static const _ringsOfCanvas = 0.490;

  @override
  Widget build(BuildContext context) {
    final canvas = rings / _ringsOfCanvas;
    return SizedBox(
      width: rings,
      height: rings,
      child: OverflowBox(
        maxWidth: canvas,
        maxHeight: canvas,
        child: Lottie.asset(
          'assets/animation/target_stamp.json',
          controller: progress,
          width: canvas,
          height: canvas,
          fit: BoxFit.contain,
          renderCache: RenderCache.raster,
        ),
      ),
    );
  }
}
