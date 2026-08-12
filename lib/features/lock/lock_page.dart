import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/dates.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/seal.dart';
import '../../data/providers.dart';
import '../shell/shell.dart';

/// The book's cover. Face ID fires on arrival when a PIN exists; the PIN pad
/// is the fallback. A wrong PIN shakes and says so in one line; the right one
/// stamps the chop, and the book opens through it. Under the date the cover
/// may whisper one true thing about yesterday — never a nag.
class LockPage extends ConsumerStatefulWidget {
  const LockPage({super.key});

  @override
  ConsumerState<LockPage> createState() => _LockPageState();
}

class _LockPageState extends ConsumerState<LockPage>
    with SingleTickerProviderStateMixin {
  final _entered = StringBuffer();
  bool _hasPin = false;
  bool _checked = false;
  bool _wrong = false;
  bool _success = false;

  /// One quiet, factual line under the date — or nothing at all.
  String? _whisper;

  /// Built in [initState], never lazily: a cover that is never shaken (a
  /// book with no PIN) would otherwise construct its controller inside
  /// dispose, reaching for a ticker that is already gone.
  late final AnimationController _shake;

  /// The chop's landing (StampIn's own beat) and the pause after it, before
  /// the shell fades up through the cover.
  static const _stampBeat = Duration(milliseconds: 340);
  static const _openBeat = Duration(milliseconds: 260);

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _prepare();
    _listenForWhispers();
  }

  @override
  void dispose() {
    _shake.dispose();
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
    final gap = today.difference(DateTime(last.year, last.month, last.day)).inDays;
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

  Future<void> _tryBiometrics() async {
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return;
      final ok = await auth.authenticate(
        localizedReason: 'Open your book',
        // Not biometricOnly: many Android phones carry class-2 face unlock,
        // which a strict biometric ask refuses outright — and the device's
        // own credential is a perfectly good key to this door.
        biometricOnly: false,
      );
      if (ok && mounted) _celebrateAndOpen();
    } catch (_) {
      // No biometrics here (simulator, desktop, tests) — the PIN pad is
      // the door.
    }
  }

  /// Success is a moment: the chop stamps down with a thud (StampIn brings
  /// its own haptic), a beat passes, and the shell fades up through the cover.
  Future<void> _celebrateAndOpen() async {
    if (_success) return;
    setState(() => _success = true);
    if (!Motion.reduced(context)) {
      await Future<void>.delayed(_stampBeat + _openBeat);
    }
    if (!mounted) return;
    // Straight to the money — the character had its moment on the splash;
    // after the password nothing stands between Krish and the book.
    Navigator.of(
      context,
    ).pushReplacement(LedgerRoute(builder: (_) => const LedgerShell()));
  }

  Future<void> _digit(String d) async {
    if (_entered.length >= 4 || _success) return;
    setState(() {
      _wrong = false;
      _entered.write(d);
    });
    if (_entered.length < 4) return;

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
              'BudgetBox',
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
  /// under Krish's own chop-mark, which stamps on the way through.
  Widget _noPinYet(LedgerColors c) {
    return Column(
      children: [
        SizedBox(height: 52, child: Center(child: _chop(c))),
        const SizedBox(height: Gap.x4),
        Text(
          'Tap to open the book',
          style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
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

  /// Krish's mark. Idle it simply sits there; on the way in it lands.
  Widget _chop(LedgerColors c) {
    final mark = Text(
      'K',
      style: LedgerType.wordmark.copyWith(fontSize: 24, color: c.seal),
    );
    return _success
        ? StampIn(key: const ValueKey('lock-stamp'), size: 52, child: mark)
        : Seal(size: 52, child: mark);
  }

  Widget _pinPad(LedgerColors c) {
    // A wrong PIN is amber, not vermilion: the dots and their rims go warn
    // and only the one line of verdict wears the seal.
    final dotInk = _wrong ? c.warn : c.ink;
    final dotRim = _wrong ? c.warn : c.inkFaint;
    return Column(
      children: [
        // Success replaces the dots with the landing chop; otherwise the
        // dots, which shake as one piece on a wrong PIN.
        SizedBox(
          height: 64,
          child: _success
              ? Center(child: _chop(c))
              : AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) {
                    // Three diminishing swings.
                    final t = _shake.value;
                    final dx = math.sin(t * math.pi * 5) * 14 * (1 - t);
                    return Transform.translate(
                      offset: Offset(dx, 0),
                      child: child,
                    );
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 4; i++)
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
                    _key(c, '', _tryBiometrics, icon: Icons.face_outlined),
                    _key(c, '0', () => _digit('0')),
                    _key(c, '', _backspace, icon: Icons.backspace_outlined),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _key(
    LedgerColors c,
    String label,
    VoidCallback onTap, {
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.all(6),
      // The kit's press: every key visibly gives, with its own click.
      child: Pressable(
        scale: 0.90,
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
              : Text(
                  label,
                  style: LedgerType.amount.copyWith(fontSize: 22, color: c.ink),
                ),
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
