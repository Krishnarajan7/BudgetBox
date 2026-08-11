import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import 'motion.dart';
import 'pen_marks.dart';

/// The vermilion chop-mark. The app's only celebration.
class Seal extends StatelessWidget {
  const Seal({super.key, this.size = 44, this.child});

  final double size;

  /// Defaults to a check mark scaled to the seal.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Transform.rotate(
      angle: -5 * 3.14159 / 180,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: c.seal, width: size * 0.055 + 1.2),
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
        alignment: Alignment.center,
        child: child ??
            PenTick(size: size * 0.48, color: c.seal),
      ),
    );
  }
}

/// The seal pressing onto the page: it lands from above the paper — scale
/// settles, ink darkens on contact — with one firm haptic. Used the moment
/// something is worth stamping (a save, a closed day, a finished setup).
class StampIn extends StatefulWidget {
  const StampIn({
    super.key,
    this.size = 44,
    this.child,
    this.delay = Duration.zero,
    this.haptic = true,
    this.onStamped,
  });

  final double size;
  final Widget? child;
  final Duration delay;
  final bool haptic;
  final VoidCallback? onStamped;

  @override
  State<StampIn> createState() => _StampInState();
}

class _StampInState extends State<StampIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      if (Motion.reduced(context)) {
        _c.value = 1;
        _land();
      } else {
        _c.forward();
        _c.addStatusListener((s) {
          if (s == AnimationStatus.completed) _land();
        });
      }
    });
  }

  void _land() {
    if (_landed) return;
    _landed = true;
    if (widget.haptic) HapticFeedback.mediumImpact();
    widget.onStamped?.call();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.scale(scale: 1.55 - 0.55 * t, child: child),
        );
      },
      child: Seal(size: widget.size, child: widget.child),
    );
  }
}
