import 'dart:async' show unawaited;
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
import '../shell/shell.dart';

/// The book's cover. The character — the folder-book with a face, the same
/// one that settles onto the splash — waits here and IS the door: the app's
/// own PIN, nothing else (no Face ID; the book answers to its owner's hand,
/// not the phone's). The character has a temper about it: a wrong PIN and
/// it flushes vermilion, brows down, mouth flat, shaking its head — then
/// cools back to itself. The right PIN completes the wink it was always
/// halfway through, takes the press, and the book opens through it. Under
/// the date the cover may whisper one true thing about yesterday — never a
/// nag.
class LockPage extends ConsumerStatefulWidget {
  const LockPage({super.key});

  @override
  ConsumerState<LockPage> createState() => _LockPageState();
}

class _LockPageState extends ConsumerState<LockPage>
    with TickerProviderStateMixin {
  final _entered = StringBuffer();
  bool _hasPin = false;
  bool _checked = false;
  bool _wrong = false;
  bool _success = false;

  /// How many digits this cover asks for. New PINs are six; a PIN set
  /// before the change stays four, so the book never locks out its owner.
  int _pinLength = 4;

  /// One quiet, factual line under the date — or nothing at all.
  String? _whisper;

  /// Built in [initState], never lazily: a cover that is never shaken (a
  /// book with no PIN) would otherwise construct its controller inside
  /// dispose, reaching for a ticker that is already gone.
  late final AnimationController _shake;

  /// The character pressed down on the way in — the same hand that stamps
  /// the seal, landing on the book's face instead.
  late final AnimationController _press;

  /// The flare of temper: forward is the flush (quick — anger arrives),
  /// reverse is the cooling (slow — it takes a moment to let go).
  late final AnimationController _anger;
  late final CurvedAnimation _angerCurve;

  /// The wink, completed: the half-closed eye shuts, holds a beat, opens.
  late final AnimationController _wink;

  /// The pause after the press, before the shell fades up through the cover.
  static const _openBeat = Duration(milliseconds: 240);

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _anger = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 1400),
    );
    // The flush snaps in; the cooling releases — held a beat, then let go,
    // easing all the way out so the last of the red never visibly steps.
    _angerCurve = CurvedAnimation(
      parent: _anger,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _wink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _prepare();
    _listenForWhispers();
  }

  @override
  void dispose() {
    _shake.dispose();
    _press.dispose();
    _angerCurve.dispose();
    _anger.dispose();
    _wink.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final settings = ref.read(settingsRepoProvider);
    final hasPin = await settings.hasPin();
    final pinLength = await settings.pinLength();
    if (!mounted) return;
    if (!hasPin) {
      // No lock set — then there is no cover and nothing to ask. The book
      // opens itself: kural first (the shell raises it), then the day.
      Navigator.of(
        context,
      ).pushReplacement(LedgerRoute(builder: (_) => const LedgerShell()));
      return;
    }
    setState(() {
      _hasPin = hasPin;
      _pinLength = pinLength;
      _checked = true;
    });
  }

  /// Read-only: did yesterday get closed, and how long has the journal been
  /// quiet? One of those becomes the cover's line; neither is a reproach.
  Future<void> _listenForWhispers() async {
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yKey = LedgerDates.dayKey(today.subtract(const Duration(days: 1)));

    final sealed = await (db.select(
      db.daySeals,
    )..where((s) => s.date.equals(yKey))).getSingleOrNull();
    if (!mounted) return;
    if (sealed != null) {
      setState(() => _whisper = 'yesterday, closed');
      return;
    }

    // One row per day and only ever a few hundred — cheap to read whole.
    final pages = await db.select(db.journalEntries).get();
    if (!mounted) return;
    DateTime? last;
    for (final p in pages) {
      if (p.body.trim().isEmpty) continue;
      final d = DateTime.tryParse(p.date);
      if (d == null) continue;
      if (last == null || d.isAfter(last)) last = d;
    }
    if (last == null) return;
    final gap = today
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    if (gap < 2) return;
    if (mounted) setState(() => _whisper = '${_count(gap)} days unwritten');
  }

  /// Small numbers read better as words; past ten, the figure is kinder.
  static String _count(int n) {
    const words = [
      'zero', 'one', 'two', 'three', 'four', 'five', //
      'six', 'seven', 'eight', 'nine', 'ten',
    ];
    return n <= 10 ? words[n] : '$n';
  }

  /// Success is a moment with two beats: the character finishes the wink it
  /// has always been halfway through — eye shuts, holds, opens — and only
  /// then takes the press, the cover stamped by the hand that opens it. A
  /// beat passes, and the shell fades up through it.
  Future<void> _celebrateAndOpen() async {
    if (_success) return;
    setState(() => _success = true);
    HapticFeedback.lightImpact();
    if (!Motion.reduced(context)) {
      // Any leftover temper cools instantly — a right answer clears the air.
      _anger.value = 0;
      await _wink.forward(from: 0);
      HapticFeedback.mediumImpact();
      await _press.forward(from: 0);
      await Future<void>.delayed(_openBeat);
    }
    if (!mounted) return;
    // Straight to the money — after the door nothing stands between Krish
    // and the book.
    Navigator.of(
      context,
    ).pushReplacement(LedgerRoute(builder: (_) => const LedgerShell()));
  }

  Future<void> _digit(String d) async {
    if (_entered.length >= _pinLength || _success) return;
    setState(() {
      _wrong = false;
      _entered.write(d);
    });
    if (_entered.length < _pinLength) return;

    final ok = await ref
        .read(settingsRepoProvider)
        .checkPin(_entered.toString());
    if (!mounted) return;
    if (ok) {
      await _celebrateAndOpen();
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() => _wrong = true);
    if (Motion.reduced(context)) {
      await Future<void>.delayed(Motion.quick);
    } else {
      // The temper: the flush arrives fast and cools slowly, while the
      // head shakes it off. The cooling runs on while the next attempt is
      // already being typed — grudges fade, they don't blink off.
      unawaited(
        _anger.forward(from: 0).then((_) {
          if (mounted) _anger.reverse();
        }),
      );
      await _shake.forward(from: 0);
    }
    if (!mounted) return;
    setState(() => _entered.clear());
  }

  void _backspace() {
    if (_entered.isEmpty || _success) return;
    final s = _entered.toString();
    _entered.clear();
    _entered.write(s.substring(0, s.length - 1));
    setState(() {});
  }

  static String _dateLine() {
    final now = DateTime.now();
    return '${LedgerDates.weekdaysFull[now.weekday - 1]}, '
        '${now.day} ${LedgerDates.monthsFull[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final whisper = _whisper;
    final cover = Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(flex: 2),
            Text(
              'Krish Space',
              textAlign: TextAlign.center,
              style: LedgerType.wordmark.copyWith(fontSize: 28, color: c.ink),
            ),
            const SizedBox(height: Gap.x2),
            Text(
              "Krish's book · ${_dateLine()}",
              textAlign: TextAlign.center,
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
            if (whisper != null) ...[
              const SizedBox(height: Gap.x1),
              InkIn(
                child: Text(
                  whisper,
                  textAlign: TextAlign.center,
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12,
                    color: c.inkFaint.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
            const Spacer(flex: 2),
            if (_checked && _hasPin) _pinPad(c) else const SizedBox.shrink(),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );

    return cover;
  }

  /// The character, holding the middle of the cover — and wearing every
  /// mood the door puts it through. One merged listenable drives it all:
  /// the press dip, the angry flush (with its own head-shake), the wink.
  Widget _character(LedgerColors c, {required double width}) {
    return AnimatedBuilder(
      animation: Listenable.merge([_press, _anger, _wink, _shake]),
      builder: (context, _) {
        final dip = math.sin(_press.value * math.pi);
        final anger = _angerCurve.value;
        // Heat, not tint: ink → deep ember → vermilion, the way metal takes
        // colour. A straight lerp to the seal passed through a washed pink
        // on its way back down; routing through the ember keeps the cooling
        // warm to the last.
        const ember = Color(0xFFB2371F);
        final body = anger < 0.55
            ? Color.lerp(c.quill, ember, anger / 0.55)!
            : Color.lerp(ember, c.seal, (anger - 0.55) / 0.45)!;
        // The head-shake rides the same swing as the dots, scaled down —
        // one gesture, two places.
        final t = _shake.value;
        final dx = math.sin(t * math.pi * 5) * 7 * (1 - t);
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.scale(
            scale: 1 - 0.10 * dip,
            child: CustomPaint(
              size: Size(width, width * 0.82),
              painter: _MoodFacePainter(
                body: body,
                face: c.paper,
                anger: anger,
                wink: _wink.value,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pinPad(LedgerColors c) {
    // A wrong PIN is amber, not vermilion: the dots and their rims go warn
    // and only the one line of verdict wears the seal.
    final dotInk = _wrong ? c.warn : c.ink;
    final dotRim = _wrong ? c.warn : c.inkFaint;
    return Column(
      children: [
        // The character watches the door; on the right PIN it takes the
        // press while the dots and keypad fall quiet beneath it.
        _character(c, width: 84),
        const SizedBox(height: Gap.x6),
        AnimatedOpacity(
          duration: Motion.quick,
          opacity: _success ? 0 : 1,
          child: SizedBox(
            height: 46,
            child: AnimatedBuilder(
              animation: _shake,
              builder: (context, child) {
                // Three diminishing swings.
                final t = _shake.value;
                final dx = math.sin(t * math.pi * 5) * 14 * (1 - t);
                return Transform.translate(offset: Offset(dx, 0), child: child);
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pinLength; i++)
                        _PinDot(
                          filled: i < _entered.length,
                          ink: dotInk,
                          rim: dotRim,
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.x2),
                  SizedBox(
                    height: 16,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _wrong ? 1 : 0,
                      child: Text(
                        'Not it — try again',
                        style: LedgerType.bodyText.copyWith(
                          fontSize: 12,
                          color: c.seal,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.x4),
        AnimatedOpacity(
          duration: Motion.quick,
          opacity: _success ? 0.25 : 1,
          child: IgnorePointer(
            ignoring: _success,
            child: Column(
              children: [
                for (final row in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                ])
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final d in row) _key(c, d, () => _digit(d)),
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The slot Face ID used to hold. The book answers to
                    // its own PIN now — an empty space, not another key.
                    const SizedBox(width: 88, height: 66),
                    _key(c, '0', () => _digit('0')),
                    _key(c, '⌫', _backspace, faint: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// One keypad block — the ledger keypad's key, not a phone dialer's
  /// circle: a lifted block that visibly gives, with its own click.
  Widget _key(
    LedgerColors c,
    String label,
    VoidCallback onTap, {
    bool faint = false,
  }) {
    return _LockKey(label: label, onTap: onTap, faint: faint);
  }
}

/// A keypad key that answers the finger with light: the pressed numeral
/// catches the moonlight and the block warms under it, both fading as the
/// finger leaves — ink cooling after the stroke. The scale-give and the
/// click come from [Pressable]; this adds only the light.
class _LockKey extends StatefulWidget {
  const _LockKey({
    required this.label,
    required this.onTap,
    this.faint = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool faint;

  @override
  State<_LockKey> createState() => _LockKeyState();
}

class _LockKeyState extends State<_LockKey>
    with SingleTickerProviderStateMixin {
  // Starts settled at 1 — `lit` below is the *remaining* light, so a key
  // that has never been pressed must read fully cooled, not fully lit.
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  void _tap() {
    if (!Motion.reduced(context)) _glow.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Pressable(
        scale: 0.92,
        onTap: _tap,
        child: AnimatedBuilder(
          animation: _glow,
          builder: (context, _) {
            // Full light at the press, easing back to ink — never a step.
            final lit =
                1 - Curves.easeOutCubic.transform(_glow.value);
            final restInk = widget.faint ? c.inkFaint : c.ink;
            return Container(
              width: 78,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  c.quill.withValues(alpha: 0.14 * lit),
                  c.paperRaised,
                ),
                borderRadius: BorderRadius.circular(Corner.key),
              ),
              child: Text(
                widget.label,
                style: LedgerType.amount.copyWith(
                  fontSize: 20,
                  color: Color.lerp(restInk, c.quill, lit),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One PIN dot. Filling is a small pop — the digit lands on the page rather
/// than appearing on it.
class _PinDot extends StatefulWidget {
  const _PinDot({required this.filled, required this.ink, required this.rim});

  final bool filled;
  final Color ink;
  final Color rim;

  @override
  State<_PinDot> createState() => _PinDotState();
}

class _PinDotState extends State<_PinDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didUpdateWidget(_PinDot old) {
    super.didUpdateWidget(old);
    if (widget.filled && !old.filled && !Motion.reduced(context)) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, child) => Transform.scale(
        // Up and back down in one breath — a flash, never a bounce.
        scale: 1 + math.sin(_pop.value * math.pi) * 0.4,
        child: child,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Motion.curve,
        width: 11,
        height: 11,
        margin: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.filled ? widget.ink : null,
          border: Border.all(color: widget.rim, width: 1.2),
        ),
      ),
    );
  }
}

/// The character's face with a temper and a wink — the splash's
/// [MarkFacePainter] geometry, given moods. [anger] flushes the slab toward
/// the seal (the caller lerps the colour), slides angry brows down over the
/// eyes, tilts the eyes inward and flattens the smile into a flat line of
/// disapproval. [wink] completes the wink the left eye was always halfway
/// through: it closes into a contented arc, holds, and opens again, the
/// smile widening a touch while it's shut. Both are 0..1 and compose.
class _MoodFacePainter extends CustomPainter {
  const _MoodFacePainter({
    required this.body,
    required this.face,
    required this.anger,
    required this.wink,
  });

  final Color body;
  final Color face;
  final double anger;
  final double wink;

  /// The wink's envelope: shut quickly, hold shut, open with ease.
  double get _shut {
    if (wink <= 0) return 0;
    if (wink < 0.35) return Curves.easeOutCubic.transform(wink / 0.35);
    if (wink < 0.65) return 1;
    return 1 - Curves.easeInOutCubic.transform((wink - 0.65) / 0.35);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // The folder-book slab, exactly as the splash draws it.
    final tabTop = h * 0.06;
    final bodyTop = h * 0.24;
    final r = w * 0.10;
    final slab = Path()
      ..moveTo(w * 0.04, h - r)
      ..lineTo(w * 0.04, tabTop + r)
      ..arcToPoint(Offset(w * 0.04 + r, tabTop), radius: Radius.circular(r))
      ..lineTo(w * 0.34, tabTop)
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
    final shut = _shut;
    // Angry eyes tilt their tops toward each other — a glare, not a stare.
    final tilt = w * 0.025 * anger;

    // Left eye: the bar with the curled foot, mid-wink by nature. The wink
    // finishes the job — the bar sinks into its own curl until only a
    // contented closed arc remains.
    if (shut < 0.95) {
      final top = eyeTop + (eyeBottom - h * 0.075 - eyeTop) * shut;
      final left = Path()
        ..moveTo(w * 0.34 + tilt, top)
        ..lineTo(w * 0.34, eyeBottom - h * 0.045)
        ..arcToPoint(
          Offset(w * 0.27, eyeBottom - h * 0.045),
          radius: Radius.circular(w * 0.045),
          clockwise: true,
        );
      canvas.drawPath(left, pen);
    } else {
      // Fully shut: one downward bow — the eye smiling on its own.
      final arc = Path()
        ..moveTo(w * 0.26, eyeBottom - h * 0.05)
        ..quadraticBezierTo(
          w * 0.335,
          eyeBottom + h * 0.015,
          w * 0.41,
          eyeBottom - h * 0.05,
        );
      canvas.drawPath(arc, pen);
    }

    // Right eye: straight, a touch taller — the one paying attention. It
    // stays open through the wink (that is what makes it a wink).
    canvas.drawLine(
      Offset(w * 0.62 - tilt, eyeTop - h * 0.03),
      Offset(w * 0.62, eyeBottom),
      pen,
    );

    // The brows arrive only with temper: two strokes sliding down and in,
    // fading in with the flush.
    if (anger > 0.01) {
      final brow = Paint()
        ..color = face.withValues(alpha: anger.clamp(0.0, 1.0))
        ..strokeWidth = w * 0.055
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final drop = h * 0.05 * (1 - anger);
      canvas.drawLine(
        Offset(w * 0.235, h * 0.345 - drop),
        Offset(w * 0.375, h * 0.405 - drop),
        brow,
      );
      canvas.drawLine(
        Offset(w * 0.715, h * 0.345 - drop),
        Offset(w * 0.575, h * 0.405 - drop),
        brow,
      );
    }

    // The mouth: a too-wide smile that widens further while the wink holds,
    // and flattens to a hard line as the temper rises.
    final widen = w * 0.015 * shut;
    final smileCtrlY = h * (0.92 + 0.04 * shut);
    final ctrlY = smileCtrlY + (h * 0.60 - smileCtrlY) * anger;
    final endY = h * (0.74 - 0.045 * anger);
    final mouth = Path()
      ..moveTo(w * 0.30 - widen, endY)
      ..quadraticBezierTo(w * 0.48, ctrlY, w * 0.68 + widen, endY - h * 0.01);
    canvas.drawPath(mouth, pen);
  }

  @override
  bool shouldRepaint(_MoodFacePainter old) =>
      old.body != body ||
      old.face != face ||
      old.anger != anger ||
      old.wink != wink;
}
