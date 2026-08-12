import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/dates.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../data/providers.dart';
import '../shell/shell.dart';

/// The book's cover. The character — the folder-book with a face, the same
/// one that settles onto the splash — waits here and is the way in. Face ID
/// fires on arrival when a PIN exists; the ledger keypad is the fallback. A
/// wrong PIN shakes and says so in one line; the right one presses the
/// character down like a stamp, and the book opens through it. Under the
/// date the cover may whisper one true thing about yesterday — never a nag.
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

  /// One quiet, factual line under the date — or nothing at all.
  String? _whisper;

  /// Built in [initState], never lazily: a cover that is never shaken (a
  /// book with no PIN) would otherwise construct its controller inside
  /// dispose, reaching for a ticker that is already gone.
  late final AnimationController _shake;

  /// The character pressed down on the way in — the same hand that stamps
  /// the seal, landing on the book's face instead.
  late final AnimationController _press;

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
    _prepare();
    _listenForWhispers();
  }

  @override
  void dispose() {
    _shake.dispose();
    _press.dispose();
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
      // No biometrics here (simulator, desktop, tests) — the keypad is
      // the door.
    }
  }

  /// Success is a moment: the character gets pressed down with a thud —
  /// the cover stamped by the hand that opens it — a beat passes, and the
  /// shell fades up through it.
  Future<void> _celebrateAndOpen() async {
    if (_success) return;
    setState(() => _success = true);
    HapticFeedback.mediumImpact();
    if (!Motion.reduced(context)) {
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
            const Spacer(flex: 2),
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

  /// The character, holding the middle of the cover. On the way in it takes
  /// the press — down and back in one breath, the stamp's gesture without
  /// the stamp.
  Widget _character(LedgerColors c, {required double width}) {
    return AnimatedBuilder(
      animation: _press,
      builder: (context, child) {
        final dip = math.sin(_press.value * math.pi);
        return Transform.scale(scale: 1 - 0.10 * dip, child: child);
      },
      child: MarkFace(width: width, body: c.quill, face: c.paper),
    );
  }

  /// Until a PIN exists (setup ritual or Settings), the cover just opens —
  /// through the character itself, which visibly gives under the finger.
  Widget _noPinYet(LedgerColors c) {
    return Column(
      children: [
        Pressable(
          scale: 0.94,
          onTap: _celebrateAndOpen,
          child: _character(c, width: 128),
        ),
        const SizedBox(height: Gap.x8),
        Text(
          'Tap to open the book',
          textAlign: TextAlign.center,
          style: LedgerType.bodyText.copyWith(fontSize: 14, color: c.ink),
        ),
        const SizedBox(height: Gap.x1),
        Text(
          'No lock set yet — add one in Settings',
          textAlign: TextAlign.center,
          style: LedgerType.bodyText.copyWith(
            fontSize: 11,
            color: c.inkFaint.withValues(alpha: 0.7),
          ),
        ),
      ],
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
                    _key(
                      c,
                      '',
                      _tryBiometrics,
                      mark: PenFace(size: 22, color: c.inkFaint),
                    ),
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
    Widget? mark,
    bool faint = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Pressable(
        scale: 0.92,
        onTap: onTap,
        child: Container(
          width: 78,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.paperRaised,
            borderRadius: BorderRadius.circular(Corner.key),
          ),
          child: mark ??
              Text(
                label,
                style: LedgerType.amount.copyWith(
                  fontSize: 20,
                  color: faint ? c.inkFaint : c.ink,
                ),
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
