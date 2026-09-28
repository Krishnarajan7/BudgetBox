import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'insight_math.dart';

import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
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
    // What carried each day, for the scrub readout: the category that
    // took most of it.
    final dayCarriers = List<String?>.filled(daysIn, null);
    byDayCat.forEach((day, m) {
      if (day < 1 || day > daysIn) return;
      final top = m.entries.reduce((a, b) => a.value >= b.value ? a : b);
      dayInks[day - 1] = inkByCat[top.key];
      dayCarriers[day - 1] = catName(top.key);
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
    var paceInk = c.inkFaint;
    if (pace != null && pace.usual != null) {
      final gap = pace.projected - pace.usual!;
      if (gap.abs() >= 20_000 && gap > 0) paceInk = c.warn;
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

    final perDay = nowTotal ~/ math.max(1, elapsed);
    final topFour = stories.take(4).toList();
    final sectionPad = MediaQuery.paddingOf(context).bottom + Gap.x8;

    String heavyDayLabel() => heavyDay == null
        ? ''
        : LedgerDates.dayLabel(
            DateTime(_month.year, _month.month, heavyDay.$1),
          );

    return ListView(
      padding: EdgeInsets.fromLTRB(Gap.page, Gap.x4, Gap.page, sectionPad),
      children: [
        // ————— the month, in one figure, and the three numbers beside it —————
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
        StatTiles(
          tiles: [
            if (pace != null)
              StatTile(
                label: 'lands near',
                value: Inr.compact(_near(pace.projected)),
                tone: paceInk == c.warn ? c.warn : c.ink,
                sub: pace.usual == null
                    ? 'no usual month yet'
                    : (pace.projected - pace.usual!).abs() < 20_000
                    ? 'about a usual month'
                    : '${Inr.compact(_near((pace.projected - pace.usual!).abs()))} '
                          '${pace.projected > pace.usual! ? 'heavier' : 'lighter'} than usual',
              )
            else
              StatTile(
                label: 'the month',
                value: Inr.compact(nowTotal),
                tone: c.ink,
                sub: thenTotal == 0
                    ? 'nothing to compare'
                    : 'was ${Inr.compact(thenTotal)}',
              ),
            StatTile(
              label: 'a day',
              value: Inr.compact(perDay),
              tone: c.ink,
              sub: onNow ? '$elapsed days in' : 'over $daysIn days',
            ),
            StatTile(
              label: 'heaviest day',
              value: heavyDay == null ? '—' : Inr.compact(heavyDay.$2),
              tone: heavyDay == null ? c.inkFaint : c.ink,
              sub: heavyDay == null ? 'nothing yet' : heavyDayLabel(),
            ),
          ],
        ),
        // ————— the one line worth reading first —————
        if (lead != null)
          Padding(
            padding: const EdgeInsets.only(top: Gap.x3),
            child: Text(
              _headlineLine(lead, catName),
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                height: 1.45,
                color: lead.$2 ? c.inkFaint : c.warn,
              ),
            ),
          ),

        // ————— where it went: the ring, then the ranking —————
        //
        // The ring says the shape at a glance — four inks, the rest in
        // track — and the ranking under it says the same thing in order,
        // each category judged against its own last three months.
        if (stories.isNotEmpty) ...[
          const SectionHead('where it went'),
          Plate(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Donut(
                      segments: [
                        for (final s in topFour)
                          (
                            s.paise.toDouble(),
                            inkByCat[s.categoryId] ?? c.inkFaint,
                          ),
                      ],
                      total: nowTotal.toDouble(),
                      size: 116,
                      thickness: 13,
                      center: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${stories.length}',
                            style: LedgerType.amountTotal.copyWith(
                              fontSize: 20,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            stories.length == 1 ? 'category' : 'categories',
                            style: LedgerType.label.copyWith(
                              fontSize: 9,
                              color: c.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Gap.x4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final s in topFour)
                            _LegendRow(
                              ink: inkByCat[s.categoryId] ?? c.inkFaint,
                              name: catName(s.categoryId),
                              paise: s.paise,
                            ),
                          if (stories.length > 4)
                            _LegendRow(
                              ink: c.rule,
                              name: '${stories.length - 4} more',
                              paise: stories
                                  .skip(4)
                                  .fold(0, (t, s) => t + s.paise),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                  child: Divider(height: 1, color: c.rule),
                ),
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
                        builder: (_) => Scaffold(
                          body: SafeArea(
                            bottom: false,
                            child: BookPage(
                              initialMonth: _month,
                              initialCategory: story.categoryId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // ————— the running month: living against what happened once —————
        if (running.oneOffPaise > 0 && running.runningPaise > 0) ...[
          const SectionHead('the running month'),
          Plate(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SplitBar(
                  parts: [
                    (running.runningPaise, c.quill),
                    (running.oneOffPaise, c.inkFaint.withValues(alpha: 0.35)),
                  ],
                ),
                const SizedBox(height: Gap.x3),
                Row(
                  children: [
                    _Figure(
                      label: 'living',
                      value: Inr.compact(running.runningPaise),
                      sub: 'rent, food, rides, bills',
                      dot: c.quill,
                    ),
                    _Figure(
                      label: 'one-offs',
                      value: Inr.compact(running.oneOffPaise),
                      sub: running.oneOffs
                          .take(2)
                          .map((o) => o.$1.toLowerCase())
                          .join(', '),
                      dot: c.inkFaint.withValues(alpha: 0.35),
                    ),
                    _Figure(
                      label: 'came in',
                      value: incomeNow == 0 ? '—' : Inr.compact(incomeNow),
                      sub: incomeNow == 0
                          ? 'nothing yet'
                          : running.runningPaise > incomeNow
                          ? 'living runs past it'
                          : '${Inr.compact(incomeNow - running.runningPaise)} clear of living',
                      tone: incomeNow > 0 && running.runningPaise > incomeNow
                          ? c.warn
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: Gap.x3),
                Text(
                  _runningLine(running, incomeNow, onNow),
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12.5,
                    height: 1.4,
                    color: incomeNow > 0 && running.runningPaise > incomeNow
                        ? c.warn
                        : c.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ],

        // ————— in your hands: what he could move, and the habits in it —————
        if (inHands.totalPaise > 0) ...[
          const SectionHead('in your hands'),
          Plate(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SplitBar(
                  parts: [
                    (inHands.flexiblePaise, c.quill),
                    (inHands.fixedPaise, c.inkFaint.withValues(alpha: 0.35)),
                  ],
                ),
                const SizedBox(height: Gap.x3),
                Row(
                  children: [
                    _Figure(
                      label: 'yours to move',
                      value: Inr.compact(inHands.flexiblePaise),
                      sub:
                          '${(inHands.share * 100).round()}% of '
                          '${onNow ? 'the last $windowDays days' : 'the month'}',
                      dot: c.quill,
                    ),
                    _Figure(
                      label: 'rent & bills',
                      value: Inr.compact(inHands.fixedPaise),
                      sub: 'stays where it is',
                      dot: c.inkFaint.withValues(alpha: 0.35),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                  child: Divider(height: 1, color: c.rule),
                ),
                if (inHands.habits.isEmpty)
                  Text(
                    'nothing repeats enough to call a habit yet.',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 13,
                      color: c.inkFaint,
                    ),
                  )
                else
                  for (final (i, h) in inHands.habits.indexed)
                    _HabitRow(
                      key: ValueKey('habit-${h.key}'),
                      habit: h,
                      share: inHands.flexiblePaise == 0
                          ? 0
                          : (h.paise / inHands.flexiblePaise).clamp(0.0, 1.0),
                      last: i == inHands.habits.length - 1,
                      onOpen: h.search.isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                              LedgerRoute<void>(
                                builder: (_) => Scaffold(
                                  body: SafeArea(
                                    bottom: false,
                                    child: BookPage(
                                      initialMonth: _month,
                                      initialQuery: h.search,
                                    ),
                                  ),
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
          Plate(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DayChart(
                  key: ValueKey('days-$_month'),
                  month: _month,
                  daily: daily,
                  elapsed: elapsed,
                  heavyDay: heavyDay?.$1,
                  dayInks: dayInks,
                  carriers: dayCarriers,
                  average: perDay,
                ),
                const SizedBox(height: Gap.x3),
                Row(
                  children: [
                    _Figure(
                      label: 'heaviest day',
                      value: heavyDay == null ? '—' : Inr.compact(heavyDay.$2),
                      sub: heavyDay == null
                          ? 'nothing yet'
                          : heavyCarrier == null
                          ? heavyDayLabel()
                          : '${heavyDayLabel()} · mostly $heavyCarrier',
                    ),
                    _Figure(
                      label: 'quietest week',
                      value: quiet == null
                          ? '—'
                          : quiet.$2 == 0
                          ? '₹0'
                          : Inr.compact(quiet.$2),
                      sub: quiet == null
                          ? 'not a week in yet'
                          : '${quiet.$1}–${LedgerDates.ddMmm(DateTime(_month.year, _month.month, quiet.$1 + 6))}'
                                '${quiet.$2 == 0 ? ' · not a rupee' : ''}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // ————— where the weight moved: each swing as a bar off the axis —————
        if (shifts.isNotEmpty) ...[
          const SectionHead('where the weight moved'),
          Plate(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, s) in shifts.indexed)
                  _DivergeRow(
                    name: catName(s.categoryId),
                    deltaPaise: s.deltaPaise,
                    maxPaise: shifts
                        .map((x) => x.deltaPaise.abs())
                        .reduce(math.max),
                    tag: s.isNew
                        ? 'first seen'
                        : s.wentQuiet
                        ? 'went quiet'
                        : null,
                    last: i == shifts.length - 1,
                  ),
              ],
            ),
          ),
        ],

        // ————— the heaviest single lines —————
        if (heaviest.isNotEmpty) ...[
          const SectionHead('heaviest lines'),
          Plate(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in heaviest.take(3))
                  PlateRow(
                    leading: Medallion(
                      icon: LedgerIcons.resolve(catIcon(t.categoryId)),
                      ink: inkByCat[t.categoryId] ?? c.inkFaint,
                      size: 34,
                      iconSize: 16,
                    ),
                    title: t.title,
                    sub:
                        '${LedgerDates.ddMmm(t.at)} · ${catName(t.categoryId)}',
                    amount: Inr.format(t.amountPaise),
                    dense: true,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Two or more parts of one whole, laid end to end — living against
/// one-offs, yours against rent. Rounded at the ends, hairline gaps
/// between, so the proportion reads before the numbers do.
class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.parts});

  /// (paise, ink), in order.
  final List<(int, Color)> parts;
  static const height = 8.0;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final total = parts.fold(0, (t, p) => t + p.$1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: total <= 0
            ? ColoredBox(color: c.rule)
            : Row(
                children: [
                  for (final (i, p) in parts.indexed)
                    if (p.$1 > 0) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: math.max(1, (p.$1 * 1000 / total).round()),
                        child: ColoredBox(color: p.$2),
                      ),
                    ],
                ],
              ),
      ),
    );
  }
}

/// A small labelled figure in a row of them — the plate's numbers, set
/// under a one-word label with a line of context beneath.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.sub,
    this.dot,
    this.tone,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? dot;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LedgerType.label.copyWith(color: c.inkFaint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LedgerType.amountTotal.copyWith(
              fontSize: 16,
              color: tone ?? c.ink,
            ),
          ),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 1, right: Gap.x2),
              child: Text(
                sub!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LedgerType.bodyText.copyWith(
                  fontSize: 11,
                  height: 1.3,
                  color: c.inkFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One line of the ring's legend: the ink, the name, the share.
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.ink,
    required this.name,
    required this.paise,
  });

  final Color ink;
  final String name;
  final int paise;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
          ),
          const SizedBox(width: Gap.x2),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LedgerType.bodyText.copyWith(fontSize: 12.5, color: c.ink),
            ),
          ),
          const SizedBox(width: Gap.x2),
          Text(
            Inr.compact(paise),
            style: LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// A category's swing against last month as a bar off a centre axis:
/// left and in jama when it fell, right and in warn when it rose. The
/// figure sits at the end so the eye reads direction, size, then number.
class _DivergeRow extends StatelessWidget {
  const _DivergeRow({
    required this.name,
    required this.deltaPaise,
    required this.maxPaise,
    required this.last,
    this.tag,
  });

  final String name;
  final int deltaPaise;
  final int maxPaise;
  final bool last;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final rose = deltaPaise > 0;
    final ink = rose ? c.warn : c.jama;
    final fraction = maxPaise == 0 ? 0.0 : deltaPaise.abs() / maxPaise;
    final row = Padding(
      padding: EdgeInsets.only(top: 8, bottom: last ? 2 : 8),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 13,
                    color: c.ink,
                  ),
                ),
                if (tag != null)
                  Text(
                    tag!,
                    style: LedgerType.label.copyWith(color: c.inkFaint),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Gap.x2),
          Expanded(
            child: SizedBox(
              height: 14,
              child: CustomPaint(
                painter: _DivergePainter(
                  fraction: fraction,
                  rose: rose,
                  ink: ink,
                  axis: c.rule,
                ),
              ),
            ),
          ),
          const SizedBox(width: Gap.x2),
          Text(
            '${rose ? '+' : '−'}${Inr.format(deltaPaise.abs())}',
            style: LedgerType.amount.copyWith(fontSize: 13, color: ink),
          ),
        ],
      ),
    );
    if (last) return row;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      child: row,
    );
  }
}

class _DivergePainter extends CustomPainter {
  const _DivergePainter({
    required this.fraction,
    required this.rose,
    required this.ink,
    required this.axis,
  });

  final double fraction;
  final bool rose;
  final Color ink;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    canvas.drawLine(
      Offset(mid, 0),
      Offset(mid, size.height),
      Paint()
        ..color = axis
        ..strokeWidth = 1,
    );
    final half = mid - 2;
    final len = half * fraction.clamp(0.0, 1.0);
    if (len <= 0) return;
    final top = size.height / 2 - 4;
    final rect = rose
        ? Rect.fromLTWH(mid + 2, top, len, 8)
        : Rect.fromLTWH(mid - 2 - len, top, len, 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = ink,
    );
  }

  @override
  bool shouldRepaint(_DivergePainter old) =>
      old.fraction != fraction || old.rose != rose || old.ink != ink;
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

/// The month, a bar a day: weekends washed faintly behind, Mondays
/// numbered under the line, the average drawn across as a dash, and the
/// heaviest day at full voice. A finger on the chart names the day, what
/// it cost and what carried it.
class _DayChart extends StatefulWidget {
  const _DayChart({
    super.key,
    required this.month,
    required this.daily,
    required this.elapsed,
    required this.dayInks,
    required this.carriers,
    required this.average,
    this.heavyDay,
  });

  final DateTime month;
  final List<int> daily;
  final int elapsed;
  final List<Color?> dayInks;
  final List<String?> carriers;

  /// What a day cost on average, for the dash across the chart.
  final int average;
  final int? heavyDay;

  @override
  State<_DayChart> createState() => _DayChartState();
}

class _DayChartState extends State<_DayChart> {
  int? _scrub;

  void _read(Offset p, double width) {
    final n = widget.daily.length;
    if (n == 0) return;
    final i = (p.dx / width * n).floor().clamp(0, n - 1);
    if (i >= widget.elapsed) return;
    if (i != _scrub) {
      HapticFeedback.selectionClick();
      setState(() => _scrub = i);
    }
  }

  void _lift() {
    if (_scrub != null) setState(() => _scrub = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final s = _scrub;
    final heavy = widget.heavyDay;
    final String readout;
    final Color readoutInk;
    if (s != null) {
      final day = DateTime(widget.month.year, widget.month.month, s + 1);
      final carrier = widget.carriers[s];
      readout =
          '${LedgerDates.dayLabel(day)} · ${Inr.format(widget.daily[s])}'
          '${carrier == null || widget.daily[s] == 0 ? '' : ' · $carrier'}';
      readoutInk = c.ink;
    } else if (heavy != null) {
      readout =
          'heaviest ${LedgerDates.ddMmm(DateTime(widget.month.year, widget.month.month, heavy))} '
          '· ${Inr.compact(widget.average)} a day on average';
      readoutInk = c.inkFaint;
    } else {
      readout = 'touch a day to read it';
      readoutInk = c.inkFaint;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          readout,
          key: const ValueKey('day-chart-readout'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LedgerType.bodyText.copyWith(fontSize: 12, color: readoutInk),
        ),
        const SizedBox(height: Gap.x2),
        SizedBox(
          height: 108,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              key: const ValueKey('day-chart-touch'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _read(d.localPosition, box.maxWidth),
              onTapUp: (_) => _lift(),
              onTapCancel: _lift,
              onHorizontalDragStart: (d) =>
                  _read(d.localPosition, box.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  _read(d.localPosition, box.maxWidth),
              onHorizontalDragEnd: (_) => _lift(),
              onHorizontalDragCancel: _lift,
              child: DrawIn(
                duration: const Duration(milliseconds: 700),
                builder: (context, t) => CustomPaint(
                  painter: _DayBarsPainter(
                    month: widget.month,
                    daily: widget.daily,
                    elapsed: widget.elapsed,
                    heavyDay: widget.heavyDay,
                    dayInks: widget.dayInks,
                    average: widget.average,
                    scrub: _scrub,
                    ink: c.ink,
                    quill: c.quill,
                    rule: c.rule,
                    faint: c.inkFaint,
                    wash: c.paperRaised,
                    progress: t,
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayBarsPainter extends CustomPainter {
  _DayBarsPainter({
    required this.month,
    required this.daily,
    required this.elapsed,
    required this.heavyDay,
    required this.dayInks,
    required this.average,
    required this.scrub,
    required this.ink,
    required this.quill,
    required this.rule,
    required this.faint,
    required this.wash,
    required this.textScaler,
    this.progress = 1,
  });

  final DateTime month;
  final List<int> daily;
  final int elapsed;
  final int? heavyDay;
  final List<Color?> dayInks;
  final int average;
  final int? scrub;
  final Color ink;
  final Color quill;
  final Color rule;
  final Color faint;
  final Color wash;
  final TextScaler textScaler;

  /// 0→1: the bars rise left to right, each on the tail of the last.
  final double progress;

  static const _labelBand = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (daily.isEmpty) return;
    final base = size.height - _labelBand;
    final n = math.min(elapsed, daily.length);
    final slot = size.width / daily.length;

    // Weekends, washed behind the bars.
    for (var i = 0; i < daily.length; i++) {
      final wd = DateTime(month.year, month.month, i + 1).weekday;
      if (wd == DateTime.saturday || wd == DateTime.sunday) {
        canvas.drawRect(
          Rect.fromLTWH(slot * i, 0, slot, base),
          Paint()..color = wash.withValues(alpha: 0.55),
        );
      }
    }

    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = rule
        ..strokeWidth = 1,
    );

    var maxV = 0;
    for (var i = 0; i < n; i++) {
      maxV = math.max(maxV, daily[i]);
    }
    maxV = math.max(maxV, average);
    final top = 10.0;
    double yFor(int v) => maxV <= 0 ? base : base - (base - top) * (v / maxV);

    // The average, dashed across, labelled at the right edge.
    if (average > 0 && maxV > 0) {
      final y = yFor(average);
      final dash = Paint()
        ..color = faint.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 3, size.width), y),
          dash,
        );
      }
      final label = TextPainter(
        text: TextSpan(
          text: 'avg ${Inr.compact(average)}',
          style: TextStyle(
            fontSize: 9,
            color: faint,
            fontFamily: 'Spline Sans Mono',
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      canvas.drawRect(
        Rect.fromLTWH(
          size.width - label.width - 6,
          y - label.height - 1,
          label.width + 6,
          label.height + 1,
        ),
        Paint()..color = wash.withValues(alpha: 0.85),
      );
      label.paint(
        canvas,
        Offset(size.width - label.width - 3, y - label.height - 1),
      );
      label.dispose();
    }

    final barW = math.min(slot * 0.62, 7.0);
    final tickPaint = Paint()
      ..color = rule
      ..strokeWidth = math.max(barW * 0.5, 1.0);
    for (var i = 0; i < n; i++) {
      final t = Curves.easeOutCubic.transform(
        ((progress * (daily.length + 6) - i) / 6).clamp(0.0, 1.0),
      );
      if (t <= 0) break;
      final x = slot * (i + 0.5);
      if (daily[i] <= 0 || maxV <= 0) {
        canvas.drawLine(Offset(x, base), Offset(x, base - 2.5 * t), tickPaint);
        continue;
      }
      final h = (base - yFor(daily[i])) * t;
      final heavy = (i + 1) == heavyDay;
      final catInk = i < dayInks.length ? dayInks[i] : null;
      final chosen = scrub == null || scrub == i;
      final baseInk = catInk ?? (heavy ? quill : ink);
      final alpha = !chosen
          ? 0.25
          : heavy || scrub == i
          ? 1.0
          : (catInk == null ? 0.45 : 0.75);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - barW / 2, base - h, barW, h),
          Radius.circular(barW / 2),
        ),
        Paint()..color = baseInk.withValues(alpha: alpha),
      );
    }

    // Mondays, numbered under the line — the month's own ruler.
    for (var i = 0; i < daily.length; i++) {
      final d = DateTime(month.year, month.month, i + 1);
      final first = i == 0;
      if (d.weekday != DateTime.monday && !first) continue;
      final x = slot * (i + 0.5);
      canvas.drawLine(
        Offset(x, base),
        Offset(x, base + 3),
        Paint()
          ..color = rule
          ..strokeWidth = 1,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontSize: 9,
            color: faint,
            fontFamily: 'Spline Sans Mono',
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      label.paint(canvas, Offset(x - label.width / 2, base + 4));
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(_DayBarsPainter old) =>
      old.progress != progress ||
      old.daily != daily ||
      old.elapsed != elapsed ||
      old.heavyDay != heavyDay ||
      old.dayInks != dayInks ||
      old.scrub != scrub ||
      old.average != average;
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

/// One habit on the plate, three lines deep: what and how much, how
/// often and at what pace, then its share of what was his to move — and
/// the two things he can do about it.
class _HabitRow extends StatelessWidget {
  const _HabitRow({
    super.key,
    required this.habit,
    required this.share,
    required this.last,
    required this.onOpen,
    required this.onFine,
  });

  final Habit habit;

  /// 0..1 of the flexible spend this habit took.
  final double share;
  final bool last;
  final VoidCallback? onOpen;
  final VoidCallback onFine;

  static IconData _icon(Habit h) {
    switch (h.label) {
      case 'rides':
        return Icons.two_wheeler_outlined;
      case 'chai and coffee':
        return Icons.coffee_outlined;
      case 'ordered in':
        return Icons.delivery_dining_outlined;
      case 'drinks':
        return Icons.local_drink_outlined;
      case 'smokes':
        return Icons.smoking_rooms_outlined;
    }
    return switch (h.kind) {
      HabitKind.often => Icons.restaurant_outlined,
      HabitKind.shop => Icons.storefront_outlined,
      HabitKind.standing => Icons.autorenew_rounded,
      HabitKind.weekend => Icons.weekend_outlined,
      HabitKind.unnamed => Icons.edit_outlined,
    };
  }

  String get _sub => switch (habit.kind) {
    HabitKind.often => '${habit.count} times in ${habit.days} days',
    HabitKind.shop => '${habit.count} visits in ${habit.days} days',
    HabitKind.standing =>
      '${habit.count} standing ${habit.count == 1 ? 'charge' : 'charges'}',
    HabitKind.weekend => '${habit.count} weekend days',
    HabitKind.unnamed => '${habit.count} lines with no title',
  };

  String? get _pace => switch (habit.kind) {
    HabitKind.often => '≈${Inr.compact(roundNear(habit.monthPaise))} /mo',
    HabitKind.shop => '${(share * 100).round()}% of yours',
    HabitKind.standing => 'a year',
    HabitKind.weekend => '${(share * 100).round()}% of yours',
    HabitKind.unnamed => null,
  };

  String get _foot => switch (habit.kind) {
    HabitKind.often =>
      '${Inr.compact(roundNear(habit.yearPaise))} a year · half back '
          '${Inr.compact(roundNear(habit.yearPaise ~/ 2))}',
    HabitKind.shop =>
      '${Inr.compact(roundNear(habit.yearPaise))} a year at this pace',
    HabitKind.standing => 'kept for a year, or a tap to stop',
    HabitKind.weekend => 'more than the weekdays carried',
    HabitKind.unnamed => 'a word as you write is all it takes',
  };

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final h = habit;
    final unnamed = h.kind == HabitKind.unnamed;
    final body = Padding(
      padding: EdgeInsets.only(top: 8, bottom: last ? 2 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Medallion(
            icon: _icon(h),
            ink: unnamed ? c.inkFaint : c.quill,
            size: 34,
            iconSize: 16,
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
                      Inr.format(h.paise),
                      style: LedgerType.amountTotal.copyWith(
                        fontSize: 15,
                        color: unnamed ? c.inkFaint : c.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LedgerType.bodyText.copyWith(
                          fontSize: 12,
                          color: c.inkFaint,
                        ),
                      ),
                    ),
                    if (_pace != null)
                      Text(
                        _pace!,
                        style: LedgerType.amount.copyWith(
                          fontSize: 11.5,
                          color: c.inkFaint,
                        ),
                      ),
                  ],
                ),
                if (!unnamed) ...[
                  const SizedBox(height: 6),
                  RoundedBar(fraction: share, ink: c.quill, height: 4),
                ],
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _foot,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LedgerType.label.copyWith(color: c.inkFaint),
                      ),
                    ),
                    const SizedBox(width: Gap.x2),
                    if (onOpen != null) ...[
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
                      const SizedBox(width: Gap.x3),
                    ],
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
