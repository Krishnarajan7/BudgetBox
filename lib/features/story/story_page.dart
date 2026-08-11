import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/seal.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/goal_repo.dart';

/// The month's entries. The story is one screen, so its reads live here
/// rather than as four nested builders.
final _monthTxnsProvider = StreamProvider.autoDispose<List<Txn>>((ref) {
  final now = DateTime.now();
  return ref.watch(txnRepoProvider).watchRange(
        LedgerDates.monthStart(now),
        LedgerDates.monthEnd(now),
      );
});

final _categoriesProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  final db = ref.watch(dbProvider);
  return db.select(db.categories).watch();
});

final _budgetsProvider = StreamProvider.autoDispose<List<Budget>>(
    (ref) => ref.watch(budgetRepoProvider).watchAll());

final _goalsProvider = StreamProvider.autoDispose<List<GoalView>>(
    (ref) => ref.watch(goalRepoProvider).watchViews());

/// The monthly story: swipeable pages in the app's voice — the spend, the
/// Sankey, whatever else the month actually earned a page for — closing on a
/// stamp. The one place the app gets to be theatrical; it earned it.
class StoryPage extends ConsumerStatefulWidget {
  const StoryPage({super.key});

  @override
  ConsumerState<StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends ConsumerState<StoryPage> {
  final _controller = PageController();
  int _page = 0;

  /// Pages the reader has actually reached. Every figure sits at zero until
  /// its page arrives, then counts up to what the month really was — and it
  /// stays there, so a half-swipe never runs the digits backwards.
  final _arrived = <int>{};

  /// True once the reader has turned a page — the swipe hint retires.
  bool _swiped = false;

  @override
  void initState() {
    super.initState();
    // Page one arrives a frame late on purpose: its figures get to count.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _arrived.add(0));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _turned(int i) {
    HapticFeedback.selectionClick();
    setState(() {
      _page = i;
      _arrived.add(i);
      if (i > 0) _swiped = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final now = DateTime.now();

    final facts = _MonthFacts(
      month: ref.watch(_monthTxnsProvider).value ?? const <Txn>[],
      cats: {
        for (final x in ref.watch(_categoriesProvider).value ??
            const <Category>[])
          x.id: x,
      },
      budgets: ref.watch(_budgetsProvider).value ?? const <Budget>[],
      goals: ref.watch(_goalsProvider).value ?? const <GoalView>[],
      now: now,
    );
    final pages = _buildPages(c, facts);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Gap.page, Gap.x3, Gap.page, 0),
              child: Row(
                children: [
                  Text(
                    '${facts.monthName.toLowerCase()}, '
                    'page ${_page + 1} of ${pages.length}',
                    style: LedgerType.amount
                        .copyWith(fontSize: 12, color: c.inkFaint),
                  ),
                  const Spacer(),
                  Pressable(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close, size: 18, color: c.inkFaint),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: _turned,
                children: pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.x6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // The active dot glides into a small pill.
                  for (var i = 0; i < pages.length; i++)
                    AnimatedContainer(
                      duration: Motion.quick,
                      curve: Motion.curve,
                      width: i == _page ? 14 : 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Corner.chip),
                        color: i == _page ? c.ink : c.rule,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPages(LedgerColors c, _MonthFacts f) {
    final pages = <Widget>[];
    bool here(int i) => _arrived.contains(i);

    /// The story's line style, and its emphasis — both from the tokens.
    final line = LedgerType.title.copyWith(fontSize: 28, color: c.ink);
    final emph = LedgerType.heroAmount.copyWith(fontSize: 28, color: c.ink);

    TextSpan bold(String t) => TextSpan(text: t, style: emph);

    /// A figure that arrives with its page: zero until the reader gets here.
    InlineSpan figure(int index, int value, String Function(int) format) =>
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: CountUp(
            value: here(index) ? value : 0,
            format: format,
            style: emph,
          ),
        );

    InlineSpan money(int index, int paise) =>
        figure(index, paise, Inr.format);
    InlineSpan tally(int index, int count) =>
        figure(index, count, (v) => '$v');

    void add(List<InlineSpan> Function(int index) spans,
        {Widget? Function(int index)? extra}) {
      final index = pages.length;
      pages.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          child: InkIn(
            key: ValueKey('story-page-$index'),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(TextSpan(children: spans(index)), style: line),
                if (extra != null) ...[
                  const SizedBox(height: Gap.x4),
                  ?extra(index),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // ── The five that always run ──────────────────────────────────────────
    add(
      (i) => [
        const TextSpan(text: 'This month, '),
        money(i, f.spent),
        const TextSpan(text: ' left the book.'),
      ],
      // A faint nudge for the first read; it retires after one page turn.
      extra: (_) => AnimatedOpacity(
        duration: Motion.spring,
        curve: Motion.curve,
        opacity: _swiped ? 0 : 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('swipe',
                style: LedgerType.bodyText
                    .copyWith(fontSize: 13, color: c.inkFaint)),
            Icon(Icons.chevron_right, size: 15, color: c.inkFaint),
          ],
        ),
      ),
    );

    add((i) => [
          bold(f.topCategoryName),
          const TextSpan(text: ' took the biggest bite — '),
          money(i, f.topCategoryPaise),
          const TextSpan(text: '.'),
        ]);

    add(
      (i) => [
        const TextSpan(text: 'Your biggest day was the '),
        bold(_ordinal(f.biggestDay)),
        const TextSpan(text: ' — '),
        money(i, f.biggestDayPaise),
        const TextSpan(text: '.'),
      ],
      extra: (_) => Text(
        'Worth it? Only you know. The book just keeps the score.',
        style: LedgerType.bodyText.copyWith(color: c.inkFaint),
      ),
    );

    add((i) => [
          tally(i, f.quietDays),
          const TextSpan(text: ' quiet days — pages with nothing on them.'),
        ]);

    // ── The Sankey ────────────────────────────────────────────────────────
    final sankeyIndex = pages.length;
    pages.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.page),
        child: InkIn(
          key: ValueKey('story-page-$sankeyIndex'),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('where it went',
                  style: LedgerType.label.copyWith(color: c.inkFaint)),
              const SizedBox(height: Gap.x3),
              SizedBox(
                height: 260,
                width: double.infinity,
                // The ribbons grow left→right when this page first shows.
                child: DrawIn(
                  duration: const Duration(milliseconds: 900),
                  builder: (context, t) => CustomPaint(
                    painter: _SankeyPainter(
                      income: math.max(f.income, f.spent),
                      flows: f.sankeyFlows,
                      c: c,
                      progress: t,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Gap.x4),
              Text.rich(
                TextSpan(children: [
                  money(sankeyIndex, math.max(f.income, f.spent)),
                  const TextSpan(text: ' came in. '),
                  money(sankeyIndex, f.kept),
                  const TextSpan(text: ' stayed.'),
                ]),
                style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
              ),
            ],
          ),
        ),
      ),
    );

    // ── The conditional pages: only when the month actually earned them ───
    final held = f.heldBudget;
    if (held != null) {
      add(
        (i) => [
          bold(held.name),
          const TextSpan(text: ' never crossed its line — '),
          money(i, held.spent),
          TextSpan(text: ' of ${Inr.format(held.limit)}.'),
        ],
        extra: (_) => Text(
          'Twelve months of that and it\'s '
          '${Inr.format(held.spare * 12)} you never had to find.',
          style: LedgerType.bodyText.copyWith(color: c.inkFaint),
        ),
      );
    }

    final moved = f.movedGoal;
    if (moved != null) {
      add(
        (i) => [
          bold(moved.name),
          const TextSpan(text: ' took '),
          money(i, moved.moved),
          const TextSpan(text: ' this month.'),
        ],
        extra: (_) => Text(
          moved.reached
              ? 'And that was the last of it. The goal closed this month.'
              : '${Inr.format(moved.remaining)} to go — '
                  '${_months(moved.monthsLeft)} more like this one.',
          style: LedgerType.bodyText.copyWith(color: c.inkFaint),
        ),
      );
    }

    // Only worth a page if it has somewhere to land: a quiet week that
    // wouldn't have made the month cheaper is just a stat.
    final quiet = f.quietWeek;
    if (quiet != null && quiet.projected < f.spent) {
      add(
        (i) => [
          const TextSpan(text: 'Your quietest stretch was the '),
          bold('${_ordinal(quiet.start)} to the ${_ordinal(quiet.end)}'),
          const TextSpan(text: ' — '),
          money(i, quiet.paise),
          const TextSpan(text: ' went out.'),
        ],
        extra: (_) => Text(
          '${_weeks(quiet.weeksInMonth)} like that one and the month costs '
          '${Inr.format(quiet.projected)} — against the '
          '${Inr.format(f.spent)} it actually did.',
          style: LedgerType.bodyText.copyWith(color: c.inkFaint),
        ),
      );
    }

    // ── The ending ────────────────────────────────────────────────────────
    final closingIndex = pages.length;
    pages.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.page),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 46,
              child: here(closingIndex)
                  ? const StampIn(size: 42)
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: Gap.x4),
            Text('${f.monthName}, closed.', style: line),
            const SizedBox(height: Gap.x2),
            Text(
              f.monthOver
                  ? 'That\'s the page. The book keeps it.'
                  : 'Well — as much of it as you\'ve written so far.',
              style: LedgerType.bodyText.copyWith(color: c.inkFaint),
            ),
          ],
        ),
      ),
    );

    return pages;
  }
}

/// 1st, 2nd, 3rd, 4th … 21st. The book writes dates the way a person says
/// them.
String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

String _months(int n) => n == 1 ? 'one month' : '$n months';
String _weeks(int n) => n == 1 ? 'One week' : '$n weeks';

/// A budget that held its line for the whole month.
class _HeldBudget {
  const _HeldBudget(this.name, this.spent, this.limit);
  final String name;
  final int spent;
  final int limit;
  int get spare => limit - spent;
}

/// A goal the month actually moved.
class _MovedGoal {
  const _MovedGoal(this.name, this.moved, this.remaining, this.reached);
  final String name;
  final int moved;
  final int remaining;
  final bool reached;
  int get monthsLeft => moved <= 0 ? 0 : (remaining / moved).ceil();
}

/// The cheapest full week of the month, and what a month of them would cost.
class _QuietWeek {
  const _QuietWeek(
      this.start, this.end, this.paise, this.weeksInMonth, this.projected);
  final int start;
  final int end;
  final int paise;
  final int weeksInMonth;
  final int projected;
}

class _MonthFacts {
  _MonthFacts({
    required List<Txn> month,
    required Map<int, Category> cats,
    required List<Budget> budgets,
    required List<GoalView> goals,
    required DateTime now,
  }) {
    final expenses = month.where((t) => t.type == TxnType.expense).toList();
    spent = expenses.fold(0, (s, t) => s + t.amountPaise);
    income = month
        .where((t) => t.type == TxnType.income)
        .fold(0, (s, t) => s + t.amountPaise);
    kept = math.max(income - spent, 0);
    monthName = LedgerDates.monthsFull[now.month - 1];
    final daysInMonth = LedgerDates.daysInMonth(now);
    monthOver = now.day >= daysInMonth;

    final byCat = <int?, int>{};
    final byDay = <int, int>{};
    for (final t in expenses) {
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amountPaise;
      byDay[t.at.day] = (byDay[t.at.day] ?? 0) + t.amountPaise;
    }

    int? topCat;
    var topPaise = 0;
    byCat.forEach((k, v) {
      if (v > topPaise) {
        topPaise = v;
        topCat = k;
      }
    });
    topCategoryName =
        topCat == null ? 'Nothing' : (cats[topCat]?.name ?? 'Uncategorised');
    topCategoryPaise = topPaise;

    var bigDay = 1;
    var bigPaise = 0;
    byDay.forEach((k, v) {
      if (v > bigPaise) {
        bigPaise = v;
        bigDay = k;
      }
    });
    biggestDay = bigDay;
    biggestDayPaise = bigPaise;

    quietDays = List.generate(now.day, (i) => i + 1)
        .where((d) => !byDay.containsKey(d))
        .length;

    final sorted = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    sankeyFlows = [
      ('kept', kept, true),
      for (final e in sorted.take(4))
        (
          (cats[e.key]?.name.split(' ').first.toLowerCase()) ?? 'other',
          e.value,
          false
        ),
    ];

    heldBudget = _findHeldBudget(budgets, byCat);
    movedGoal = _findMovedGoal(goals, month);
    quietWeek = _findQuietWeek(byDay, now, daysInMonth);
  }

  /// A budget only "held" if it was genuinely used — an untouched budget is
  /// not a win, it's an unopened envelope. Tightest hold wins the page.
  static _HeldBudget? _findHeldBudget(
      List<Budget> budgets, Map<int?, int> byCat) {
    _HeldBudget? best;
    var bestUse = 0.0;
    for (final b in budgets) {
      if (b.categoryId == null || b.limitPaise <= 0) continue;
      final spent = byCat[b.categoryId] ?? 0;
      if (spent <= 0 || spent > b.limitPaise) continue;
      final use = spent / b.limitPaise;
      if (use < 0.5) continue; // barely touched — not a story
      if (use > bestUse) {
        bestUse = use;
        best = _HeldBudget(b.name, spent, b.limitPaise);
      }
    }
    return best;
  }

  /// A goal that moved enough to matter: a twentieth of its target, or the
  /// contribution that finished it.
  static _MovedGoal? _findMovedGoal(List<GoalView> goals, List<Txn> month) {
    if (goals.isEmpty) return null;
    final byGoal = <int, int>{};
    for (final t in month) {
      final id = t.goalId;
      if (id != null) byGoal[id] = (byGoal[id] ?? 0) + t.amountPaise;
    }
    _MovedGoal? best;
    var bestMoved = 0;
    for (final g in goals) {
      final moved = byGoal[g.goal.id] ?? 0;
      if (moved <= 0) continue;
      final matters = g.reached || moved * 20 >= g.goal.targetPaise;
      if (!matters || moved <= bestMoved) continue;
      bestMoved = moved;
      best = _MovedGoal(g.goal.name, moved, g.remainingPaise, g.reached);
    }
    return best;
  }

  /// The quietest *finished* week. Needs at least two to compare, or it's
  /// not a stretch, it's just the only week there is.
  static _QuietWeek? _findQuietWeek(
      Map<int, int> byDay, DateTime now, int daysInMonth) {
    final done = <(int, int, int)>[]; // start, end, paise
    for (var s = 1; s <= daysInMonth; s += 7) {
      final e = math.min(s + 6, daysInMonth);
      if (e >= now.day) break; // still being written
      var total = 0;
      for (var d = s; d <= e; d++) {
        total += byDay[d] ?? 0;
      }
      done.add((s, e, total));
    }
    if (done.length < 2) return null;
    var best = done.first;
    for (final w in done) {
      if (w.$3 < best.$3) best = w;
    }
    if (best.$3 <= 0) return null; // a blank week says nothing
    final weeks = math.max((daysInMonth / 7).round(), 1);
    return _QuietWeek(best.$1, best.$2, best.$3, weeks, best.$3 * weeks);
  }

  late final int spent;
  late final int income;
  late final int kept;
  late final String monthName;
  late final bool monthOver;
  late final String topCategoryName;
  late final int topCategoryPaise;
  late final int biggestDay;
  late final int biggestDayPaise;
  late final int quietDays;
  late final List<(String, int, bool)> sankeyFlows;
  late final _HeldBudget? heldBudget;
  late final _MovedGoal? movedGoal;
  late final _QuietWeek? quietWeek;
}

/// One hue, weighted by magnitude — income fanning into where it went.
class _SankeyPainter extends CustomPainter {
  _SankeyPainter({
    required this.income,
    required this.flows,
    required this.c,
    this.progress = 1,
  });

  final int income;
  final List<(String, int, bool)> flows;
  final LedgerColors c;

  /// 0→1 grows the ribbons left→right — one clean wipe, driven by [DrawIn].
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (income <= 0 || flows.isEmpty) return;
    if (progress < 1) {
      canvas.clipRect(
          Rect.fromLTWH(0, 0, size.width * progress, size.height));
    }
    const gapPx = 7.0;
    final x0 = 40.0;
    final x1 = size.width - 96;
    final usable = size.height - gapPx * (flows.length - 1) - 8;

    double scale(int v) => usable * v / income;

    // Left source bar.
    final total = flows.fold(0, (s, f) => s + f.$2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x0 - 6, 4, 5, scale(total) + gapPx * (flows.length - 1)),
        const Radius.circular(2.5),
      ),
      Paint()..color = c.ink.withValues(alpha: 0.85),
    );

    var yl = 4.0;
    var yr = 4.0;
    for (final (name, v, kept) in flows) {
      final h = math.max(scale(v), 2.0);
      final color = kept ? c.jama : c.quill;
      final opacity = kept ? 0.82 : (0.18 + 1.4 * v / income).clamp(0.15, 0.8);

      final path = Path()
        ..moveTo(x0, yl)
        ..cubicTo(x0 + 70, yl, x1 - 70, yr, x1, yr)
        ..lineTo(x1, yr + h)
        ..cubicTo(x1 - 70, yr + h, x0 + 70, yl + h, x0, yl + h)
        ..close();
      canvas.drawPath(
          path, Paint()..color = color.withValues(alpha: opacity));

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x1 + 1, yr, 5, h),
          const Radius.circular(2.5),
        ),
        Paint()..color = color.withValues(alpha: kept ? 1 : 0.55),
      );

      final label = TextPainter(
        text: TextSpan(
          text: '$name ${Inr.format(v)}',
          style: LedgerType.amount.copyWith(
            fontSize: kept ? 12 : 10.5,
            color: kept ? c.ink : c.inkFaint,
            fontVariations: [FontVariation('wght', kept ? 620 : 460)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 92);
      label.paint(canvas, Offset(x1 + 12, yr + h / 2 - label.height / 2));

      yl += h;
      yr += h + gapPx;
    }
  }

  @override
  bool shouldRepaint(_SankeyPainter old) =>
      old.income != income || old.flows != flows || old.progress != progress;
}
