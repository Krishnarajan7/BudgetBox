import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/seal.dart';
import '../../data/providers.dart';
import '../shell/shell.dart';

/// The book's cover. Face ID fires on arrival when a PIN exists; the PIN pad
/// is the fallback. A wrong PIN shakes and flashes the seal red; the right
/// one turns the dots jama, stamps the chop, and the book opens through it.
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

  late final AnimationController _shake;
  late final AnimationController _stamp;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _stamp = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _prepare();
  }

  @override
  void dispose() {
    _shake.dispose();
    _stamp.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final settings = ref.read(settingsRepoProvider);
    final hasPin = await settings.hasPin();
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _checked = true;
    });
    if (hasPin) _tryBiometrics();
  }

  Future<void> _tryBiometrics() async {
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return;
      final ok = await auth.authenticate(
        localizedReason: 'Open your book',
        biometricOnly: true,
      );
      if (ok && mounted) _celebrateAndOpen();
    } catch (_) {
      // No biometrics here (simulator, desktop, tests) — the PIN pad is
      // the door.
    }
  }

  /// Success is a moment: dots turn jama, the chop stamps with a thud, and
  /// the shell fades up through the cover.
  Future<void> _celebrateAndOpen() async {
    if (_success) return;
    setState(() => _success = true);
    HapticFeedback.mediumImpact();
    await _stamp.forward();
    HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) => const LedgerShell(),
        transitionsBuilder: (_, anim, _, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.015),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _digit(String d) async {
    if (_entered.length >= 4 || _success) return;
    HapticFeedback.selectionClick();
    setState(() {
      _wrong = false;
      _entered.write(d);
    });
    if (_entered.length == 4) {
      final ok =
          await ref.read(settingsRepoProvider).checkPin(_entered.toString());
      if (!mounted) return;
      if (ok) {
        await _celebrateAndOpen();
      } else {
        HapticFeedback.heavyImpact();
        setState(() => _wrong = true);
        await _shake.forward(from: 0);
        if (!mounted) return;
        setState(() => _entered.clear());
      }
    }
  }

  void _backspace() {
    if (_entered.isEmpty || _success) return;
    HapticFeedback.selectionClick();
    final s = _entered.toString();
    _entered.clear();
    _entered.write(s.substring(0, s.length - 1));
    setState(() {});
  }

  static String _dateLine() {
    final now = DateTime.now();
    const w = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const m = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${w[now.weekday - 1]}, ${now.day} ${m[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final cover = Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(flex: 2),
            Text(
              'BudgetBox',
              textAlign: TextAlign.center,
              style: LedgerType.wordmark.copyWith(fontSize: 28, color: c.ink),
            ),
            const SizedBox(height: Gap.x2),
            Text(
              "Krish's book · ${_dateLine()}",
              textAlign: TextAlign.center,
              style: LedgerType.bodyText
                  .copyWith(fontSize: 13, color: c.inkFaint),
            ),
            const Spacer(flex: 3),
            if (!_checked)
              const SizedBox.shrink()
            else if (!_hasPin)
              _noPinYet(c)
            else
              _pinPad(c),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );

    // With no PIN, the whole cover is the handle.
    if (_checked && !_hasPin) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _celebrateAndOpen,
        child: cover,
      );
    }
    return cover;
  }

  /// Until a PIN exists (setup ritual or Settings), the cover just opens —
  /// under Krish's own chop-mark.
  Widget _noPinYet(LedgerColors c) {
    return Column(
      children: [
        _chop(c),
        const SizedBox(height: Gap.x4),
        Text(
          'Tap to open the book',
          style:
              LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
        ),
        const SizedBox(height: Gap.x1),
        Text(
          'No lock set yet — add one in Settings',
          style: LedgerType.bodyText.copyWith(
            fontSize: 11,
            color: c.inkFaint.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _chop(LedgerColors c) {
    return Seal(
      size: 52,
      child: Text(
        'K',
        style: LedgerType.wordmark.copyWith(fontSize: 24, color: c.seal),
      ),
    );
  }

  Widget _pinPad(LedgerColors c) {
    return Column(
      children: [
        // Success replaces the dots with the stamping chop; otherwise the
        // dots, which shake as one piece on a wrong PIN.
        SizedBox(
          height: 64,
          child: _success
              ? AnimatedBuilder(
                  animation: _stamp,
                  builder: (context, child) {
                    final v = Curves.easeOutBack.transform(_stamp.value);
                    return Opacity(
                      opacity: _stamp.value.clamp(0, 1),
                      child: Transform.rotate(
                        angle: 6 * (1 - v) * math.pi / 180,
                        child: Transform.scale(
                            scale: 1.6 - 0.6 * v, child: child),
                      ),
                    );
                  },
                  child: Center(child: _chop(c)),
                )
              : AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) {
                    // Three diminishing swings.
                    final t = _shake.value;
                    final dx = math.sin(t * math.pi * 5) * 14 * (1 - t);
                    return Transform.translate(
                        offset: Offset(dx, 0), child: child);
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 4; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              curve: Curves.easeOut,
                              width: 11,
                              height: 11,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 7),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < _entered.length
                                    ? (_wrong ? c.seal : c.ink)
                                    : null,
                                border: Border.all(
                                  color: _wrong ? c.seal : c.inkFaint,
                                  width: 1.2,
                                ),
                              ),
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
                            style: LedgerType.bodyText
                                .copyWith(fontSize: 12, color: c.seal),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: Gap.x4),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
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
                      for (final d in row) _key(c, d, () => _digit(d))
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _key(c, '', _tryBiometrics, icon: Icons.face_outlined),
                    _key(c, '0', () => _digit('0')),
                    _key(c, '', _backspace,
                        icon: Icons.backspace_outlined),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _key(LedgerColors c, String label, VoidCallback onTap,
      {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: _PressScale(
        onTap: onTap,
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.rule),
          ),
          child: icon != null
              ? Icon(icon, size: 20, color: c.inkFaint)
              : Text(label,
                  style:
                      LedgerType.amount.copyWith(fontSize: 22, color: c.ink)),
        ),
      ),
    );
  }
}

/// A key that visibly depresses — taps should feel like pressing something.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.90 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
