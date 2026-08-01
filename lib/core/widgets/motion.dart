import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The motion kit. Every screen draws from these four so the whole book
/// moves with one hand: things press, numbers settle, lines ink in, charts
/// draw themselves. Nothing bounces; nothing celebrates without cause.

/// Universal press affordance: anything tappable visibly gives.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.haptic = true,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _down = false);
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A number that settles instead of snapping: whenever [value] changes, the
/// shown figure glides from the old one. Give it tabular text or it will
/// jitter — that's the caller's contract.
class CountUp extends StatefulWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.format,
    required this.style,
    this.duration = const Duration(milliseconds: 550),
  });

  final int value;
  final String Function(int) format;
  final TextStyle style;
  final Duration duration;

  @override
  State<CountUp> createState() => _CountUpState();
}

class _CountUpState extends State<CountUp> {
  late int _from = widget.value;

  @override
  void didUpdateWidget(CountUp old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _from = old.value;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.value),
      tween: Tween(begin: _from.toDouble(), end: widget.value.toDouble()),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) =>
          Text(widget.format(v.round()), style: widget.style),
    );
  }
}

/// A line inking itself onto the page: fade + a small rise, once, on entry.
/// [delay] staggers siblings so lists write themselves top to bottom.
class InkIn extends StatefulWidget {
  const InkIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.play = true,
  });

  final Widget child;
  final Duration delay;

  /// False renders instantly — for rows that were already on the page.
  final bool play;

  @override
  State<InkIn> createState() => _InkInState();
}

class _InkInState extends State<InkIn> {
  late bool _shown = !widget.play;

  @override
  void initState() {
    super.initState();
    if (widget.play) {
      Future<void>.delayed(widget.delay, () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      opacity: _shown ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        offset: _shown ? Offset.zero : const Offset(0, 0.12),
        child: widget.child,
      ),
    );
  }
}

/// Hands its child a 0→1 draw progress on first build — charts use it to
/// draw themselves rather than appear.
class DrawIn extends StatelessWidget {
  const DrawIn({
    super.key,
    required this.builder,
    this.duration = const Duration(milliseconds: 700),
  });

  final Widget Function(BuildContext, double progress) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => builder(context, v),
    );
  }
}
