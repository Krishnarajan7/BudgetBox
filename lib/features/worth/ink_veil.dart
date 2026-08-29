import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/widgets/motion.dart';

/// The veil: every digit of a figure flips into a masking character —
/// left to right, one after the next, cycling through a few random glyphs
/// before it settles, the way a split-flap board turns over. Unveiling runs
/// the same wave back until the true digits stand again.
///
/// Rules that keep it honest and calm:
/// * only digits scramble — the ₹, commas and the point hold still, so a
///   veiled figure still reads as *money*, just not as an amount;
/// * each slot keeps the width of the digit it hides, so the row never
///   shifts a pixel while the tiles turn;
/// * the resting mask is seeded per slot — the same figure veils to the
///   same characters every time, no shimmer at rest;
/// * a screen reader hears 'hidden', never the number.
///
/// Chosen with eyes open: masking per digit keeps the figure's *length*
/// visible. That is the trade for the flip being legible as "this exact
/// number, covered" rather than a generic redaction.
class InkVeil extends StatefulWidget {
  const InkVeil({
    super.key,
    required this.veiled,
    required this.text,
    required this.style,
    this.child,
    this.order = 0,
  });

  final bool veiled;

  /// The true figure, e.g. '₹1,23,456.78'. The scramble is built from it.
  final String text;

  /// How the figure is set — including its color: the tiles wear it too.
  final TextStyle style;

  /// What stands when the veil is fully open. Defaults to [text] in
  /// [style]; the hero passes its rolling odometer, rows their settling
  /// counts — the moment the wave starts they are swapped for still glyphs
  /// of the same string, which is indistinguishable.
  final Widget? child;

  /// This figure's place in the cascade down the page.
  final int order;

  @override
  State<InkVeil> createState() => _InkVeilState();
}

class _InkVeilState extends State<InkVeil>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t;

  /// What the current run is heading toward. The reveal is not the hide
  /// played backwards — both run left to right, so each direction is its
  /// own forward pass.
  late bool _towardVeiled = widget.veiled;

  int _generation = 0;

  static const _stagger = Duration(milliseconds: 34);

  /// One tile's full turn, and the lag between neighbouring tiles.
  static const _turnMs = 240;
  static const _lagMs = 45;

  /// What a digit settles as. No digits, nothing that reads as one — and
  /// nothing wider or heavier than a digit: the first set (×+*#§?%&) mixed
  /// glyph widths and weights, so masks bled into their neighbours and a
  /// veiled figure read as a scribble rather than a covered number. These
  /// four are digit-narrow and of one visual weight.
  static const _masks = '×+*÷';

  /// What a digit may flash mid-spin — a little wilder than the resting
  /// set, because motion forgives what stillness would not. Each cell is
  /// width-clamped regardless, so even these can never overlap.
  static const _spins = '×+*÷#?';

  @override
  void initState() {
    super.initState();
    _t = AnimationController(vsync: this, value: 1);
    // The settled-vs-animating branch is chosen in build(), and finishing a
    // wave schedules no build of its own — without this, the veil stayed on
    // its per-glyph tiles forever after the first run: right-looking, but
    // the odometer never came back and the figure stopped speaking.
    _t.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
    _resize();
  }

  void _resize() {
    final digits = widget.text.runes.where(_isDigit).length;
    _t.duration = Duration(
      milliseconds: _turnMs + _lagMs * math.max(0, digits - 1),
    );
  }

  static bool _isDigit(int rune) => rune >= 0x30 && rune <= 0x39;

  @override
  void didUpdateWidget(InkVeil old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _resize();
    if (old.veiled == widget.veiled) return;
    final gen = ++_generation;
    _towardVeiled = widget.veiled;
    if (Motion.reduced(context)) {
      _t.value = 1;
      return;
    }
    Future.delayed(_stagger * widget.order, () {
      if (!mounted || gen != _generation) return;
      _t.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  /// The resting mask for slot [i] — stable per figure and position.
  String _maskFor(int i) =>
      _masks[(widget.text.length * 31 + i * 7 + widget.order) % _masks.length];

  /// A mid-turn glyph: pseudo-random per slot and tick, digits excluded.
  String _spin(int slot, int tick) =>
      _spins[(slot * 13 + tick * 5 + widget.order * 3) % _spins.length];

  /// Every state carries its own semantics node (`container: true`), so
  /// what a screen reader hears never depends on how ancestors happen to
  /// merge: an open figure reads as its amount, a veiled one as 'hidden'.
  Widget _spoken(String label, Widget child) => Semantics(
    label: label,
    container: true,
    child: ExcludeSemantics(child: child),
  );

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) {
      return widget.veiled
          ? _spoken('hidden', _still(masked: true))
          : _spoken(widget.text, widget.child ?? _still(masked: false));
    }

    final settled = !_t.isAnimating && _t.value == 1;
    // Fully open and at rest: the live figure (odometer and all).
    if (settled && !_towardVeiled) {
      return _spoken(widget.text, widget.child ?? _still(masked: false));
    }
    // Fully veiled and at rest: still masks, no animation machinery.
    if (settled && _towardVeiled) {
      return _spoken('hidden', _still(masked: true));
    }

    final row = AnimatedBuilder(
      animation: _t,
      builder: (context, _) => _tiles(context),
    );
    return _spoken(_towardVeiled ? 'hidden' : widget.text, row);
  }

  /// The whole figure as still text, masked or plain.
  Widget _still({required bool masked}) {
    if (!masked) return Text(widget.text, style: widget.style);
    final out = StringBuffer();
    var slot = 0;
    for (final rune in widget.text.runes) {
      out.write(_isDigit(rune) ? _maskFor(slot++) : String.fromCharCode(rune));
    }
    return _FixedSlots(
      truth: widget.text,
      shown: out.toString(),
      style: widget.style,
    );
  }

  /// The wave, mid-turn. Each digit slot has its own window on the clock:
  /// slot k turns during [k*lag, k*lag + turn], cycling a few characters
  /// before settling — on its mask going under, on its digit coming back.
  Widget _tiles(BuildContext context) {
    final total = _t.duration!.inMilliseconds;
    final now = _t.value * total;
    final out = StringBuffer();
    var slot = 0;
    for (final rune in widget.text.runes) {
      if (!_isDigit(rune)) {
        out.write(String.fromCharCode(rune));
        continue;
      }
      final local = (now - slot * _lagMs) / _turnMs;
      final String glyph;
      if (local <= 0) {
        // Its turn has not come: still showing what it was.
        glyph = _towardVeiled ? String.fromCharCode(rune) : _maskFor(slot);
      } else if (local >= 1) {
        glyph = _towardVeiled ? _maskFor(slot) : String.fromCharCode(rune);
      } else {
        // Mid-turn: the reel spins — a fresh face roughly every 50ms.
        glyph = _spin(slot, (local * 5).floor());
      }
      out.write(glyph);
      slot++;
    }
    return _FixedSlots(
      truth: widget.text,
      shown: out.toString(),
      style: widget.style,
    );
  }
}

/// Prints [shown] with each glyph centred in the width its counterpart in
/// [truth] occupies — so however the reels spin, the figure's edges hold
/// perfectly still.
class _FixedSlots extends StatelessWidget {
  const _FixedSlots({
    required this.truth,
    required this.shown,
    required this.style,
  });

  final String truth;
  final String shown;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final trueGlyphs = truth.runes
        .map(String.fromCharCode)
        .toList(growable: false);
    final shownGlyphs = shown.runes
        .map(String.fromCharCode)
        .toList(growable: false);
    final cells = <Widget>[];
    for (var i = 0; i < trueGlyphs.length && i < shownGlyphs.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: trueGlyphs[i], style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      cells.add(
        SizedBox(
          width: tp.width,
          child: FittedBox(
            // The hard guarantee against overlap: a glyph wider than the
            // digit it stands in for is scaled to the slot, never allowed
            // to lean on its neighbour.
            fit: BoxFit.scaleDown,
            child: Text(
              shownGlyphs[i],
              style: style,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
      );
    }
    // Scales down exactly as the open figure would in a bounded slot (the
    // hero's odometer lives in a FittedBox too) — parity either way.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: cells),
    );
  }
}

/// The eye that actually blinks. On toggle the lid closes — the icon swaps
/// while shut — and opens again, so the change of state reads as the gesture
/// it is instead of one glyph teleporting into another.
class BlinkingEye extends StatefulWidget {
  const BlinkingEye({
    super.key,
    required this.veiled,
    required this.color,
    this.size = 19,
  });

  final bool veiled;
  final Color color;
  final double size;

  @override
  State<BlinkingEye> createState() => _BlinkingEyeState();
}

class _BlinkingEyeState extends State<BlinkingEye>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
  );

  @override
  void didUpdateWidget(BlinkingEye old) {
    super.didUpdateWidget(old);
    if (old.veiled != widget.veiled && !Motion.reduced(context)) {
      _blink.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) {
        final t = _blink.value;
        // The lid: shut fastest at the middle of the blink.
        final lid = 1 - math.sin(t * math.pi) * 0.92;
        // The icon swaps while the eye is shut, never in the open.
        final showVeiled = t >= 0.5
            ? widget.veiled
            : (_blink.isAnimating ? !widget.veiled : widget.veiled);
        return Transform.scale(
          scaleY: lid,
          child: Icon(
            showVeiled
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: widget.size,
            color: widget.color,
          ),
        );
      },
    );
  }
}
