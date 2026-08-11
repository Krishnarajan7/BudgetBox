import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The motion kit. Every screen draws from these so the whole book moves
/// with one hand: things press, numbers settle, lines ink in, charts draw
/// themselves, pages turn. Nothing bounces; nothing celebrates without cause.

/// The book's one hand: a single gentle spring for everything that moves.
abstract final class Motion {
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration spring = Duration(milliseconds: 250);
  static const Duration settle = Duration(milliseconds: 550);
  static const Duration draw = Duration(milliseconds: 700);
  static const Curve curve = Curves.easeOutCubic;

  /// True when the system asks for reduced motion — every entrance and
  /// flourish in the kit collapses to an instant render.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Pushes the next screen like a page turning, not a Material zoom: the new
/// page fades in and rises a hair on the book's one spring.
class LedgerRoute<T> extends PageRouteBuilder<T> {
  LedgerRoute({required WidgetBuilder builder, super.fullscreenDialog})
      : super(
          transitionDuration: Motion.spring,
          reverseTransitionDuration: Motion.quick,
          pageBuilder: (context, anim, secondary) => builder(context),
          transitionsBuilder: (context, anim, _, child) {
            final eased =
                CurvedAnimation(parent: anim, curve: Motion.curve);
            return FadeTransition(
              opacity: eased,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.015),
                  end: Offset.zero,
                ).animate(eased),
                child: child,
              ),
            );
          },
        );
}

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
    if (Motion.reduced(context)) {
      return Text(widget.format(widget.value), style: widget.style);
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.value),
      tween: Tween(begin: _from.toDouble(), end: widget.value.toDouble()),
      duration: widget.duration,
      curve: Motion.curve,
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
    if (Motion.reduced(context)) return widget.child;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      opacity: _shown ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 260),
        curve: Motion.curve,
        offset: _shown ? Offset.zero : const Offset(0, 0.12),
        child: widget.child,
      ),
    );
  }
}

/// Reveals its child left-to-right, like a pen stroke crossing the line.
/// Give it an [animation] to drive it, or leave it to drive itself once on
/// entry after [delay].
class InkReveal extends StatefulWidget {
  const InkReveal({
    super.key,
    required this.child,
    this.animation,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
  });

  final Widget child;
  final Animation<double>? animation;
  final Duration delay;
  final Duration duration;

  @override
  State<InkReveal> createState() => _InkRevealState();
}

class _InkRevealState extends State<InkReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _own;

  @override
  void initState() {
    super.initState();
    if (widget.animation == null) {
      _own = AnimationController(vsync: this, duration: widget.duration);
      Future<void>.delayed(widget.delay, () {
        if (!mounted) return;
        if (Motion.reduced(context)) {
          _own!.value = 1;
        } else {
          _own!.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = widget.animation ??
        CurvedAnimation(parent: _own!, curve: const Cubic(0.6, 0, 0.2, 1));
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) => ClipRect(
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: anim.value == 0 ? 0.001 : anim.value,
          child: widget.child,
        ),
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
    if (Motion.reduced(context)) return builder(context, 1);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Motion.curve,
      builder: (context, v, _) => builder(context, v),
    );
  }
}
