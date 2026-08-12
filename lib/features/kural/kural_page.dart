import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/seal.dart';
import '../../data/providers.dart';

/// One kural a day, all 1330 of them, in order, no repeats — three and a
/// half years before the book clears its throat and starts again. The whole
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
            (
              word: v['w'] as String,
              ta: v['ta'] as String,
              en: v['en'] as String,
            ),
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
  const KuralPage({super.key, required this.index, required this.streak});

  /// 0-based position in the sequence (kural index, not number).
  final int index;

  /// Consecutive days read, today included.
  final int streak;

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

  void _celebrate() {
    if (_celebrating) return;
    HapticFeedback.lightImpact();
    if (Motion.reduced(context)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _celebrating = true);
    _streakC.forward();
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
                      Text('இன்றைய குறள்',
                          style:
                              LedgerType.label.copyWith(color: c.inkFaint)),
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'day ${widget.streak} of reading',
                              style: LedgerType.bodyStrong
                                  .copyWith(fontSize: 14, color: c.ink),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'குறள் ${kural.no} · ${all.length - (widget.index % all.length) - 1} left in the book',
                              style: LedgerType.bodyText
                                  .copyWith(fontSize: 11, color: c.inkFaint),
                            ),
                          ],
                        ),
                        const Spacer(),
                        for (var d = 1; d <= 7; d++)
                          Padding(
                            padding: const EdgeInsets.only(left: 5),
                            child: d == weekday
                                ? const StampIn(size: 18, haptic: false)
                                : Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: d < weekday
                                              ? c.inkFaint
                                              : c.rule),
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Gap.x8),
                // ————— the couplet itself, the day's hero —————
                InkIn(
                  child: Text(
                    kural.couplet,
                    textAlign: TextAlign.center,
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 24,
                      height: 1.7,
                      color: c.ink,
                    ),
                  ),
                ),
                const SizedBox(height: Gap.x3),
                InkIn(
                  delay: const Duration(milliseconds: 140),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Gap.x2, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.paperRaised,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'திருக்குறள் ${kural.no}',
                        style: LedgerType.amount
                            .copyWith(fontSize: 12, color: c.inkFaint),
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
                              fontSize: 15, height: 1.65, color: c.ink),
                        ),
                        const SizedBox(height: Gap.x3),
                        Text(
                          kural.english,
                          style: LedgerType.bodyText.copyWith(
                              fontSize: 13, height: 1.5, color: c.inkFaint),
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
                                    fontSize: 12, color: c.inkFaint),
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
                    child: _StreakMoment(
                        controller: _streakC, streak: widget.streak),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Decides whether to-day's kural is still unread, and if so pushes it —
/// called by the shell once it settles. All bookkeeping lives in settings:
/// `kuralIndex` (next to show), `kuralDay` (last shown), `kuralStreak`.
Future<void> maybeShowDailyKural(
    BuildContext context, ProviderContainer container) async {
  // Never inside the test binding: every shell test would otherwise open
  // under the day's kural. The page has its own direct tests.
  if (WidgetsBinding.instance.runtimeType.toString().startsWith('Test') ||
      WidgetsBinding.instance.runtimeType
          .toString()
          .startsWith('AutomatedTest')) {
    return;
  }
  final settings = container.read(settingsRepoProvider);
  final today = DateTime.now();
  final key =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  final lastDay = await settings.kuralDay();
  if (lastDay == key) return; // already read to-day

  final index = await settings.kuralIndex();
  final streak = await settings.bumpKuralStreak(key, lastDay);
  await settings.setKuralShown(key, index + 1);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    LedgerRoute<void>(builder: (_) => KuralPage(index: index, streak: streak)),
  );
}

/// The reference's streak banner, in this book's hand.
///
/// Beats, on one timeline: slide down (0–12%), settle, today's dot blooms
/// into a vermilion seal (22–34%), the tick lands in it (34–44%), a long
/// proud hold, and the slide back up (86–98%). The owner pops the page when
/// the controller completes.
class _StreakMoment extends StatelessWidget {
  const _StreakMoment({required this.controller, required this.streak});

  final AnimationController controller;
  final int streak;

  static const _names = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final today = DateTime.now().weekday; // 1=Mon..7
    final slideIn = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.0, 0.12, curve: Curves.easeOutCubic),
    );
    final slideOut = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.86, 0.98, curve: Curves.easeInCubic),
    );
    final bloom = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.22, 0.34, curve: Cubic(0.2, 1.5, 0.4, 1)),
    );
    final tick = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.34, 0.44, curve: Curves.easeOut),
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final dy = -1.4 * (1 - slideIn.value) + -1.4 * slideOut.value;
        return FractionalTranslation(
          translation: Offset(0, dy),
          child: Container(
            padding: const EdgeInsets.fromLTRB(Gap.x4, Gap.x3, Gap.x4, Gap.x3),
            decoration: BoxDecoration(
              color: c.paperRaised,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'day $streak of your reading streak',
                  style: LedgerType.bodyStrong
                      .copyWith(fontSize: 14, color: c.ink),
                ),
                const SizedBox(height: Gap.x3),
                Row(
                  children: [
                    // The seal wears the count — this book's flame.
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.seal,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$streak',
                        style: LedgerType.amount.copyWith(
                            fontSize: 16,
                            color: c.paperRaised,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Spacer(),
                    for (var i = 0; i < 7; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 7),
                        child: Column(
                          children: [
                            Text(
                              _names[(today - 1 + i) % 7],
                              style: LedgerType.label.copyWith(
                                  fontSize: 9,
                                  color: i == 0 ? c.ink : c.inkFaint),
                            ),
                            const SizedBox(height: 4),
                            i == 0
                                ? Transform.rotate(
                                    angle: -0.09,
                                    child: Transform.scale(
                                      scale: bloom.value,
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: c.seal,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Opacity(
                                          opacity: tick.value,
                                          child: PenTick(
                                              size: 12, color: c.paperRaised),
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: c.rule),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
