import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../data/providers.dart';
import '../../data/repos/habit_repo.dart';
import '../../data/repos/marks_repo.dart';

// Only the water itself carries colour — the room is the book's own paper,
// night or day. The blues sit a step brighter on lacquer and a step deeper
// on cream, so the liquid reads in both hours.
const _waterNight = Color(0xFF7B87F2);
const _waterNightDeep = Color(0xFF5560D8);
const _waterDay = Color(0xFF5B6BD6);
const _waterDayDeep = Color(0xFF3D4BB0);

/// The water room: tap the habit and the day's glasses become a vessel that
/// actually fills — the level rises on a spring, the surface is a living
/// wave, and each glass sloshes as it lands. One big add, one quiet undo.
class WaterPage extends ConsumerStatefulWidget {
  const WaterPage({super.key, required this.habit, required this.day});

  final Habit habit;
  final DateTime day;

  @override
  ConsumerState<WaterPage> createState() => _WaterPageState();
}

class _WaterPageState extends ConsumerState<WaterPage>
    with TickerProviderStateMixin {
  int _count = 0;

  /// The fill, 0…1 of the vessel — animated toward count/target.
  late final AnimationController _level = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  /// The living surface: a slow loop the waves ride on.
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  /// The slosh: amplitude kicked up for a beat when a glass lands.
  late final AnimationController _slosh = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  String get _key => LedgerDates.dayKey(widget.day);

  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(marksRepoProvider).watchDay(widget.day).listen((m) {
      if (!mounted) return;
      final count = countOn(m, _key, widget.habit.kind);
      if (count == _count) return;
      final grew = count > _count;
      setState(() => _count = count);
      final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      final t = (count / widget.habit.target).clamp(0.0, 1.0);
      if (still) {
        _level.value = t;
      } else {
        _level.animateTo(t, curve: Curves.easeOutCubic);
        if (grew) {
          _slosh
            ..value = 0
            ..forward();
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _wave.stop();
    } else if (!_wave.isAnimating) {
      _wave.repeat();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _level.dispose();
    _wave.dispose();
    _slosh.dispose();
    super.dispose();
  }

  void _add() {
    HapticFeedback.selectionClick();
    if (_count + 1 == widget.habit.target) HapticFeedback.mediumImpact();
    ref.read(marksRepoProvider).bump(widget.day, widget.habit.kind);
  }

  void _takeBack() {
    if (_count == 0) return;
    HapticFeedback.selectionClick();
    ref.read(marksRepoProvider).unbump(widget.day, widget.habit.kind);
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.habit.target;
    final unit = widget.habit.unit ?? 'marks';
    final pct = (_count / target * 100).clamp(0, 100).round();
    final c = LedgerColors.of(context);
    final night = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.x6, Gap.x2, Gap.x6, Gap.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    widget.habit.name.toLowerCase(),
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 14,
                      color: c.inkFaint,
                    ),
                  ),
                  const Spacer(),
                  Pressable(
                    key: const ValueKey('water-close'),
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.x2),
                      child: PenCross(size: 18, color: c.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.x4),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The vessel itself, filling as the day drinks.
                    Expanded(
                      flex: 5,
                      child: AnimatedBuilder(
                        animation:
                            Listenable.merge([_level, _wave, _slosh]),
                        builder: (context, _) => CustomPaint(
                          painter: _VesselPainter(
                            level: _level.value,
                            phase: _wave.value * 2 * math.pi,
                            slosh: _sloshKick(),
                            water: night ? _waterNight : _waterDay,
                            waterDeep:
                                night ? _waterNightDeep : _waterDayDeep,
                            ink: c.ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.x6),
                    // The day's numbers, big and unboxed.
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$pct%',
                            style: LedgerType.heroAmount.copyWith(
                              fontSize: 34,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            'of the day',
                            style: LedgerType.bodyText.copyWith(
                              fontSize: 12,
                              color: c.inkFaint,
                            ),
                          ),
                          const SizedBox(height: Gap.x6),
                          Text(
                            '$target',
                            style: LedgerType.heroAmount.copyWith(
                              fontSize: 26,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            '$unit the goal',
                            style: LedgerType.bodyText.copyWith(
                              fontSize: 12,
                              color: c.inkFaint,
                            ),
                          ),
                          const SizedBox(height: Gap.x6),
                          CountUp(
                            value: _count,
                            format: (v) => '$v',
                            style: LedgerType.heroAmount.copyWith(
                              fontSize: 104,
                              height: 1,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            'so far to-day',
                            style: LedgerType.bodyText.copyWith(
                              fontSize: 12,
                              color: c.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.x4),
              // The panel: one big add, one quiet way back.
              Container(
                padding: const EdgeInsets.all(Gap.x4),
                decoration: BoxDecoration(
                  color: c.paperRaised,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _count >= target
                          ? 'the day is full.'
                          : 'one ${widget.habit.unit == null ? 'mark' : 'glass'} at a time.',
                      textAlign: TextAlign.center,
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 13,
                        color: c.inkFaint,
                      ),
                    ),
                    const SizedBox(height: Gap.x3),
                    Pressable(
                      haptic: false,
                      onTap: _add,
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          color: c.ink,
                          borderRadius: BorderRadius.circular(27),
                        ),
                        child: Center(
                          child: Text(
                            'add a ${widget.habit.unit == null ? 'mark' : 'glass'}',
                            style: LedgerType.bodyStrong.copyWith(
                              fontSize: 16,
                              color: c.paper,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_count > 0) ...[
                      const SizedBox(height: Gap.x3),
                      Pressable(
                        haptic: false,
                        onTap: _takeBack,
                        child: Text(
                          'take one back',
                          textAlign: TextAlign.center,
                          style: LedgerType.bodyStrong.copyWith(
                            fontSize: 13,
                            color: c.inkFaint,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The slosh's extra amplitude: swells and dies inside one beat.
  double _sloshKick() {
    final t = _slosh.value;
    if (t == 0 || t == 1) return 0;
    return math.sin(math.pi * t) * (1 - t) * 2.4;
  }
}

/// The vessel: a tall rounded glass, a cap, and the water alive inside it —
/// two waves out of phase so the surface reads as liquid, not as a bar
/// chart lying on its side.
class _VesselPainter extends CustomPainter {
  const _VesselPainter({
    required this.level,
    required this.phase,
    required this.slosh,
    required this.water,
    required this.waterDeep,
    required this.ink,
  });

  final double level;
  final double phase;
  final double slosh;
  final Color water;
  final Color waterDeep;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final glass = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.06, w * 0.84, h * 0.94 - h * 0.06),
      Radius.circular(w * 0.16),
    );

    // The cap.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.34, 0, w * 0.32, h * 0.055),
        Radius.circular(w * 0.03),
      ),
      Paint()..color = ink.withValues(alpha: 0.85),
    );

    // The water, clipped to the glass.
    canvas.save();
    canvas.clipRRect(glass);
    final top = glass.top, bottom = glass.bottom;
    final surface = bottom - (bottom - top) * level;
    _wavePath(canvas, size, surface, phase, 7 + slosh * 6, waterDeep, 0.75);
    _wavePath(
      canvas,
      size,
      surface,
      phase + math.pi / 1.6,
      5 + slosh * 4,
      water,
      0.9,
    );
    canvas.restore();

    // The glass itself: a quiet edge and one falling highlight.
    canvas.drawRRect(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ink.withValues(alpha: 0.35),
    );
    canvas.drawLine(
      Offset(w * 0.20, h * 0.14),
      Offset(w * 0.20, h * 0.34),
      Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = ink.withValues(alpha: 0.22),
    );
  }

  void _wavePath(
    Canvas canvas,
    Size size,
    double surface,
    double phase,
    double amp,
    Color color,
    double alpha,
  ) {
    final w = size.width, h = size.height;
    final path = Path()..moveTo(0, surface);
    for (double x = 0; x <= w; x += 4) {
      path.lineTo(
        x,
        surface + math.sin(phase + x / w * 2 * math.pi) * amp,
      );
    }
    path
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(_VesselPainter old) =>
      old.level != level ||
      old.phase != phase ||
      old.slosh != slosh ||
      old.water != water ||
      old.ink != ink;
}
