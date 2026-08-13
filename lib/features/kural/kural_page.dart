import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/lottie_marks.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/seal.dart';
import '../../data/providers.dart';

const kuralCount = 1330;

/// A tiny fixed PRNG for the reading order. Dart's Random algorithm is not a
/// persistence contract; this one is. The same seed therefore reconstructs
/// the same Fisher–Yates order after an app update or on another device.
class _KuralRandom {
  _KuralRandom(int seed) : _state = seed == 0 ? 0x6d2b79f5 : seed;

  int _state;

  int nextInt(int max) {
    var x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >>> 17;
    x ^= (x << 5) & 0xffffffff;
    _state = x & 0xffffffff;
    return _state % max;
  }
}

/// Rebuilds one random-looking, no-repeat cycle without storing 1,330 ids.
List<int> shuffledKuralOrder(int length, int seed) {
  final order = List<int>.generate(length, (i) => i);
  final random = _KuralRandom(seed);
  for (var i = order.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final hold = order[i];
    order[i] = order[j];
    order[j] = hold;
  }
  return order;
}

int shuffledKuralIndex(int length, int seed, int position) =>
    shuffledKuralOrder(length, seed)[position % length];

/// One Kural a day, all 1,330 in shuffled order with no repeats — three and a
/// half years before the book clears its throat and reshuffles. The whole
/// text ships inside the app: a couplet that has waited two thousand years
/// can wait out a dead network too.
class Kural {
  const Kural({
    required this.no,
    required this.couplet,
    required this.urai,
    required this.english,
    required this.vocab,
  });

  final int no;
  final String couplet;
  final String urai;
  final String english;
  final List<({String word, String ta, String en})> vocab;

  static Kural fromJson(Map<String, dynamic> j) => Kural(
    no: j['no'] as int,
    couplet: j['k'] as String,
    urai: j['urai'] as String,
    english: j['en'] as String,
    vocab: [
      for (final v in (j['vocab'] as List? ?? const []))
        (word: v['w'] as String, ta: v['ta'] as String, en: v['en'] as String),
    ],
  );
}

/// Loads the bundled text once per session.
Future<List<Kural>> loadKurals() async {
  final raw = await rootBundle.loadString('assets/kural/kural.json');
  final list = jsonDecode(raw) as List;
  return [for (final e in list) Kural.fromJson(e as Map<String, dynamic>)];
}

/// The day's page from the Kural: number chip, the couplet large, urai,
/// meaning, and — when the book has them — the couplet's words opened up,
/// with the reading streak riding on top.
class KuralPage extends StatefulWidget {
  const KuralPage({
    super.key,
    required this.index,
    required this.streak,
    this.position,
    this.onRead,
  });

  /// 0-based position in the sequence (kural index, not number).
  final int index;

  /// Position inside the shuffled cycle. Direct page tests may omit it and
  /// retain the old index-based display fallback.
  final int? position;

  /// Consecutive days read, today included.
  final int streak;

  /// Commits progress only when the reader presses “படித்தேன்”.
  final Future<void> Function()? onRead;

  @override
  State<KuralPage> createState() => _KuralPageState();
}

class _KuralPageState extends State<KuralPage>
    with SingleTickerProviderStateMixin {
  // Held once: a rebuild must not re-read 774KB of scripture.
  late final Future<List<Kural>> _kurals = loadKurals();

  /// The streak moment, beat for beat from the reference: the card comes
  /// DOWN over the page, today's dot blooms into a stamped seal, the tick
  /// lands, it holds, and the card leaves the way it came — then the page
  /// closes itself. One controller, no timers.
  late final AnimationController _streakC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );
  bool _celebrating = false;

  @override
  void initState() {
    super.initState();
    _streakC.addStatusListener((st) {
      if (st == AnimationStatus.completed && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _streakC.dispose();
    super.dispose();
  }

  Future<void> _celebrate() async {
    if (_celebrating) return;
    await widget.onRead?.call();
    if (!mounted) return;
    HapticFeedback.lightImpact();
    if (Motion.reduced(context)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _celebrating = true);
    _streakC.forward();
  }

  /// One weekday's mark (1=Mon). A past day counts as read when it falls
  /// inside the running streak, which ends to-day — the streak preview
  /// already includes to-day, so the days read before it are streak − 1.
  Widget _weekMark(LedgerColors c, int d, int weekday) {
    if (d == weekday) return const StampIn(size: 18, haptic: false);
    if (d > weekday) {
      return Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c.rule),
        ),
      );
    }
    final read = weekday - d <= widget.streak - 1;
    return SizedBox(
      width: 14,
      height: 14,
      child: Center(
        child: read
            ? PenTick(size: 13, color: c.jama)
            : PenCross(size: 10, color: c.inkFaint.withValues(alpha: 0.55)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<Kural>>(
          future: _kurals,
          builder: (context, snap) {
            final all = snap.data;
            if (all == null || all.isEmpty) return const SizedBox.shrink();
            final kural = all[widget.index % all.length];
            final weekday = DateTime.now().weekday; // 1=Mon..7=Sun
            final page = ListView(
              padding: const EdgeInsets.symmetric(horizontal: Gap.page),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: Gap.x3),
                  child: Row(
                    children: [
                      Text(
                        'இன்றைய குறள்',
                        style: LedgerType.label.copyWith(color: c.inkFaint),
                      ),
                      const Spacer(),
                      Pressable(
                        onTap: () => Navigator.of(context).pop(),
                        child: Padding(
                          padding: const EdgeInsets.all(Gap.x1),
                          child: PenCross(size: 15, color: c.inkFaint),
                        ),
                      ),
                    ],
                  ),
                ),
                // ————— the reading streak, worn quietly —————
                LedgerCard(
                  child: Padding(
                    padding: const EdgeInsets.only(top: Gap.x3),
                    child: Row(
                      children: [
                        // Flexible, or the line about what's left in the book
                        // takes its full intrinsic width and shoves the week
                        // off the plate on a phone.
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'day ${widget.streak} of reading',
                                style: LedgerType.bodyStrong.copyWith(
                                  fontSize: 14,
                                  color: c.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'குறள் ${kural.no} · ${all.length - ((widget.position ?? widget.index) % all.length) - 1} left in the book',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: LedgerType.bodyText.copyWith(
                                  fontSize: 11,
                                  color: c.inkFaint,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Gap.x3),
                        // The week tells the truth: a tick where the day was
                        // read, a small cross where it wasn't, to-day taking
                        // the stamp, and the days ahead still blank.
                        for (var d = 1; d <= 7; d++)
                          Padding(
                            padding: const EdgeInsets.only(left: 5),
                            child: _weekMark(c, d, weekday),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Gap.x8),
                // ————— the couplet itself, the day's hero —————
                InkIn(
                  child: _Couplet(text: kural.couplet, color: c.ink),
                ),
                const SizedBox(height: Gap.x3),
                InkIn(
                  delay: const Duration(milliseconds: 140),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.x2,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.paperRaised,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'திருக்குறள் ${kural.no}',
                        style: LedgerType.amount.copyWith(
                          fontSize: 12,
                          color: c.inkFaint,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.x6),
                InkIn(
                  delay: const Duration(milliseconds: 220),
                  child: LedgerCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const RuleHeader('பொருள்'),
                        const SizedBox(height: Gap.x2),
                        Text(
                          kural.urai,
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 15,
                            height: 1.65,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: Gap.x3),
                        Text(
                          kural.english,
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 13,
                            height: 1.5,
                            color: c.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (kural.vocab.isNotEmpty)
                  InkIn(
                    delay: const Duration(milliseconds: 300),
                    child: LedgerCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const RuleHeader('சொற்கள்'),
                          for (final (i, v) in kural.vocab.indexed)
                            LedgerLine(
                              title: v.word,
                              detail: v.ta,
                              amount: '',
                              amountWidget: Text(
                                v.en,
                                style: LedgerType.bodyText.copyWith(
                                  fontSize: 12,
                                  color: c.inkFaint,
                                ),
                              ),
                              last: i == kural.vocab.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: Gap.x6),
                FilledButton(
                  onPressed: _celebrate,
                  child: const Text('படித்தேன் — open the book'),
                ),
                const SizedBox(height: Gap.x6),
              ],
            );
            return Stack(
              children: [
                page,
                if (_celebrating)
                  Positioned(
                    left: Gap.x2,
                    right: Gap.x2,
                    top: Gap.x2,
                    // The card and its two Lottie marks move every frame;
                    // without this the whole page underneath — scripture,
                    // cards and all — is asked to repaint along with them.
                    child: RepaintBoundary(
                      child: _StreakMoment(
                        controller: _streakC,
                        streak: widget.streak,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The couplet in its own metre. A kural is seven cīrs — four on the first
/// line, three on the second — and the page keeps that shape instead of
/// letting the phone wrap scripture wherever the margin happens to fall.
/// Each line scales down to fit rather than break.
class _Couplet extends StatelessWidget {
  const _Couplet({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = LedgerType.bodyStrong.copyWith(
      fontSize: 24,
      height: 1.55,
      color: color,
    );
    final words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    // Anything that isn't a seven-cīr couplet (it happens in edited texts)
    // falls back to a plain centred wrap.
    if (words.length < 5) {
      return Text(text, textAlign: TextAlign.center, style: style);
    }
    Widget line(String s) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(s, style: style),
    );
    return Column(
      children: [line(words.take(4).join(' ')), line(words.skip(4).join(' '))],
    );
  }
}

/// Decides whether to-day's kural is still unread, and if so pushes it —
/// called by the shell once it settles. All bookkeeping lives in settings:
/// `kuralPosition` (next slot), `kuralSeed` (cycle order), `kuralDay`
/// (last completed), and `kuralStreak`.
Future<void> maybeShowDailyKural(
  BuildContext context,
  ProviderContainer container,
) async {
  // Never inside the test binding: every shell test would otherwise open
  // under the day's kural. The page has its own direct tests.
  if (WidgetsBinding.instance.runtimeType.toString().startsWith('Test') ||
      WidgetsBinding.instance.runtimeType.toString().startsWith(
        'AutomatedTest',
      )) {
    return;
  }
  final settings = container.read(settingsRepoProvider);
  final today = DateTime.now();
  final key =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  final lastDay = await settings.kuralDay();
  if (lastDay == key) return; // already read to-day

  final position = await settings.kuralPosition();
  final seed = await settings.kuralCycleSeed();
  final index = shuffledKuralIndex(kuralCount, seed, position);
  final streak = await settings.previewKuralStreak(key, lastDay);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    LedgerRoute<void>(
      builder: (_) => KuralPage(
        index: index,
        position: position,
        streak: streak,
        onRead: () async {
          await settings.completeDailyKural(
            key,
            expectedPosition: position,
            total: kuralCount,
          );
        },
      ),
    ),
  );
}

/// The reference's streak banner, in this book's hand.
///
/// Beats, on one timeline: slide down (0–12%), the flame catches and burns
/// its whole take (12–96%), the dart flies at to-day's mark and lands
/// (22–68%), a long proud hold, and the slide back up (86–98%). Both marks
/// are hand-animated Lottie in the book's vermilion — see [StreakFlame] and
/// [TargetStamp] — and both ride this one controller rather than tickers of
/// their own. The owner pops the page when the controller completes.
class _StreakMoment extends StatelessWidget {
  const _StreakMoment({required this.controller, required this.streak});

  final AnimationController controller;
  final int streak;

  static const _names = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final today = DateTime.now().weekday; // 1=Mon..7
    // Arrival is one decisive move — most of the distance in the first
    // hundred milliseconds, then settling — and the exit is shorter still.
    // The old pair spent 430ms each way easing gently over 1.4 card-heights,
    // which reads as drag rather than grace.
    final slideIn = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.0, 0.085, curve: Cubic(0.12, 0.9, 0.2, 1)),
    );
    final slideOut = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.92, 1.0, curve: Cubic(0.7, 0, 0.84, 0)),
    );
    // Ink follows the move rather than leading it, so the card never hangs
    // half-faded in the middle of the screen.
    final fadeIn = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.0, 0.04),
    );
    final fadeOut = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.94, 1.0),
    );
    // Both animations carry their own easing from After Effects: these
    // intervals only place them on the timeline, and must stay linear or
    // the artist's timing gets bent twice.
    final flame = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.08, 0.94),
    );
    final throwIn = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.18, 0.64),
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final dy = -1.05 * (1 - slideIn.value) + -1.05 * slideOut.value;
        return Opacity(
          opacity: (fadeIn.value * (1 - fadeOut.value)).clamp(0.0, 1.0),
          child: FractionalTranslation(
            translation: Offset(0, dy),
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                Gap.x4,
                Gap.x3,
                Gap.x4,
                Gap.x3,
              ),
              decoration: BoxDecoration(
                color: c.paperRaised,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  // Enough to lift the card off the page, not so much that it
                  // lands as a grey slab on the day paper.
                  BoxShadow(
                    color: const Color(0xFF000000).withValues(alpha: 0.12),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The reference sets its headline in serif, and so does
                      // this book.
                      Expanded(
                        child: Text(
                          'day $streak of your reading streak',
                          style: LedgerType.title.copyWith(
                            fontSize: 19,
                            color: c.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.x3),
                      // The count keeps the corner: out of the fire, where it
                      // was fighting the flame for room, and up here where a
                      // figure belongs.
                      Text(
                        '$streak',
                        style: LedgerType.markCount.copyWith(color: c.ink),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.x4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StreakFlame(progress: flame, height: 62),
                      const SizedBox(width: Gap.x6),
                      // The week takes what's left and spreads itself across
                      // it: seven fixed slots would overrun a 360pt phone.
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < 7; i++)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _names[(today - 1 + i) % 7],
                                    style: LedgerType.label.copyWith(
                                      fontSize: 9,
                                      color: i == 0 ? c.ink : c.inkFaint,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  // To-day keeps exactly the week's own slot —
                                  // the dart is what marks it, not extra room.
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: i == 0
                                        ? TargetStamp(progress: throwIn)
                                        : DecoratedBox(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(color: c.rule),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
