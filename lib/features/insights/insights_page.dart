import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'insight_math.dart';

import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/icons.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/plates.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/settings_repo.dart';
import '../book/book_page.dart';
import '../today/widgets/ledger_rows.dart';

/// Where the money went, said plainly — the month read back as a page,
/// not a dashboard.
///
/// One month at a time: what it cost against last month and where it is
/// heading, the shape of its days, which categories carried it, where the
/// weight *moved* — the "you spend more on X" the book exists to say —
/// and the few single lines heavy enough to name. Sections sit straight
/// on the paper, ruled apart by their headers; everything is computed
/// from the ledger itself, on the phone, so the page is exactly as
/// correct offline as on.
class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key});

  @override
  ConsumerState<InsightsPage> createState() => _InsightsPageState();
}

/// One category's month-over-month movement.
class CategoryShift {
  const CategoryShift({
    required this.categoryId,
    required this.nowPaise,
    required this.thenPaise,
  });

  final int? categoryId;
  final int nowPaise;
  final int thenPaise;

  int get deltaPaise => nowPaise - thenPaise;
  bool get isNew => thenPaise == 0 && nowPaise > 0;
  bool get wentQuiet => nowPaise == 0 && thenPaise > 0;
}

/// The shifts worth saying, heaviest movement first. Pure, so the arithmetic
/// is testable without a widget in sight.
List<CategoryShift> categoryShifts(
  Iterable<(int?, int)> thisMonth,
  Iterable<(int?, int)> lastMonth, {
  int top = 6,
}) {
  final now = <int?, int>{};
  for (final (id, paise) in thisMonth) {
    now[id] = (now[id] ?? 0) + paise;
  }
  final then = <int?, int>{};
  for (final (id, paise) in lastMonth) {
    then[id] = (then[id] ?? 0) + paise;
  }
  final ids = {...now.keys, ...then.keys};
  final shifts = [
    for (final id in ids)
      CategoryShift(
        categoryId: id,
        nowPaise: now[id] ?? 0,
        thenPaise: then[id] ?? 0,
      ),
  ]..removeWhere((s) => s.deltaPaise == 0);
  shifts.sort((a, b) => b.deltaPaise.abs().compareTo(a.deltaPaise.abs()));
  return shifts.take(top).toList();
}

class _InsightsPageState extends ConsumerState<InsightsPage> {
  DateTime _month = LedgerDates.monthStart(DateTime.now());

  void _flip(int delta) {
    final current = LedgerDates.monthStart(DateTime.now());
    var target = LedgerDates.monthStart(bookMonthShift(_month, delta));
    if (target.isAfter(current)) target = current;
    if (target != _month) setState(() => _month = target);
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _label => '${_months[_month.month - 1]} ${_month.year}';

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final txns = ref.watch(txnRepoProvider);
    final db = ref.watch(dbProvider);
    final prev = bookMonthShift(_month, -1);
    final furthest = bookMonthShift(_month, -3);
    final onNow = _month == LedgerDates.monthStart(DateTime.now());

    return ModuleScaffold(
      title: 'Insights',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Pressable(
            onTap: () => _flip(-1),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: RotatedBox(
                quarterTurns: 1,
                child: PenChevron(size: 14, color: c.inkFaint),
              ),
            ),
          ),
          Text(
            LedgerDates.ddMmm(_month).split(' ').last,
            style: LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.ink),
          ),
          Pressable(
            onTap: onNow ? null : () => _flip(1),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: RotatedBox(
                quarterTurns: 3,
                child: PenChevron(size: 14, color: onNow ? c.rule : c.inkFaint),
              ),
            ),
          ),
        ],
      ),
      child: StreamBuilder<List<Txn>>(
        stream: txns.watchRange(_month, LedgerDates.monthEnd(_month)),
        builder: (context, nowSnap) {
          return StreamBuilder<List<Txn>>(
            // Three months back in one stream: the history every category
            // is judged against.
            stream: txns.watchRange(furthest, LedgerDates.monthEnd(prev)),
            builder: (context, pastSnap) {
              return StreamBuilder<List<Category>>(
                stream: db.select(db.categories).watch(),
                builder: (context, catSnap) {
                  final nowAll = nowSnap.data ?? const <Txn>[];
                  final pastAll = pastSnap.data ?? const <Txn>[];
                  final thenAll = [
                    for (final t in pastAll)
                      if (!t.at.isBefore(prev)) t,
                  ];
                  final cats = {
                    for (final cat in catSnap.data ?? const <Category>[])
                      cat.id: cat,
                  };
                  // A client's domain is a project's cost, not his habit;
                  // and a habit he has called fine stays called fine.
                  return StreamBuilder<List<ProjectLink>>(
                    stream: db.select(db.projectLinks).watch(),
                    builder: (context, linkSnap) {
                      final claimed = {
                        for (final l in linkSnap.data ?? const <ProjectLink>[])
                          l.txnId,
                      };
                      return StreamBuilder<Setting?>(
                        stream:
                            (db.select(db.settings)..where(
                                  (s) =>
                                      s.key.equals(SettingsRepo.handsMutedKey),
                                ))
                                .watchSingleOrNull(),
                        builder: (context, muteSnap) {
                          final muted = {
                            for (final k in (muteSnap.data?.value ?? '').split(
                              '\n',
                            ))
                              if (k.isNotEmpty) k,
                          };
                          return _body(
                            c,
                            nowAll,
                            thenAll,
                            pastAll,
                            cats,
                            claimed: claimed,
                            muted: muted,
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  /// The consequence of the split: the living figure against what came in,
  /// projected to the full month while the month is still running.
  String _runningLine(RunningMonth r, int incomePaise, bool onNow) {
    final now = DateTime.now();
    final daysIn = LedgerDates.daysInMonth(_month);
    final elapsed = onNow ? math.max(1, math.min(now.day, daysIn)) : daysIn;
    final projected = onNow && elapsed >= 7 && elapsed < daysIn
        ? (r.runningPaise / elapsed * daysIn).round()
        : r.runningPaise;
    final base = onNow && projected != r.runningPaise
        ? 'living costs about ${Inr.format(_near(projected))} a month at this pace'
        : 'living cost ${Inr.format(r.runningPaise)} this month';
    if (incomePaise <= 0) return '$base — nothing came in to set it against';
    if (projected > incomePaise) {
      return '$base — more than the ${Inr.format(incomePaise)} that came in, '
          'before a single one-off';
    }
    final kept = incomePaise - projected;
    return '$base — that leaves ${Inr.format(kept)} of the '
        '${Inr.format(incomePaise)} that came in';
  }

  /// The split, in one sentence: what was his to move against what was
  /// not. The fixed half is named so the figure is not mistaken for blame.
  String _handsLine(Hands h, bool onNow, int days) {
    final span = onNow ? 'the last $days days' : 'this month';
    if (h.fixedPaise == 0) {
      return 'all ${Inr.format(h.flexiblePaise)} of $span was yours to move '
          '— no rent or bills in it.';
    }
    final pct = (h.share * 100).round();
    return '${Inr.format(h.flexiblePaise)} of ${Inr.format(h.totalPaise)} '
        'over $span was yours to move — $pct%. rent and bills took the rest.';
  }

  /// Round enough to say "near": to ₹100 above ₹1,000, to ₹10 below it.
  /// A projection quoted to the rupee would be lying about its precision.
  static int _near(int paise) => paise >= 100_000
      ? (paise / 10_000).round() * 10_000
      : (paise / 1_000).round() * 1_000;

  Widget _body(
    LedgerColors c,
    List<Txn> nowAll,
    List<Txn> thenAll,
    List<Txn> pastAll,
    Map<int, Category> cats, {
    Set<int> claimed = const {},
    Set<String> muted = const {},
  }) {
    List<(int?, int)> spend(List<Txn> all) => [
      for (final t in all.where((t) => t.type == TxnType.expense))
        (t.categoryId, t.amountPaise),
    ];
    final nowSpend = spend(nowAll);
    final thenSpend = spend(thenAll);
    final nowTotal = nowSpend.fold(0, (s, e) => s + e.$2);
    final thenTotal = thenSpend.fold(0, (s, e) => s + e.$2);
    final delta = nowTotal - thenTotal;

    final heaviest = nowAll.where((t) => t.type == TxnType.expense).toList()
      ..sort((a, b) => b.amountPaise.compareTo(a.amountPaise));

    // Every category judged against its own last three months. A month
    // still being lived is compared through the same day-of-month, so
    // "running hot" on the 12th means hot *for a 12th*, not against a
    // whole month it hasn't had yet.
    final onNow = _month == LedgerDates.monthStart(DateTime.now());
    final cutDay = onNow ? DateTime.now().day : 32;
    List<SpendRow> monthRows(List<Txn> all, DateTime start) => [
      for (final t in all.where(
        (t) =>
            t.type == TxnType.expense &&
            !t.at.isBefore(start) &&
            t.at.isBefore(LedgerDates.monthEnd(start)) &&
            t.at.day <= cutDay,
      ))
        (t.categoryId, t.amountPaise, t.title),
    ];
    final stories = categoryStories(
      [
        for (final t in nowAll.where((t) => t.type == TxnType.expense))
          (t.categoryId, t.amountPaise, t.title),
      ],
      [
        for (var back = 1; back <= 3; back++)
          monthRows(pastAll, bookMonthShift(_month, -back)),
      ],
    );
    final lead = headline(stories);

    String catName(int? id) =>
        id == null ? 'unfiled' : (cats[id]?.name ?? 'unfiled');

    final running = runningMonth([
      for (final t in nowAll.where((t) => t.type == TxnType.expense))
        (t.title, t.amountPaise, cats[t.categoryId]?.name),
    ]);
    final incomeNow = nowAll
        .where((t) => t.type == TxnType.income)
        .fold(0, (s, t) => s + t.amountPaise);
    String? catIcon(int? id) => id == null ? null : cats[id]?.icon;

    // ————— in your hands —————
    //
    // A habit is a pattern in *recent* lines, so the month being lived is
    // read over its last thirty days rather than from the 1st — on the 3rd
    // there would be nothing to read. A finished month is read whole.
    final today = DateTime.now();
    final windowEnd = onNow ? today : LedgerDates.monthEnd(_month);
    final windowStart = onNow
        ? today.subtract(const Duration(days: 30))
        : _month;
    final windowRows = [
      for (final t in [...pastAll, ...nowAll])
        if (t.type == TxnType.expense &&
            !t.at.isBefore(windowStart) &&
            t.at.isBefore(windowEnd))
          (t.id, t.title, t.amountPaise, cats[t.categoryId]?.name, t.at),
    ];
    var windowDays = onNow ? 30 : LedgerDates.daysInMonth(_month);
    if (onNow && windowRows.isNotEmpty) {
      // A book younger than the window: the evidence spans only the days
      // it has been kept, and the pace must say so.
      final first = windowRows
          .map((r) => r.$5)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      windowDays = math.max(
        1,
        math.min(30, today.difference(first).inDays + 1),
      );
    }
    final inHands = hands(
      windowRows,
      days: windowDays,
      until: windowEnd,
      claimed: claimed,
      muted: muted,
    );

    // The drawer's four inks, dealt to the heaviest categories — and then
    // colour follows the category across the whole page: the same ink on
    // its bar in the ranking and on every day it carried in the strip.
    // Beyond four, categories stay in plain ink rather than inventing hues.
    final inkByCat = <int?, Color>{
      for (final (i, s) in stories.indexed)
        if (i < c.chartInks.length) s.categoryId: c.chartInks[i],
    };

    // ————— the shape of the days —————
    final daysIn = LedgerDates.daysInMonth(_month);
    final elapsed = onNow ? math.min(DateTime.now().day, daysIn) : daysIn;
    final daily = dailyTotals([
      for (final t in nowAll.where((t) => t.type == TxnType.expense))
        (t.at.day, t.amountPaise),
    ], daysIn);
    final heavyDay = heaviestDay(daily, elapsed: elapsed);
    final quiet = quietestWeek(daily, elapsed: elapsed);

    // Each day's stroke wears the ink of the category that carried it —
    // the strip reads as *whose* month it was, day by day. Days carried
    // by an unranked category stay in plain ink.
    final byDayCat = <int, Map<int?, int>>{};
    for (final t in nowAll.where((t) => t.type == TxnType.expense)) {
      final m = byDayCat.putIfAbsent(t.at.day, () => {});
      m[t.categoryId] = (m[t.categoryId] ?? 0) + t.amountPaise;
    }
    final dayInks = List<Color?>.filled(daysIn, null);
    byDayCat.forEach((day, m) {
      if (day < 1 || day > daysIn) return;
      final top = m.entries.reduce((a, b) => a.value >= b.value ? a : b);
      dayInks[day - 1] = inkByCat[top.key];
    });

    // What carried the heaviest day — one line if one line was most of
    // it, its category if the category was; otherwise the day speaks
    // for itself.
    String? heavyCarrier;
    if (heavyDay != null) {
      final dayTxns =
          nowAll
              .where(
                (t) => t.type == TxnType.expense && t.at.day == heavyDay.$1,
              )
              .toList()
            ..sort((a, b) => b.amountPaise.compareTo(a.amountPaise));
      final top = dayTxns.first;
      if (top.amountPaise * 5 >= heavyDay.$2 * 3) {
        heavyCarrier = top.title;
      } else {
        final byCat = <int?, int>{};
        for (final t in dayTxns) {
          byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amountPaise;
        }
        final topCat = byCat.entries.reduce(
          (a, b) => a.value >= b.value ? a : b,
        );
        if (topCat.value * 5 >= heavyDay.$2 * 3) {
          heavyCarrier = catName(topCat.key);
        }
      }
    }

    // ————— the consequence: where the month is heading —————
    //
    // Prior months enter *whole* here — a projection is a finished figure
    // and is judged against finished figures, unlike the per-category
    // pace above, which cuts to the same day.
    final priorTotals = <int>[];
    for (var back = 1; back <= 3; back++) {
      final start = bookMonthShift(_month, -back);
      priorTotals.add(
        pastAll
            .where(
              (t) =>
                  t.type == TxnType.expense &&
                  !t.at.isBefore(start) &&
                  t.at.isBefore(LedgerDates.monthEnd(start)),
            )
            .fold(0, (s, t) => s + t.amountPaise),
      );
    }
    final pace = onNow
        ? paceProjection(
            spentPaise: nowTotal,
            elapsedDays: elapsed,
            daysInMonth: daysIn,
            priorMonthTotals: priorTotals,
          )
        : null;
    String? paceLine;
    var paceInk = c.inkFaint;
    if (pace != null) {
      final near = Inr.format(_near(pace.projected));
      final usual = pace.usual;
      if (usual == null) {
        paceLine = 'at this pace the month lands near $near';
      } else {
        final gap = pace.projected - usual;
        if (gap.abs() < 20_000) {
          paceLine =
              'at this pace the month lands near $near — '
              'about a usual month';
        } else {
          paceLine =
              'at this pace the month lands near $near — '
              '${Inr.format(_near(gap.abs()))} '
              '${gap > 0 ? 'heavier' : 'lighter'} than usual';
          if (gap > 0) paceInk = c.warn;
        }
      }
    }

    // ————— the movement worth naming, against last month —————
    //
    // A month with no predecessor has nothing to have moved from, and a
    // swing under ₹200 is not a story.
    final shifts = thenSpend.isEmpty
        ? const <CategoryShift>[]
        : [
            for (final s in categoryShifts(nowSpend, thenSpend))
              if (s.deltaPaise.abs() >= 20_000) s,
          ].take(3).toList();

    if (nowSpend.isEmpty && thenSpend.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Gap.page),
        child: Text(
          'Nothing written in $_label — a quiet page has nothing to explain.',
          style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
        ),
      );
    }

    Widget dayNote(String line, {Color? ink}) => Padding(
      padding: const EdgeInsets.only(top: Gap.x2),
      child: Text(
        line,
        style: LedgerType.bodyText.copyWith(
          fontSize: 13,
          height: 1.45,
          color: ink ?? c.inkFaint,
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Gap.page),
      children: [
        const SizedBox(height: Gap.x4),
        // ————— the month, in one figure —————
        Text(
          _label.toLowerCase(),
          style: LedgerType.label.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: 2),
        CountUp(
          value: nowTotal,
          format: Inr.format,
          style: LedgerType.heroAmount.copyWith(fontSize: 44, color: c.ink),
        ),
        const SizedBox(height: Gap.x2),
        if (thenTotal > 0 || nowTotal > 0)
          Row(
            children: [
              _DeltaChip(
                label: delta == 0
                    ? 'dead even with last month'
                    : delta < 0
                    ? '${Inr.format(-delta)} lighter than last month'
                    : '${Inr.format(delta)} heavier than last month',
                tone: delta > 0 ? c.warn : c.jama,
              ),
            ],
          ),

        // ————— the paragraph worth reading first —————
        if (lead != null) ...[
          const SizedBox(height: Gap.x3),
          Text(
            _headlineLine(lead, catName),
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              height: 1.45,
              color: lead.$2 ? c.inkFaint : c.warn,
            ),
          ),
        ],
        if (paceLine != null) ...[
          const SizedBox(height: Gap.x1),
          Text(
            paceLine,
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              height: 1.45,
              color: paceInk,
            ),
          ),
        ],

        // ————— the running month: what living costs, apart from what
        // happened once —————
        //
        // A first month somewhere new is mostly one-offs: the ticket, the
        // deposit, the pillow. The figure worth carrying forward is the
        // month *without* them, set against what came in.
        if (running.oneOffPaise > 0 && running.runningPaise > 0) ...[
          const SectionHead('the running month'),
          LeaderRow(
            label: 'living',
            detail: 'rent, food, getting around, bills, kirana',
            amount: Inr.format(running.runningPaise),
            amountColor: c.ink,
          ),
          LeaderRow(
            label: 'one-offs',
            detail: running.oneOffs
                .take(3)
                .map((o) => o.$1.toLowerCase())
                .join(', '),
            amount: Inr.format(running.oneOffPaise),
            amountColor: c.inkFaint,
          ),
          const SizedBox(height: Gap.x2),
          Text(
            _runningLine(running, incomeNow, onNow),
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              height: 1.45,
              color: incomeNow > 0 && running.runningPaise > incomeNow
                  ? c.warn
                  : c.inkFaint,
            ),
          ),
        ],

        // ————— in your hands: what he could move, and the habits in it —————
        if (inHands.totalPaise > 0) ...[
          const SectionHead('in your hands'),
          Text(
            _handsLine(inHands, onNow, windowDays),
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              height: 1.45,
              color: c.inkFaint,
            ),
          ),
          const SizedBox(height: Gap.x2),
          RoundedBar(fraction: inHands.share, ink: c.quill, height: 5),
          if (inHands.habits.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Gap.x3),
              child: Text(
                'nothing repeats enough to call a habit yet.',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
            )
          else
            Plate(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, h) in inHands.habits.indexed)
                    _HabitRow(
                      key: ValueKey('habit-${h.key}'),
                      habit: h,
                      last: i == inHands.habits.length - 1,
                      onOpen: h.search.isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                              LedgerRoute<void>(
                                builder: (_) => BookPage(
                                  initialMonth: _month,
                                  initialQuery: h.search,
                                ),
                              ),
                            ),
                      onFine: () {
                        HapticFeedback.selectionClick();
                        ref.read(settingsRepoProvider).muteHand(h.key);
                      },
                    ),
                ],
              ),
            ),
        ],

        // ————— the days: the month's shape, stroke by stroke —————
        if (nowSpend.isNotEmpty) ...[
          const SectionHead('the days'),
          _DayStrip(
            key: ValueKey('days-$_month'),
            daily: daily,
            elapsed: elapsed,
            heavyDay: heavyDay?.$1,
            dayInks: dayInks,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                LedgerDates.ddMmm(_month),
                style: LedgerType.amount.copyWith(
                  fontSize: 9,
                  color: c.inkFaint,
                ),
              ),
              const Spacer(),
              Text(
                LedgerDates.ddMmm(DateTime(_month.year, _month.month, daysIn)),
                style: LedgerType.amount.copyWith(
                  fontSize: 9,
                  color: c.inkFaint,
                ),
              ),
            ],
          ),
          if (heavyDay != null)
            dayNote(
              'the heaviest day was ${LedgerDates.dayLabel(DateTime(_month.year, _month.month, heavyDay.$1))} '
              '— ${Inr.format(heavyDay.$2)}'
              '${heavyCarrier == null ? '' : ', mostly $heavyCarrier'}',
            ),
          if (quiet != null)
            dayNote(
              'the quietest stretch — ${quiet.$1}–'
              '${LedgerDates.ddMmm(DateTime(_month.year, _month.month, quiet.$1 + 6))}, '
              '${quiet.$2 == 0 ? 'not a rupee written' : '${Inr.format(quiet.$2)} in seven days'}',
            ),
        ],

        // ————— where it went —————
        //
        // The whole month, ranked — no wheel, no fold, no "everything
        // else" hiding two-thirds of the money. Each category carries its
        // share, a bar against the heaviest, and one line of judgement
        // against its own last three months. Tap a row and the book opens
        // already turned to this month and narrowed to that category.
        if (stories.isNotEmpty) ...[
          const SectionHead('where it went'),
          Plate(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, story) in stories.indexed)
                  _StoryRow(
                    story: story,
                    name: catName(story.categoryId),
                    iconKey: catIcon(story.categoryId),
                    topPaise: stories.first.paise,
                    ink: inkByCat[story.categoryId],
                    last: i == stories.length - 1,
                    onTap: () => Navigator.of(context).push(
                      LedgerRoute<void>(
                        builder: (_) => BookPage(
                          initialMonth: _month,
                          initialCategory: story.categoryId,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // ————— where the weight moved —————
        if (shifts.isNotEmpty) ...[
          const SectionHead('where the weight moved'),
          for (final s in shifts)
            LeaderRow(
              label: catName(s.categoryId),
              amountWidget: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${s.deltaPaise > 0 ? '+' : '−'}'
                    '${Inr.format(s.deltaPaise.abs())}',
                    style: LedgerType.amount.copyWith(
                      color: s.deltaPaise > 0 ? c.warn : c.jama,
                    ),
                  ),
                  if (s.isNew || s.wentQuiet)
                    Text(
                      s.isNew ? ' · first seen' : ' · went quiet',
                      style: LedgerType.label.copyWith(color: c.inkFaint),
                    ),
                ],
              ),
            ),
        ],

        // ————— the heaviest single lines —————
        if (heaviest.isNotEmpty) ...[
          const SectionHead('heaviest lines'),
          for (final (i, t) in heaviest.take(3).indexed)
            LedgerLine(
              leading: LedgerDates.ddMmm(t.at),
              title: t.title,
              detail: catName(t.categoryId),
              amount: Inr.format(t.amountPaise),
              last: i == heaviest.take(3).length - 1,
            ),
        ],
        const SizedBox(height: Gap.x8),
      ],
    );
  }
}

/// The month's movement, stamped small — status ink on a wash of itself.
class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.x2, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: LedgerType.bodyStrong.copyWith(fontSize: 11, color: tone),
      ),
    );
  }
}

/// The month's spending as a row of ink strokes, one per day — the way a
/// ledger's pages thicken and thin. Each stroke wears the ink of the
/// category that carried its day (plain ink when that category is
/// unranked); the heaviest day is drawn at full voice; a day with nothing
/// written keeps a rule tick; days still to come are blank paper. The
/// strokes rise left to right as the page draws itself.
class _DayStrip extends StatelessWidget {
  const _DayStrip({
    super.key,
    required this.daily,
    required this.elapsed,
    required this.dayInks,
    this.heavyDay,
  });

  final List<int> daily;
  final int elapsed;

  /// Per-day ink from the dominant category, null for plain ink days.
  final List<Color?> dayInks;

  /// 1-based day of the month set at full voice, when one earned it.
  final int? heavyDay;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: DrawIn(
        duration: const Duration(milliseconds: 700),
        builder: (context, t) => CustomPaint(
          painter: _DayStrokesPainter(
            daily: daily,
            elapsed: elapsed,
            heavyDay: heavyDay,
            dayInks: dayInks,
            ink: c.ink,
            quill: c.quill,
            rule: c.rule,
            progress: t,
          ),
        ),
      ),
    );
  }
}

class _DayStrokesPainter extends CustomPainter {
  _DayStrokesPainter({
    required this.daily,
    required this.elapsed,
    required this.heavyDay,
    required this.dayInks,
    required this.ink,
    required this.quill,
    required this.rule,
    this.progress = 1,
  });

  final List<int> daily;
  final int elapsed;
  final int? heavyDay;
  final List<Color?> dayInks;
  final Color ink;
  final Color quill;
  final Color rule;

  /// 0→1: the strokes rise left to right, each on the tail of the last.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (daily.isEmpty) return;
    final base = size.height - 1;
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = rule
        ..strokeWidth = 1,
    );

    final n = math.min(elapsed, daily.length);
    var maxV = 0;
    for (var i = 0; i < n; i++) {
      maxV = math.max(maxV, daily[i]);
    }

    final slot = size.width / daily.length;
    final strokeW = math.min(slot * 0.5, 4.0);
    final tickPaint = Paint()
      ..color = rule
      ..strokeWidth = math.max(strokeW * 0.6, 1.0);
    for (var i = 0; i < n; i++) {
      // Staggered reveal: each stroke grows over a short beat that starts
      // as its neighbour's ends.
      final t = Curves.easeOutCubic.transform(
        ((progress * (daily.length + 6) - i) / 6).clamp(0.0, 1.0),
      );
      if (t <= 0) break;
      final x = slot * (i + 0.5);
      if (daily[i] <= 0 || maxV <= 0) {
        canvas.drawLine(Offset(x, base), Offset(x, base - 2.5 * t), tickPaint);
        continue;
      }
      final h = (4 + (base - 12) * (daily[i] / maxV)) * t;
      final heavy = (i + 1) == heavyDay;
      final catInk = i < dayInks.length ? dayInks[i] : null;
      canvas.drawLine(
        Offset(x, base),
        Offset(x, base - h),
        Paint()
          ..color = catInk == null
              ? (heavy ? quill : ink.withValues(alpha: 0.45))
              : catInk.withValues(alpha: heavy ? 1.0 : 0.75)
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_DayStrokesPainter old) =>
      old.progress != progress ||
      old.daily != daily ||
      old.elapsed != elapsed ||
      old.heavyDay != heavyDay ||
      old.dayInks != dayInks;
}

/// The lead sentence: the hottest runner named plainly, or the calm verdict.
String _headlineLine(
  (CategoryStory, bool) lead,
  String Function(int?) catName,
) {
  final (story, calm) = lead;
  if (calm) {
    return '${catName(story.categoryId)} holds the most — '
        'nothing is running past its usual.';
  }
  return '${catName(story.categoryId)} is '
      '${Inr.format(story.overPaise)} past its usual pace — '
      'the rest of the month is ordinary.';
}

/// One category's line in the ranking: mark, name, judgement, figure and
/// share — and beneath them, its bar against the heaviest category, in
/// the ink the category wears everywhere on this page (a plain quill
/// wash when it holds none).
class _StoryRow extends StatelessWidget {
  const _StoryRow({
    required this.story,
    required this.name,
    required this.iconKey,
    required this.topPaise,
    required this.last,
    required this.onTap,
    this.ink,
  });

  final CategoryStory story;
  final String name;
  final String? iconKey;
  final int topPaise;
  final bool last;
  final VoidCallback onTap;

  /// The category's ink from the page's shared deal, null when unranked.
  final Color? ink;

  /// The judgement, in the book's voice. Every line is earned from this
  /// category's own history — never a generic caption.
  String get _verdictLine {
    final s = story;
    switch (s.verdict) {
      case CategoryVerdict.oneBigLine:
        return 'mostly one line — ${s.biggestTitle}';
      case CategoryVerdict.runningHot:
        return '${Inr.format(s.overPaise)} past its usual';
      case CategoryVerdict.runningCool:
        return '${Inr.format(-s.overPaise)} under its usual';
      case CategoryVerdict.firstMonth:
        return s.count == 1 ? 'one entry, first seen' : 'first month with this';
      case CategoryVerdict.steady:
        return s.count == 1
            ? '1 entry · about usual'
            : '${s.count} entries · about usual';
    }
  }

  Color _verdictColor(LedgerColors c) => switch (story.verdict) {
    CategoryVerdict.runningHot => c.warn,
    CategoryVerdict.runningCool => c.jama,
    _ => c.inkFaint,
  };

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(top: Gap.x2, bottom: last ? 2 : Gap.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Medallion(
                  icon: LedgerIcons.resolve(iconKey),
                  ink: ink ?? c.inkFaint,
                  size: 34,
                  iconSize: 16,
                ),
                const SizedBox(width: Gap.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LedgerType.bodyStrong.copyWith(
                          fontSize: 14,
                          color: c.ink,
                        ),
                      ),
                      Text(
                        _verdictLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LedgerType.label.copyWith(
                          color: _verdictColor(c),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.x3),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Inr.format(story.paise),
                      style: LedgerType.amount.copyWith(color: c.ink),
                    ),
                    Text(
                      '${(story.share * 100).round()}%',
                      style: LedgerType.label.copyWith(color: c.inkFaint),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 5),
            // Its length against the heaviest — the shape of the month at
            // a glance, in one ink.
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: RoundedBar(
                fraction: topPaise <= 0 ? 0.0 : story.paise / topPaise,
                ink: ink ?? c.quill.withValues(alpha: 0.6),
                height: 5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One habit on the plate: what it is, what it cost, the pace in a full
/// sentence, and the two things he can do about it — open the lines, or
/// call it fine and never hear of it again.
class _HabitRow extends StatelessWidget {
  const _HabitRow({
    super.key,
    required this.habit,
    required this.last,
    required this.onOpen,
    required this.onFine,
  });

  final Habit habit;
  final bool last;
  final VoidCallback? onOpen;
  final VoidCallback onFine;

  static IconData _icon(HabitKind k) => switch (k) {
    HabitKind.often => Icons.repeat_rounded,
    HabitKind.shop => Icons.storefront_outlined,
    HabitKind.standing => Icons.autorenew_rounded,
    HabitKind.weekend => Icons.weekend_outlined,
    HabitKind.unnamed => Icons.edit_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final h = habit;
    final amount = h.kind == HabitKind.standing
        ? '${Inr.format(h.paise)}/yr'
        : Inr.format(h.paise);
    final body = Padding(
      padding: EdgeInsets.only(top: 8, bottom: last ? 4 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Medallion(
            icon: _icon(h.kind),
            ink: h.kind == HabitKind.unnamed ? c.inkFaint : c.quill,
          ),
          const SizedBox(width: Gap.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        h.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LedgerType.bodyStrong.copyWith(
                          fontSize: 14.5,
                          color: c.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.x2),
                    Text(
                      amount,
                      style: LedgerType.amountTotal.copyWith(
                        fontSize: 15,
                        color: h.kind == HabitKind.unnamed ? c.inkFaint : c.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  habitLine(h),
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12.5,
                    height: 1.4,
                    color: c.inkFaint,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (onOpen != null)
                      Pressable(
                        key: ValueKey('habit-open-${h.key}'),
                        onTap: onOpen,
                        child: Text(
                          'the lines ›',
                          style: LedgerType.bodyStrong.copyWith(
                            fontSize: 12,
                            color: c.quill,
                          ),
                        ),
                      ),
                    if (onOpen != null) const SizedBox(width: Gap.x4),
                    Pressable(
                      key: ValueKey('habit-fine-${h.key}'),
                      onTap: onFine,
                      child: Text(
                        "that's fine",
                        style: LedgerType.bodyStrong.copyWith(
                          fontSize: 12,
                          color: c.inkFaint,
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
    );
    if (last) return body;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      child: body,
    );
  }
}
