import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/seal.dart';
import '../../data/providers.dart';
import '../lock/lock_page.dart';
import '../setup/setup_flow.dart';

/// The opening of the book: ruled paper fades in, the wordmark inks itself
/// across the line, the byline settles, the seal stamps. ~2.1s, once per cold
/// launch, tap-to-skip, and collapsed to a beat when animations are off.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  late final Animation<double> _inkReveal;
  late final Animation<double> _byline;
  late final Animation<double> _stamp;

  static const _total = Duration(milliseconds: 2100);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _total);

    Animation<double> span(double a, double b, [Curve curve = Curves.easeOut]) =>
        CurvedAnimation(
          parent: _c,
          curve: Interval(a, b, curve: curve),
        );

    _inkReveal = span(0.10, 0.53, const Cubic(0.6, 0, 0.2, 1));
    _byline = span(0.53, 0.71);
    _stamp = span(0.76, 0.90, const Cubic(0.2, 1.6, 0.4, 1));

    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed) _open();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final reduced = MediaQuery.of(context).disableAnimations;
      if (reduced) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  Future<void> _open() async {
    if (!mounted) return;
    // A truly blank book gets the setup ritual; every other launch, the lock.
    final settings = ref.read(settingsRepoProvider);
    final accountRepo = ref.read(accountRepoProvider);
    final firstLaunch =
        !await settings.setupDone() && !await accountRepo.hasAny();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) =>
            firstLaunch ? const SetupFlow(real: true) : const LockPage(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        _c.value = 1;
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkReveal(
                    animation: _inkReveal,
                    child: Text(
                      'BudgetBox',
                      style: LedgerType.heroAmount.copyWith(
                        fontSize: 40,
                        color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.x3),
                  FadeTransition(
                    opacity: _byline,
                    child: AnimatedBuilder(
                      animation: _byline,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, 6 * (1 - _byline.value)),
                        child: child,
                      ),
                      child: Text(
                        "Krish's book · since July 2026",
                        style: LedgerType.bodyText.copyWith(
                          fontSize: 13,
                          color: c.inkFaint,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.x8),
                  AnimatedBuilder(
                    animation: _stamp,
                    builder: (context, child) {
                      final v = _stamp.value;
                      if (v == 0) return const SizedBox(height: 44);
                      return Transform.rotate(
                        // Settles from +4° through the overshoot into the
                        // seal's resting −5° (applied by [Seal] itself).
                        angle: 9 * (1 - v) * 3.14159 / 180,
                        child: Transform.scale(
                          scale: 1.7 - 0.7 * v,
                          child: Opacity(
                            opacity: v.clamp(0, 1),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: const Seal(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

