import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/weather.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/sky_marks.dart';

/// The sky, given a whole page — reached by double-tapping the little mark
/// in the top bar.
///
/// One big sculpted illustration of what the air is doing, the temperature
/// as a chiselled numeral you could stub a toe on, the condition said plainly,
/// and the week ahead in a single quiet row. The drama is the point: the top
/// bar's mark is a glance, this page is the sky taken seriously for once.
class WeatherPage extends ConsumerStatefulWidget {
  const WeatherPage({super.key});

  @override
  ConsumerState<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends ConsumerState<WeatherPage> {
  @override
  void initState() {
    super.initState();
    // Readings cached before this page existed carry no week. One refresh
    // upgrades them; a failure leaves the page honest with what it has.
    Future(() async {
      final repo = ref.read(weatherRepoProvider);
      final sky = await repo.cached();
      if (sky != null && sky.days.length > 1) return;
      if (await repo.refresh() != null && mounted) {
        ref.invalidate(weatherProvider);
      }
    });
  }

  /// Double-tap the sky and the book goes and looks again — the numeral
  /// re-counting is the whole confirmation.
  Future<void> _reread() async {
    HapticFeedback.mediumImpact();
    if (await ref.read(weatherRepoProvider).refresh() != null && mounted) {
      ref.invalidate(weatherProvider);
    }
  }

  static const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const _weekdaysFull = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  static const _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final sky = ref.watch(weatherProvider).value;
    final now = DateTime.now();

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x2, Gap.page, 0),
              child: Row(
                children: [
                  Pressable(
                    scale: 0.9,
                    onTap: () => Navigator.of(context).pop(),
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: PenChevron(size: 16, color: c.inkFaint),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${_weekdaysFull[now.weekday - 1]} · '
                      '${now.day} ${_months[now.month - 1]}',
                      textAlign: TextAlign.center,
                      style: LedgerType.label.copyWith(color: c.inkFaint),
                    ),
                  ),
                  // Balances the chevron so the date sits truly centred.
                  const SizedBox(width: 16),
                ],
              ),
            ),
            if (sky == null)
              Expanded(
                child: Center(
                  child: Text(
                    'the sky is unread — no signal, or no permission',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 13,
                      color: c.inkFaint,
                    ),
                  ),
                ),
              )
            else ...[
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _reread,
                  child: Center(
                    // The hero scales down as one piece on a short screen
                    // rather than letting any line squeeze or wrap.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _SkyHero(sky: sky, now: now),
                    ),
                  ),
                ),
              ),
              if (sky.days.length > 1)
                InkIn(
                  delay: const Duration(milliseconds: 340),
                  child: _WeekRow(days: sky.days, weekdays: _weekdays),
                ),
              if (sky.staleness(now) case final stale?)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.x2),
                  child: Text(
                    stale,
                    textAlign: TextAlign.center,
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 11,
                      color: c.inkFaint,
                    ),
                  ),
                ),
              const SizedBox(height: Gap.x6),
            ],
          ],
        ),
      ),
    );
  }
}

/// The stage, the numeral and the words — the middle of the page, stacked
/// tight so [FittedBox] can treat them as one sculpture.
class _SkyHero extends StatelessWidget {
  const _SkyHero({required this.sky, required this.now});

  final Weather sky;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final night = sky.isNight(now);
    final shape = skyShapeFor(sky.code, night: night);
    final subline = [
      'high ${sky.highC.round()}° · low ${sky.lowC.round()}°',
      ?sky.sunLine(now),
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkIn(
          child: _SkyStage(
            shape: shape,
            night: night,
            size: const Size(340, 250),
          ),
        ),
        // The illustration overhangs the numeral a touch, the way the
        // clouds sit down on the figure in a hand-set poster.
        Transform.translate(
          offset: const Offset(0, -Gap.x4),
          child: Column(
            children: [
              InkIn(
                delay: const Duration(milliseconds: 120),
                child: _ChiselNumeral(value: sky.nowC.round()),
              ),
              const SizedBox(height: Gap.x2),
              InkIn(
                delay: const Duration(milliseconds: 220),
                child: Text(
                  Weather.describe(sky.code),
                  style: LedgerType.title.copyWith(fontSize: 26, color: c.ink),
                ),
              ),
              const SizedBox(height: Gap.x1),
              InkIn(
                delay: const Duration(milliseconds: 280),
                child: Text(
                  subline,
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 13,
                    color: c.inkFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The temperature carved rather than typed: the figure laid down in layers
/// so it stands off the paper, counting up from nothing when the page opens.
class _ChiselNumeral extends StatelessWidget {
  const _ChiselNumeral({required this.value});

  final int value;

  static const _depth = 9;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final style = LedgerType.heroAmount.copyWith(
      fontSize: 164,
      height: 1.0,
      color: c.ink,
    );
    // The chisel's side: the ink stepped back toward the paper, so the
    // bevel is the same material as the page in both themes.
    final side = Color.lerp(c.ink, c.paper, 0.62)!;

    Widget carve(int shown) => Stack(
      children: [
        for (var i = _depth; i >= 1; i--)
          Transform.translate(
            offset: Offset(i * 1.0, i * 1.3),
            child: Text('$shown', style: style.copyWith(color: side)),
          ),
        Text('$shown', style: style),
      ],
    );

    if (Motion.reduced(context)) return carve(value);
    return TweenAnimationBuilder<double>(
      key: ValueKey(value),
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => carve(v.round()),
    );
  }
}

/// The week under the sculpture: eight small columns, to-day leading in
/// full ink, each wearing its day's mark and bracket.
class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.days, required this.weekdays});

  final List<DayForecast> days;
  final List<String> weekdays;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final week = days.take(8).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.page),
      child: Row(
        children: [
          for (final (i, d) in week.indexed)
            Expanded(
              child: InkIn(
                delay: Duration(milliseconds: 360 + 40 * i),
                child: _WeekDay(
                  day: d,
                  label: d.date.difference(today).inDays == 0
                      ? 'today'
                      : weekdays[d.date.weekday - 1],
                  isToday: d.date.difference(today).inDays == 0,
                  ink: c.ink,
                  faint: c.inkFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({
    required this.day,
    required this.label,
    required this.isToday,
    required this.ink,
    required this.faint,
  });

  final DayForecast day;
  final String label;
  final bool isToday;
  final Color ink;
  final Color faint;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: LedgerType.bodyText.copyWith(
            fontSize: 10,
            color: isToday ? ink : faint,
            fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: Gap.x2),
        SkyMark(
          shape: skyShapeFor(day.code, night: false),
          color: isToday ? ink : faint,
          size: 20,
        ),
        const SizedBox(height: Gap.x2),
        Text(
          '${day.highC.round()}°',
          style: LedgerType.amount.copyWith(fontSize: 13, color: ink),
        ),
        Text(
          '${day.lowC.round()}°',
          style: LedgerType.amount.copyWith(fontSize: 11, color: faint),
        ),
      ],
    );
  }
}

/// The illustration: the sky's shape built from solid forms — the sun a
/// vermilion disc, the clouds slabs of ink with loose puffs floating beside
/// them, every piece adrift on its own slow breath. Filled where the top
/// bar's mark is drawn in pen: chrome glances, a poster stares.
class _SkyStage extends StatefulWidget {
  const _SkyStage({required this.shape, required this.night, required this.size});

  final SkyShape shape;

  /// After dark the disc behind the weather is the moon's pale ghost, not
  /// the vermilion sun — fog at 2 a.m. must not glow red.
  final bool night;

  final Size size;

  @override
  State<_SkyStage> createState() => _SkyStageState();
}

class _SkyStageState extends State<_SkyStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    // One slow breath: long enough that nothing on the page reads as
    // "an animation", short enough that the sky is visibly alive.
    duration: const Duration(seconds: 14),
  );

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final reduced = Motion.reduced(context);
    if (reduced) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      _breath.repeat();
    }
    return CustomPaint(
      size: widget.size,
      painter: _SkyStagePainter(
        shape: widget.shape,
        night: widget.night,
        t: reduced ? const AlwaysStoppedAnimation(0.3) : _breath,
        ink: c.ink,
        faint: c.inkFaint,
        seal: c.seal,
      ),
    );
  }
}

class _SkyStagePainter extends CustomPainter {
  _SkyStagePainter({
    required this.shape,
    required this.night,
    required this.t,
    required this.ink,
    required this.faint,
    required this.seal,
  }) : super(repaint: t);

  final SkyShape shape;
  final bool night;
  final Animation<double> t;
  final Color ink;
  final Color faint;
  final Color seal;

  /// One slow sine, phase-shifted per element so nothing moves in step.
  double _drift(double amp, double phase) =>
      math.sin((t.value + phase) * 2 * math.pi) * amp;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    switch (shape) {
      case SkyShape.sun:
        _sunAlone(canvas, size);
      case SkyShape.partCloud:
        _sunDisc(canvas, Offset(w * 0.52, h * 0.36), h * 0.30);
        _cloudGroup(canvas, size, lift: 0.12);
      case SkyShape.cloud:
        _cloudGroup(canvas, size, lift: 0.0, second: true);
      // The wet skies raise their cloud high so what falls has somewhere
      // to fall.
      case SkyShape.rain:
        _cloudGroup(canvas, size, lift: 0.16);
        _rain(canvas, size, drops: 8, slant: 0.05, len: h * 0.065);
      case SkyShape.storm:
        _cloudGroup(canvas, size, lift: 0.16);
        // The rain steps aside for the bolt: drops at the flanks only.
        _rain(
          canvas,
          size,
          drops: 6,
          slant: 0.05,
          len: h * 0.055,
          partMiddle: true,
        );
        _bolt(canvas, size);
      case SkyShape.snow:
        _cloudGroup(canvas, size, lift: 0.16);
        _snow(canvas, size);
      case SkyShape.fog:
        _fog(canvas, size);
      case SkyShape.moon:
        _moon(canvas, size);
    }
  }

  /// A clear day: the disc, its wind, its birds — and the sculpture's loose
  /// spheres beside it, so the sky is never just one lonely circle.
  void _sunAlone(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    _sunDisc(canvas, Offset(w * 0.50, h * 0.44), h * 0.32);
    _birds(canvas, Offset(w * 0.72, h * 0.16), h * 0.030);
    for (final (cx, cy, r, phase) in [
      (0.13, 0.62, 0.052, 0.30),
      (0.87, 0.50, 0.042, 0.70),
      (0.80, 0.74, 0.028, 0.10),
    ]) {
      canvas.drawCircle(
        Offset(w * cx, h * cy + _drift(4, phase)),
        h * r,
        Paint()..color = ink,
      );
    }
  }

  /// A cloud the way a cloud actually holds together: every puff rests on
  /// one baseline, and the body between the outer puffs is a fill that
  /// *ends at their centres* — so the outline is all curve, never a shelf
  /// poking out past the last puff. [r] frames it: base at r.bottom, the
  /// tallest puff just reaching r.top.
  Path _cloudPath(Rect r) {
    final base = r.bottom;
    final w = r.width;
    final h = r.height;
    final left = (x: r.left + w * 0.18, r: h * 0.32);
    final mid = (x: r.left + w * 0.48, r: h * 0.50);
    final right = (x: r.left + w * 0.80, r: h * 0.36);
    return Path()
      ..addOval(
        Rect.fromCircle(center: Offset(left.x, base - left.r), radius: left.r),
      )
      ..addOval(
        Rect.fromCircle(center: Offset(mid.x, base - mid.r), radius: mid.r),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(right.x, base - right.r),
          radius: right.r,
        ),
      )
      // The valleys between tangent puffs, filled from within: the rect
      // spans centre to centre, so its corners stay inside the end puffs.
      ..addRect(
        Rect.fromLTRB(left.x, base - math.min(left.r, right.r), right.x, base),
      );
  }

  /// The vermilion disc with its two ink swipes — the one colour on the
  /// page, spent where it counts.
  void _sunDisc(Canvas canvas, Offset at, double r) {
    final centre = at + Offset(0, _drift(3.5, 0));
    canvas.drawCircle(centre, r, Paint()..color = seal);
    // Two slim streaks crossing the disc, adrift against its bob — the
    // suggestion of wind without a single literal ray.
    final streak = Paint()..color = ink;
    for (final (dy, len, phase) in [
      (-r * 0.42, r * 1.15, 0.20),
      (-r * 0.05, r * 0.80, 0.65),
    ]) {
      final o = centre + Offset(_drift(5, phase) - len / 2, dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(o.dx, o.dy, len, r * 0.075),
          Radius.circular(r),
        ),
        streak,
      );
    }
  }

  /// Two check-mark birds, riding their own slow updraft.
  void _birds(Canvas canvas, Offset at, double s) {
    final pen = Paint()
      ..color = ink
      ..strokeWidth = s * 0.55
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final (dx, dy, phase) in [(0.0, 0.0, 0.1), (s * 3.2, s * 1.6, 0.5)]) {
      final o = at + Offset(dx, dy + _drift(2.2, phase));
      canvas.drawPath(
        Path()
          ..moveTo(o.dx - s, o.dy)
          ..quadraticBezierTo(o.dx - s * 0.4, o.dy - s, o.dx, o.dy)
          ..quadraticBezierTo(o.dx + s * 0.4, o.dy - s, o.dx + s, o.dy),
        pen,
      );
    }
  }

  /// The cloud scene: one solid cloud mid-stage, an optional faint one
  /// higher and behind, and a few loose spheres adrift beside them. No
  /// shadows — ivory casts none on lacquer, and the smudges read as dirt.
  /// [lift] raises the whole group so falling weather has room below.
  void _cloudGroup(
    Canvas canvas,
    Size size, {
    required double lift,
    bool second = false,
  }) {
    final w = size.width;
    final h = size.height;

    if (second) {
      final dx = _drift(7, 0.55);
      canvas.drawPath(
        _cloudPath(
          Rect.fromLTWH(w * 0.54 + dx, h * (0.10 - lift), w * 0.30, h * 0.17),
        ),
        Paint()..color = faint,
      );
    }

    // The main cloud, drifting on its own breath.
    final dx = _drift(6, 0.0);
    canvas.drawPath(
      _cloudPath(
        Rect.fromLTWH(w * 0.17 + dx, h * (0.34 - lift), w * 0.54, h * 0.34),
      ),
      Paint()..color = ink,
    );

    // Loose spheres either side, bobbing counter-phase — the sculpture's
    // crumbs.
    for (final (cx, cy, r, phase) in [
      (0.095, 0.60 - lift, 0.055, 0.35),
      (0.86, 0.48 - lift, 0.045, 0.75),
      (0.92, 0.64 - lift, 0.030, 0.15),
    ]) {
      canvas.drawCircle(
        Offset(w * cx, h * cy + _drift(4, phase)),
        h * r,
        Paint()..color = ink,
      );
    }
  }

  /// Falling rain: each drop on its own loop, spawning under the cloud's
  /// base and fading as it lands. [partMiddle] leaves the centre clear —
  /// the storm's bolt stands there.
  void _rain(
    Canvas canvas,
    Size size, {
    required int drops,
    required double slant,
    required double len,
    bool partMiddle = false,
  }) {
    final w = size.width;
    final h = size.height;
    for (var i = 0; i < drops; i++) {
      final phase = i / drops;
      final fall = ((t.value * 3) + phase) % 1.0;
      var across = i / (drops - 1);
      if (partMiddle) {
        // Fold the middle of the spread out to the flanks, clear of the
        // bolt's full width.
        across = across < 0.5 ? across * 0.56 : 0.72 + (across - 0.5) * 0.56;
      }
      final x = w * (0.24 + 0.46 * across) - w * slant * fall;
      final y = h * (0.56 + 0.34 * fall);
      final fade = fall > 0.75 ? (1 - fall) / 0.25 : 1.0;
      canvas.drawLine(
        Offset(x, y),
        Offset(x - w * slant * 0.25, y + len),
        Paint()
          ..color = ink.withValues(alpha: 0.85 * fade)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// The vermilion bolt — the storm's whole point, so it *stands* there
  /// rather than existing only inside a blink: always drawn, breathing,
  /// and twice a loop it flares and swells the way lightning doubles.
  void _bolt(Canvas canvas, Size size) {
    final frac = (t.value * 2) % 1.0;
    final flash = switch (frac) {
      < 0.08 => 1 - frac / 0.08,
      >= 0.13 && < 0.26 => 1 - (frac - 0.13) / 0.13,
      _ => 0.0,
    };
    final w = size.width;
    final h = size.height;
    canvas.save();
    // The flare swells from where the bolt leaves the cloud.
    canvas.translate(w * 0.49, h * 0.54);
    canvas.scale(1 + 0.10 * flash);
    canvas.translate(-w * 0.49, -h * 0.54);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.51, h * 0.54)
        ..lineTo(w * 0.41, h * 0.72)
        ..lineTo(w * 0.485, h * 0.72)
        ..lineTo(w * 0.425, h * 0.90)
        ..lineTo(w * 0.575, h * 0.69)
        ..lineTo(w * 0.50, h * 0.69)
        ..lineTo(w * 0.575, h * 0.54)
        ..close(),
      Paint()..color = seal.withValues(alpha: 0.88 + 0.12 * flash),
    );
    canvas.restore();
  }

  /// Snow: the same loops as rain, slower, swaying instead of slanting.
  void _snow(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    for (var i = 0; i < 6; i++) {
      final phase = i / 6;
      final fall = ((t.value * 2) + phase) % 1.0;
      final x = w * (0.28 + 0.40 * (i / 5)) + _drift(5, phase);
      final y = h * (0.56 + 0.32 * fall);
      final fade = fall > 0.75 ? (1 - fall) / 0.25 : 1.0;
      canvas.drawCircle(
        Offset(x, y),
        h * 0.016,
        Paint()..color = ink.withValues(alpha: 0.85 * fade),
      );
    }
  }

  /// Fog, composed instead of listed: the light behind the weather peeking
  /// over a proper cloud sunk low, and the cloud dissolving downward into
  /// drifting bands — solid, then thinner, then almost gone, the way fog
  /// actually swallows a thing from the bottom up.
  void _fog(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // The light behind it all: vermilion by day, a pale breath of ink by
    // night, dimming and brightening on the slow loop.
    final glow = 0.7 + 0.3 * (0.5 + math.sin(t.value * 2 * math.pi) / 2);
    final disc = night
        ? ink.withValues(alpha: 0.30 * glow)
        : seal.withValues(alpha: glow);
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.30 + _drift(2.5, 0.3)),
      h * 0.22,
      Paint()..color = disc,
    );

    // The bank itself — a real cloud, low.
    final dx = _drift(5, 0.0);
    canvas.drawPath(
      _cloudPath(Rect.fromLTWH(w * 0.19 + dx, h * 0.26, w * 0.50, h * 0.28)),
      Paint()..color = ink,
    );

    // Its dissolution: three bands sliding over each other, each fainter
    // and shorter than the one above, staggered so the stack reads
    // hand-set.
    for (final (y, from, to, phase, alpha) in [
      (0.585, 0.16, 0.76, 0.80, 1.0),
      (0.700, 0.28, 0.86, 0.30, 0.70),
      (0.815, 0.22, 0.64, 0.55, 0.40),
    ]) {
      final bx = _drift(w * 0.03, phase);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * from + bx, h * y, w * (to - from), h * 0.072),
          Radius.circular(h),
        ),
        Paint()..color = ink.withValues(alpha: alpha),
      );
    }
  }

  /// The night: a full crescent in ink and a few stars breathing.
  void _moon(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centre = Offset(w * 0.52, h * 0.46 + _drift(3.5, 0));
    final r = h * 0.30;
    final full = Path()..addOval(Rect.fromCircle(center: centre, radius: r));
    final bite = Path()
      ..addOval(Rect.fromCircle(
        center: centre + Offset(r * 0.55, -r * 0.30),
        radius: r * 0.82,
      ));
    canvas.drawPath(Path.combine(PathOperation.difference, full, bite),
        Paint()..color = ink);
    for (final (cx, cy, s, phase) in [
      (0.24, 0.26, 0.022, 0.10),
      (0.78, 0.20, 0.017, 0.45),
      (0.83, 0.62, 0.020, 0.80),
      (0.16, 0.66, 0.014, 0.30),
    ]) {
      final twinkle =
          0.35 + 0.65 * (0.5 + math.sin((t.value + phase) * 4 * math.pi) / 2);
      final o = Offset(w * cx, h * cy);
      final arm = h * s;
      canvas.drawPath(
        Path()
          ..moveTo(o.dx, o.dy - arm)
          ..quadraticBezierTo(o.dx, o.dy, o.dx + arm, o.dy)
          ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + arm)
          ..quadraticBezierTo(o.dx, o.dy, o.dx - arm, o.dy)
          ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - arm),
        Paint()..color = faint.withValues(alpha: twinkle),
      );
    }
  }

  @override
  bool shouldRepaint(_SkyStagePainter old) =>
      old.shape != shape ||
      old.night != night ||
      old.ink != ink ||
      old.seal != seal;
}
