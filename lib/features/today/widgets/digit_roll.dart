import 'package:flutter/material.dart';

import '../../../core/inr.dart';
import '../../../core/tokens.dart';
import '../../../core/widgets/motion.dart';

/// The hero figure as an odometer: each digit rolls to its new value on its
/// own tape — up when money lands, down when a line is struck — with the
/// units digit leading and the rest following a breath behind. First build
/// renders settled: the page opens written, it does not perform.
class DigitRoll extends StatefulWidget {
  const DigitRoll({
    super.key,
    required this.paise,
    required this.style,
    this.text,
    this.duration = const Duration(milliseconds: 380),
    this.staggerPerDigit = const Duration(milliseconds: 24),
  });

  final int paise;

  /// What to print, when the caller knows better than [Inr.format] — the
  /// add keypad passes the figure exactly as typed so a fresh decimal
  /// point shows up the moment it is pressed. Null formats [paise].
  final String? text;

  /// Digit slots size themselves to each digit's own advance and animate
  /// between widths as the tape turns, so proportional figures (a narrow 1
  /// beside a round 0) sit tight with no gaps.
  final TextStyle style;
  final Duration duration;
  final Duration staggerPerDigit;

  @override
  State<DigitRoll> createState() => _DigitRollState();
}

class _DigitRollState extends State<DigitRoll> {
  /// Which way the tapes turn: set from the sign of the change, so an added
  /// entry rolls the figure up and a struck one rolls it back down.
  int _dir = 1;

  @override
  void didUpdateWidget(DigitRoll old) {
    super.didUpdateWidget(old);
    if (old.paise != widget.paise) {
      _dir = widget.paise >= old.paise ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text ?? Inr.format(widget.paise);
    if (Motion.reduced(context)) return Text(text, style: widget.style);

    final scaler = MediaQuery.textScalerOf(context);
    double h = 0;
    final widths = List<double>.generate(10, (d) {
      final tp = TextPainter(
        text: TextSpan(text: '$d', style: widget.style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      if (tp.height > h) h = tp.height;
      return tp.width;
    });
    final c = LedgerColors.of(context);

    // Cells are keyed by their distance from the units column — which sits
    // just left of the decimal point when one exists. Keyed this way, the
    // integer digits keep their tapes both when the figure grows a digit
    // (₹999 → ₹1,000) and when a point lands behind them (₹120 → ₹120.):
    // fractional slots take negative keys of their own.
    final n = text.length;
    final dot = text.indexOf('.');
    final units = dot < 0 ? n : dot;
    final cells = <Widget>[
      for (var i = 0; i < n; i++)
        _cell(text[i], units - 1 - i, widths, h, c.paper),
    ];

    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(mainAxisSize: MainAxisSize.min, children: cells),
        ),
      ),
    );
  }

  Widget _cell(
    String ch,
    int fromRight,
    List<double> widths,
    double h,
    Color paper,
  ) {
    final code = ch.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39) {
      return _RollCell(
        key: ValueKey('d$fromRight'),
        digit: code - 0x30,
        dir: _dir,
        delay: widget.staggerPerDigit * fromRight.abs(),
        duration: widget.duration,
        style: widget.style,
        widths: widths,
        height: h,
        paper: paper,
      );
    }
    // ₹, the separators, the point: they don't roll — when a slot's glyph
    // changes (a comma arriving as the figure grows) it crossfades.
    return SizedBox(
      key: ValueKey('c$fromRight'),
      height: h,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: Text(ch, key: ValueKey(ch), style: widget.style),
      ),
    );
  }
}

/// One digit's window onto its tape. The position is continuous, so a roll
/// interrupted by another change retargets from wherever the tape stands —
/// no snap, no restart.
class _RollCell extends StatefulWidget {
  const _RollCell({
    super.key,
    required this.digit,
    required this.dir,
    required this.delay,
    required this.duration,
    required this.style,
    required this.widths,
    required this.height,
    required this.paper,
  });

  final int digit;
  final int dir;
  final Duration delay;
  final Duration duration;
  final TextStyle style;

  /// Advance width of each digit 0–9 in the current style.
  final List<double> widths;
  final double height;
  final Color paper;

  @override
  State<_RollCell> createState() => _RollCellState();
}

class _RollCellState extends State<_RollCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  /// Tape positions: the shown glyph is `pos % 10`. First build settles
  /// immediately — from == to, controller never runs.
  late double _from = widget.digit.toDouble();
  late double _to = widget.digit.toDouble();

  /// The slot's width rides the same curve as the tape, so a narrow 1
  /// widening into a 0 never leaves a gap or a jump.
  late double _wFrom = widget.widths[widget.digit];
  late double _wTo = widget.widths[widget.digit];

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: widget.delay + widget.duration,
    );
  }

  double get _delayFrac {
    final total = (widget.delay + widget.duration).inMilliseconds;
    return total == 0 ? 0 : widget.delay.inMilliseconds / total;
  }

  double get _t => _delayFrac >= 1
      ? 1.0
      : Interval(
          _delayFrac,
          1,
          curve: Curves.easeOutCubic,
        ).transform(_ac.value);

  double get _pos => _from + (_to - _from) * _t;

  double get _width => _wFrom + (_wTo - _wFrom) * _t;

  @override
  void didUpdateWidget(_RollCell old) {
    super.didUpdateWidget(old);
    if (old.digit != widget.digit) {
      _retarget();
    } else if (!_ac.isAnimating && widget.widths[widget.digit] != _wTo) {
      // Style or scale changed while settled: take the new width plainly.
      _wFrom = _wTo = widget.widths[widget.digit];
    }
  }

  void _retarget() {
    final cur = _pos;
    // Nearest occurrence of the target digit strictly in the direction of
    // the change — so 9→0 wraps forward and 0→9 wraps back, never the long
    // way round.
    final double target;
    if (widget.dir >= 0) {
      final base = cur.ceilToDouble();
      target = base + ((widget.digit - (base % 10).round()) % 10);
    } else {
      final base = cur.floorToDouble();
      target = base - (((base % 10).round() - widget.digit) % 10);
    }
    if (target == cur) return;
    _wFrom = _width;
    _wTo = widget.widths[widget.digit];
    _from = cur;
    _to = target;
    _ac.forward(from: 0);
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    return AnimatedBuilder(
      animation: _ac,
      builder: (context, _) {
        final p = _pos;
        final base = p.floorToDouble();
        final frac = p - base;
        final d0 = (base % 10).round() % 10;
        final d1 = (d0 + 1) % 10;
        final rolling = _ac.isAnimating;
        return ClipRect(
          child: SizedBox(
            width: _width,
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -frac * h,
                  left: 0,
                  right: 0,
                  child: Center(child: Text('$d0', style: widget.style)),
                ),
                if (frac > 0)
                  Positioned(
                    top: (1 - frac) * h,
                    left: 0,
                    right: 0,
                    child: Center(child: Text('$d1', style: widget.style)),
                  ),
                // The window's soft edges — only while the tape turns, so a
                // settled digit sits as plain ink like its neighbours.
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: rolling ? 1 : 0,
                      child: Column(
                        children: [
                          _edge(top: true),
                          const Spacer(),
                          _edge(top: false),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _edge({required bool top}) {
    return Container(
      height: widget.height * 0.14,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [
            widget.paper.withValues(alpha: 0.9),
            widget.paper.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
