import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/pen_marks.dart';
import '../../data/providers.dart';
import '../lock/lock_page.dart';
import '../setup/setup_flow.dart';

/// The opening of the book: the character settles onto the lacquer — a
/// press-down with the stamp's slight overshoot, nothing zooming anywhere —
/// and one line says whose space this is. ~1.2s, once per cold launch,
/// tap-to-skip, collapsed to a beat when animations are off.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  /// The character arriving: pressed down onto the page, seats with a
  /// slight overshoot — the same hand that stamps the seal.
  late final Animation<double> _seat;

  /// The slogan, inking in underneath once the character has landed.
  late final Animation<double> _line;

  static const _total = Duration(milliseconds: 1250);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _total);
    _seat = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.08, 0.42, curve: Cubic(0.2, 1.4, 0.4, 1)),
    );
    _line = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.48, 0.72, curve: Curves.easeOut),
    );

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
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _seat,
                builder: (context, child) {
                  final t = _seat.value;
                  return Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    // Settles DOWN onto the page — pressed, not zoomed.
                    child: Transform.scale(
                      scale: 1.25 - 0.25 * t,
                      child: child,
                    ),
                  );
                },
                child: MarkFace(width: 132, body: c.quill, face: c.paper),
              ),
              const SizedBox(height: Gap.x6),
              AnimatedBuilder(
                animation: _line,
                builder: (context, child) => Opacity(
                  opacity: _line.value,
                  child: Transform.translate(
                    offset: Offset(0, 6 * (1 - _line.value)),
                    child: child,
                  ),
                ),
                child: Text(
                  'made for Krish · population, one',
                  style: LedgerType.bodyText
                      .copyWith(fontSize: 13, color: c.inkFaint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
