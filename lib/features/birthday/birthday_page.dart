import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/seal.dart';
import '../../data/db.dart';
import '../../data/providers.dart';

/// The owner's-day page.
///
/// Once a year, on 18 August, the first unlock of the day does not open the
/// book — the book opens itself. Five scenes, each advanced by a tap, the
/// way a page is turned rather than a video watched: the date recognised,
/// a seal that opens a day instead of closing one, the year read back out
/// of his own rows, a gift, and the wish. Then the book goes back to being
/// a book until next year.
///
/// Built to be unbreakable on the one morning it runs: every scene advances
/// on a plain tap even if an animation never arrives, every fact is queried
/// inside its own guard, and reduced motion gets the whole ceremony with
/// the theatrics settled instead of skipped.

/// True exactly when the page should appear: the 18th of August, and not
/// yet shown this year. Pure, so the calendar arithmetic is provable
/// without a widget tree.
bool birthdaySurpriseDue(DateTime now, String? shownYear) =>
    now.month == 8 && now.day == 18 && shownYear != '${now.year}';

/// What the book counted while its owner was busy living. Every field is
/// best-effort: a failed query contributes a zero, never a crash.
class BirthdayFacts {
  const BirthdayFacts({
    this.name = 'Krish',
    this.daysOfBook = 0,
    this.entries = 0,
    this.daysClosed = 0,
    this.glasses = 0,
    this.focusMinutes = 0,
    this.journalPages = 0,
  });

  final String name;

  /// Days since the first entry was ever written.
  final int daysOfBook;
  final int entries;
  final int daysClosed;
  final int glasses;
  final int focusMinutes;
  final int journalPages;

  bool get hasAnything =>
      entries > 0 ||
      daysClosed > 0 ||
      glasses > 0 ||
      focusMinutes > 0 ||
      journalPages > 0;
}

/// Reads the year back out of the rows. Each count stands alone so one
/// broken table costs one line of the ceremony, not the ceremony.
Future<BirthdayFacts> gatherBirthdayFacts(
  LedgerDb db, {
  required String name,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  Future<int> count(String sql) async {
    try {
      final row = await db.customSelect(sql).getSingleOrNull();
      return row?.read<int?>('n') ?? 0;
    } on Object {
      return 0;
    }
  }

  var daysOfBook = 0;
  try {
    final row = await db
        .customSelect('SELECT MIN(at) AS first FROM txns')
        .getSingleOrNull();
    final first = row?.read<DateTime?>('first');
    if (first != null) {
      daysOfBook = at.difference(first).inDays + 1;
    }
  } on Object {
    daysOfBook = 0;
  }

  return BirthdayFacts(
    name: name,
    daysOfBook: daysOfBook,
    entries: await count('SELECT COUNT(*) AS n FROM txns'),
    daysClosed: await count('SELECT COUNT(*) AS n FROM day_seals'),
    glasses: await count(
      "SELECT COUNT(*) AS n FROM day_marks WHERE kind = 'water'",
    ),
    focusMinutes: await count(
      'SELECT COALESCE(SUM(minutes), 0) AS n FROM focus_sessions '
      'WHERE completed = 1',
    ),
    journalPages: await count(
      'SELECT COUNT(*) AS n FROM journal_entries',
    ),
  );
}

/// One ceremony at a time: the shell asks on launch *and* on resume, and
/// the second ask must never stack a second page mid-first.
bool _surpriseShowing = false;

/// The gate the shell knocks on after unlock. Never inside the test
/// binding — the page has its own direct tests, same rule as the kural.
Future<void> maybeShowBirthdaySurprise(
  BuildContext context,
  ProviderContainer container,
) async {
  // Taken at the door, before any await: launch and first-resume can knock
  // in the same breath, and only one of them may be let in.
  if (_surpriseShowing) return;
  _surpriseShowing = true;
  try {
    if (WidgetsBinding.instance.runtimeType.toString().startsWith('Test') ||
        WidgetsBinding.instance.runtimeType.toString().startsWith(
          'AutomatedTest',
        )) {
      return;
    }
    final settings = container.read(settingsRepoProvider);
    final now = DateTime.now();
    if (!birthdaySurpriseDue(now, await settings.birthdaySurpriseYear())) {
      return;
    }
    final facts = await gatherBirthdayFacts(
      container.read(dbProvider),
      name: await settings.name(),
      now: now,
    );
    if (!context.mounted) return;
    // Marked the moment the page is pushed: the ceremony happens once even
    // if it is walked away from — a surprise rerun is no surprise.
    await settings.markBirthdaySurprise(now.year);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 600),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => BirthdayPage(facts: facts),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  } finally {
    _surpriseShowing = false;
  }
}

class BirthdayPage extends StatefulWidget {
  const BirthdayPage({super.key, required this.facts});

  final BirthdayFacts facts;

  @override
  State<BirthdayPage> createState() => _BirthdayPageState();
}

class _BirthdayPageState extends State<BirthdayPage>
    with TickerProviderStateMixin {
  /// Which scene the ceremony stands on. Only ever climbs, so every scene
  /// key is unique for free.
  int _scene = 0;
  static const _lastScene = 4;

  /// The gift's own timeline, wound up when the Lottie reports its length.
  /// Created eagerly: a lazy controller first touched inside dispose would
  /// mint its ticker while the tree is coming down.
  late final AnimationController _gift;

  /// Whether the shower behind the gift has started.
  bool _rain = false;

  @override
  void initState() {
    super.initState();
    _gift = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _gift.dispose();
    super.dispose();
  }

  void _turn() {
    if (_scene >= _lastScene) return;
    HapticFeedback.lightImpact();
    setState(() => _scene++);
    if (_scene == 3) {
      // The gift scene: the box opens, and while it does the sky lets go.
      if (Motion.reduced(context)) {
        setState(() => _rain = false);
      } else {
        HapticFeedback.heavyImpact();
        setState(() => _rain = true);
      }
    }
  }

  void _keepTheDay() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final reduced = Motion.reduced(context);
    return PopScope(
      // The back gesture must not eat the one page of the year by
      // accident; a tap anywhere moves forward, and the last scene holds
      // the door handle.
      canPop: _scene >= _lastScene,
      child: Scaffold(
        backgroundColor: c.paper,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _turn,
          child: SafeArea(
            child: Stack(
              children: [
                if (_rain)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _SealRain(
                        onDone: () {
                          if (mounted) setState(() => _rain = false);
                        },
                      ),
                    ),
                  ),
                AnimatedSwitcher(
                  duration: reduced ? Duration.zero : Motion.settle,
                  switchInCurve: Motion.curve,
                  switchOutCurve: Motion.curve.flipped,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.015),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey('scene-$_scene'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.x6,
                      ),
                      child: switch (_scene) {
                        0 => _SceneDate(c: c),
                        1 => _SceneSeal(c: c),
                        2 => _SceneCount(c: c, facts: widget.facts),
                        3 => _SceneGift(c: c, gift: _gift),
                        _ => _SceneWish(
                          c: c,
                          name: widget.facts.name,
                          onKeep: _keepTheDay,
                        ),
                      },
                    ),
                  ),
                ),
                // The quiet invitation to turn the page — on every scene
                // but the last, where the button takes over.
                if (_scene < _lastScene)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: Gap.x6,
                    child: IgnorePointer(
                      child: InkIn(
                        key: ValueKey('hint-$_scene'),
                        delay: const Duration(milliseconds: 1600),
                        child: Text(
                          'tap to turn the page',
                          textAlign: TextAlign.center,
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 12,
                            color: c.inkFaint,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ————— scene 1: the date —————

class _SceneDate extends StatelessWidget {
  const _SceneDate({required this.c});

  final LedgerColors c;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkIn(
            child: Text(
              '18 august.',
              style: LedgerType.title.copyWith(fontSize: 40, color: c.ink),
            ),
          ),
          const SizedBox(height: Gap.x4),
          InkIn(
            delay: const Duration(milliseconds: 900),
            child: Text(
              'hold on —',
              style: LedgerType.bodyText.copyWith(
                fontSize: 15,
                color: c.inkFaint,
              ),
            ),
          ),
          const SizedBox(height: Gap.x1),
          InkIn(
            delay: const Duration(milliseconds: 1800),
            child: Text(
              'I know this date.',
              style: LedgerType.bodyStrong.copyWith(
                fontSize: 17,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ————— scene 2: the seal that opens a day —————

class _SceneSeal extends StatelessWidget {
  const _SceneSeal({required this.c});

  final LedgerColors c;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StampIn(
            size: 120,
            delay: const Duration(milliseconds: 350),
            child: Text(
              '18',
              style: LedgerType.title.copyWith(fontSize: 44, color: c.seal),
            ),
          ),
          const SizedBox(height: Gap.x8),
          InkIn(
            delay: const Duration(milliseconds: 900),
            child: Text(
              'every seal in this book closes a day.',
              textAlign: TextAlign.center,
              style: LedgerType.bodyText.copyWith(
                fontSize: 15,
                color: c.inkFaint,
              ),
            ),
          ),
          const SizedBox(height: Gap.x2),
          InkIn(
            delay: const Duration(milliseconds: 1700),
            child: Text(
              'this one opens one.',
              textAlign: TextAlign.center,
              style: LedgerType.bodyStrong.copyWith(
                fontSize: 18,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ————— scene 3: the year, read back —————

class _SceneCount extends StatelessWidget {
  const _SceneCount({required this.c, required this.facts});

  final LedgerColors c;
  final BirthdayFacts facts;

  @override
  Widget build(BuildContext context) {
    final lines = <(int, String)>[
      if (facts.entries > 0) (facts.entries, 'entries, written by hand'),
      if (facts.daysClosed > 0) (facts.daysClosed, 'days closed with the seal'),
      if (facts.glasses > 0) (facts.glasses, 'glasses of water'),
      if (facts.focusMinutes > 0) (facts.focusMinutes, 'minutes of held focus'),
      if (facts.journalPages > 0) (facts.journalPages, 'pages of the journal'),
    ];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkIn(
            child: Text(
              facts.daysOfBook > 0
                  ? 'day ${facts.daysOfBook} of this book, and while you '
                        'lived them —'
                  : 'while you were living, I was keeping count —',
              style: LedgerType.bodyText.copyWith(
                fontSize: 15,
                color: c.inkFaint,
              ),
            ),
          ),
          const SizedBox(height: Gap.x6),
          if (!facts.hasAnything)
            InkIn(
              delay: const Duration(milliseconds: 600),
              child: Text(
                'the pages are still young.\nthe year ahead is ours.',
                style: LedgerType.title.copyWith(fontSize: 24, color: c.ink),
              ),
            )
          else
            for (final (i, (figure, words)) in lines.indexed)
              InkIn(
                delay: Duration(milliseconds: 500 + 420 * i),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Gap.x3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      CountUp(
                        value: figure,
                        duration: const Duration(milliseconds: 900),
                        format: (v) => '$v',
                        style: LedgerType.heroAmount.copyWith(
                          fontSize: 30,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(width: Gap.x3),
                      Expanded(
                        child: Text(
                          words,
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 14,
                            color: c.inkFaint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: Gap.x4),
          InkIn(
            delay: Duration(milliseconds: 700 + 420 * lines.length),
            child: Text(
              'not one of those days needed a birthday to matter.',
              style: LedgerType.bodyStrong.copyWith(
                fontSize: 15,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ————— scene 4: the gift —————

class _SceneGift extends StatelessWidget {
  const _SceneGift({required this.c, required this.gift});

  final LedgerColors c;
  final AnimationController gift;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            height: 220,
            child: Lottie.asset(
              'assets/animation/Gift.json',
              controller: gift,
              fit: BoxFit.contain,
              renderCache: RenderCache.raster,
              onLoaded: (composition) {
                // The drawing may arrive after the page has already been
                // left — a dead controller must not take the morning down.
                try {
                  gift.duration = composition.duration;
                  if (reduced) {
                    gift.value = 1;
                  } else {
                    gift.forward(from: 0);
                  }
                } on Object {
                  // Nothing to animate; the scene stands on its words.
                }
              },
              // If the drawing ever fails to arrive, the seal stands in —
              // the ceremony never shows a broken box.
              errorBuilder: (_, _, _) =>
                  const Center(child: StampIn(size: 120)),
            ),
          ),
          const SizedBox(height: Gap.x6),
          InkIn(
            delay: const Duration(milliseconds: 1200),
            child: Text(
              'I had a year to think about what to get you.',
              textAlign: TextAlign.center,
              style: LedgerType.bodyText.copyWith(
                fontSize: 15,
                color: c.inkFaint,
              ),
            ),
          ),
          const SizedBox(height: Gap.x1),
          InkIn(
            delay: const Duration(milliseconds: 2100),
            child: Text(
              'so I kept it. all of it. turn the page.',
              textAlign: TextAlign.center,
              style: LedgerType.bodyStrong.copyWith(
                fontSize: 16,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ————— scene 5: the wish —————

class _SceneWish extends StatelessWidget {
  const _SceneWish({required this.c, required this.name, required this.onKeep});

  final LedgerColors c;
  final String name;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: StampIn(size: 64, delay: Duration(milliseconds: 300)),
          ),
          const SizedBox(height: Gap.x6),
          InkIn(
            delay: const Duration(milliseconds: 700),
            child: Text(
              'happy birthday, ${name.toLowerCase()}.',
              textAlign: TextAlign.center,
              style: LedgerType.title.copyWith(fontSize: 32, color: c.ink),
            ),
          ),
          const SizedBox(height: Gap.x4),
          InkIn(
            delay: const Duration(milliseconds: 1400),
            child: Text(
              'a year of your days lives in me now — the chai, the buses, '
              'the closed evenings, the quiet ones no one else saw. '
              'I keep them all, and I am not letting a single one go.',
              textAlign: TextAlign.center,
              style: LedgerType.bodyText.copyWith(
                fontSize: 15,
                height: 1.5,
                color: c.inkFaint,
              ),
            ),
          ),
          const SizedBox(height: Gap.x3),
          InkIn(
            delay: const Duration(milliseconds: 2200),
            child: Text(
              '— your book. and the brother inside it.',
              textAlign: TextAlign.center,
              style: LedgerType.bodyStrong.copyWith(
                fontSize: 14,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(height: Gap.x8),
          InkIn(
            delay: const Duration(milliseconds: 2800),
            child: FilledButton(
              onPressed: onKeep,
              child: const Text('keep the day'),
            ),
          ),
          const SizedBox(height: Gap.x2),
          InkIn(
            delay: const Duration(milliseconds: 3200),
            child: Text(
              'this page returns in a year.',
              textAlign: TextAlign.center,
              style: LedgerType.bodyText.copyWith(
                fontSize: 11,
                color: c.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Forty small things falling once a year — seals, paper squares, status
/// dots. Deterministic per index, same shower every birthday: the same joke
/// the Today page tells, retold here with the door shut.
class _SealRain extends StatelessWidget {
  const _SealRain({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final colors = [c.seal, c.jama, c.warn, c.quill];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 3200),
      onEnd: onDone,
      builder: (context, t, _) {
        return LayoutBuilder(
          builder: (context, box) {
            double n(int i, double salt) =>
                (math.sin(i * 127.1 + salt * 311.7) + 1) / 2;
            return Stack(
              children: [
                for (var i = 0; i < 40; i++)
                  Positioned(
                    left:
                        n(i, 1) * box.maxWidth +
                        math.sin(t * 6.28 * (1 + n(i, 2)) + i) * 18,
                    top:
                        -40 +
                        (box.maxHeight + 80) *
                            Curves.easeIn.transform(
                              (t * (0.7 + 0.5 * n(i, 3))).clamp(0.0, 1.0),
                            ),
                    child: Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0) * 0.9,
                      child: Transform.rotate(
                        angle: t * 6.28 * (n(i, 4) - 0.5) * 3,
                        child: Container(
                          width: 6 + 6 * n(i, 5),
                          height: 6 + 6 * n(i, 5),
                          decoration: BoxDecoration(
                            color: colors[i % colors.length].withValues(
                              alpha: 0.9,
                            ),
                            borderRadius: BorderRadius.circular(
                              i % 3 == 0 ? 99 : 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
