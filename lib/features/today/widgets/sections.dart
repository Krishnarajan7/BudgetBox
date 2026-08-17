import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../core/inr.dart';
import '../../../core/tokens.dart';
import '../../../core/typography.dart';
import '../../../core/widgets/ledger_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/pen_marks.dart';
import '../../../core/widgets/seal.dart';
import '../../../core/widgets/sheets.dart';
import '../../../data/api/endpoints/coaching_api.dart';
import '../../../data/db.dart';
import '../../../data/providers.dart';
import '../../../data/repos/budget_math.dart';
import '../../../data/repos/goal_repo.dart';
import '../../../data/repos/recurring_repo.dart';
import '../../add/money_moves.dart' show quietDays, showCatchUpSheet;
import '../../book/book_page.dart' show WhereSlice;
import 'ledger_rows.dart';

/// Today's sections. One color language runs through all of them: a
/// category's ink is the same on its entry chip, its share of the month
/// bar, and its dot on the calendar — color does the comprehension work,
/// so nothing needs a legend. Everything renders settled; motion belongs
/// to the entries and the rituals.

const _monthsLower = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdaysShort = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// The serif figure the mockup taught the page: Fraunces for money, sized
/// to its station.
TextStyle _figure(LedgerColors c, double size) =>
    LedgerType.heroAmount.copyWith(fontSize: size, color: c.ink);

/// One coaching insight, worth a header but not a box.
class CoachingNote extends StatelessWidget {
  const CoachingNote({
    super.key,
    required this.insight,
    required this.onDismiss,
  });

  final CoachingInsight insight;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final evidence = insight.evidence;
    final source = switch (insight.kind) {
      CoachingKind.merchantSurge =>
        '${evidence.comparisonMonths.length} comparable months · ${evidence.transactionIds.length} entries',
      CoachingKind.repeatedDiscretionary =>
        '${evidence.count ?? evidence.transactionIds.length} entries · marked ${evidence.classification?.name ?? 'discretionary'} by you',
      CoachingKind.budgetRisk =>
        'current pace against ${evidence.budgetName ?? 'your budget'}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHead('worth noticing'),
        Text(
          insight.title,
          style: LedgerType.title.copyWith(fontSize: 19, color: c.ink),
        ),
        const SizedBox(height: Gap.x2),
        Text(
          insight.message,
          style: LedgerType.bodyText.copyWith(
            fontSize: 13,
            height: 1.45,
            color: c.ink,
          ),
        ),
        const SizedBox(height: Gap.x2),
        Row(
          children: [
            Expanded(
              child: Text(
                'why: $source',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 10,
                  color: c.inkFaint,
                ),
              ),
            ),
            Pressable(
              onTap: onDismiss,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.x2,
                  vertical: Gap.x1,
                ),
                child: Text(
                  'not useful',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 11,
                    color: c.inkFaint,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The month in one breath: "august so far ····· ₹2,646", the budget
/// standing on the left, and — when last month has something to say — how
/// this month's pace compares at the same day, on the right. A derived
/// sentence instead of a chart.
class MonthPulse extends StatelessWidget {
  const MonthPulse({
    super.key,
    required this.monthPaise,
    required this.monthLimit,
    required this.balance,
    required this.pace,
    required this.now,
    required this.daysToSalary,
    required this.prevThroughPaise,
  });

  final int monthPaise;
  final int monthLimit;
  final ({int amountPaise, bool over}) balance;
  final BudgetPace pace;
  final DateTime now;
  final int daysToSalary;

  /// Last month's spend through this same day-of-month; 0 when the book
  /// has no last month.
  final int prevThroughPaise;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final monthName = _monthsLower[now.month - 1];
    final prevName = _monthsLower[(now.month + 10) % 12];

    final (String standing, Color standingColor) = monthLimit == 0
        ? ('no budget set for $monthName', c.inkFaint)
        : balance.over
        ? ('${Inr.format(-balance.amountPaise)} over budget', c.warn)
        : pace.status == BudgetStatus.projectedOver
        ? (
            '${Inr.format(balance.amountPaise)} left · ${Inr.format(pace.projectedOverspendPaise)} over at this rate',
            c.warn,
          )
        : (
            '${Inr.format(balance.amountPaise)} left · '
                '$daysToSalary ${daysToSalary == 1 ? 'day' : 'days'} to salary',
            c.inkFaint,
          );

    final diff = prevThroughPaise - monthPaise;
    final String? compare;
    final Color compareColor;
    if (prevThroughPaise <= 0 || diff == 0) {
      compare = null;
      compareColor = c.inkFaint;
    } else if (diff > 0) {
      compare = '${Inr.format(diff)} slower than $prevName';
      compareColor = c.jama;
    } else {
      compare = '${Inr.format(-diff)} faster than $prevName';
      compareColor = c.warn;
    }

    return Padding(
      padding: const EdgeInsets.only(top: Gap.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$monthName so far',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
              const Spacer(),
              Text(Inr.format(monthPaise), style: _figure(c, 22)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  standing,
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12,
                    color: standingColor,
                  ),
                ),
              ),
              if (compare != null) ...[
                const SizedBox(width: Gap.x3),
                Text(
                  compare,
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12,
                    color: compareColor,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The last few entries across the month, not just today's — a page with
/// one entry a day still reads as a lived-in book. Each line wears its
/// category's ink as a small chip; fresh lines still ink themselves in.
class LatelySection extends ConsumerWidget {
  const LatelySection({
    super.key,
    required this.recent,
    required this.catColor,
    required this.freshIds,
    required this.now,
  });

  final List<Txn> recent;
  final Map<int?, Color> catColor;
  final Set<int> freshIds;
  final DateTime now;

  String _when(Txn t) {
    if (t.at.year == now.year && t.at.month == now.month) {
      if (t.at.day == now.day) {
        final h12 = t.at.hour % 12 == 0 ? 12 : t.at.hour % 12;
        final mm = t.at.minute.toString().padLeft(2, '0');
        return '$h12:$mm ${t.at.hour < 12 ? 'am' : 'pm'}';
      }
      if (t.at.day == now.day - 1) return 'yesterday';
    }
    return '${_weekdaysShort[t.at.weekday - 1]} ${t.at.day}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final db = ref.watch(dbProvider);
    return StreamBuilder<List<Category>>(
      stream: db.select(db.categories).watch(),
      builder: (context, snap) {
        final cats = {
          for (final cat in snap.data ?? const <Category>[]) cat.id: cat,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHead('lately'),
            if (recent.isEmpty)
              const EmptyRuledLines(line: 'No entries yet this month.')
            else
              for (final t in recent)
                InkIn(
                  play: freshIds.contains(t.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.x2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: catColor[t.categoryId] ?? c.inkFaint,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        ),
                        const SizedBox(width: Gap.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.title,
                                style: LedgerType.bodyText.copyWith(
                                  fontSize: 15,
                                  color: c.ink,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_when(t)} · ${cats[t.categoryId]?.name ?? 'unfiled'}',
                                style: LedgerType.bodyText.copyWith(
                                  fontSize: 12,
                                  color: c.inkFaint,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Gap.x3),
                        Text(Inr.format(t.amountPaise), style: _figure(c, 17)),
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// The month's weight by category: one segmented bar in the categories'
/// own inks, then each line with its share and its figure in the column.
/// Shared between Today (current month, "see all" trailing) and the Book
/// (any month, tap a line to filter the ledger to it).
class WhereSection extends ConsumerWidget {
  const WhereSection({
    super.key,
    required this.slices,
    required this.monthPaise,
    required this.catColor,
    this.trailing,
    this.onSliceTap,
  });

  final List<WhereSlice> slices;
  final int monthPaise;
  final Map<int?, Color> catColor;

  /// Optional header trailing — Today hangs its "see all" link here.
  final Widget? trailing;

  /// Optional tap on a category line (never the "everything else" fold).
  final void Function(WhereSlice slice)? onSliceTap;

  Color _ink(LedgerColors c, WhereSlice s) =>
      s.isOther ? c.inkFaint : (catColor[s.categoryId] ?? c.inkFaint);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    if (slices.isEmpty || monthPaise <= 0) return const SizedBox.shrink();
    final db = ref.watch(dbProvider);
    return StreamBuilder<List<Category>>(
      stream: db.select(db.categories).watch(),
      builder: (context, snap) {
        final cats = {
          for (final cat in snap.data ?? const <Category>[]) cat.id: cat,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHead('where it went', trailing: trailing),
            const SizedBox(height: Gap.x1),
            // The month as one bar, segment widths honest to the paise.
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 4,
                child: Row(
                  children: [
                    for (final (i, s) in slices.indexed) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: s.paise,
                        child: ColoredBox(color: _ink(c, s)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.x2),
            for (final s in slices) _sliceRow(c, s, cats),
          ],
        );
      },
    );
  }

  Widget _sliceRow(LedgerColors c, WhereSlice s, Map<int, Category> cats) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _ink(c, s),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: Gap.x3),
          Expanded(
            child: Text(
              s.isOther
                  ? 'everything else'
                  : (cats[s.categoryId]?.name ?? 'unfiled'),
              style: LedgerType.bodyText.copyWith(fontSize: 14, color: c.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${(s.paise * 100 / monthPaise).round()}%',
            style: LedgerType.amount.copyWith(fontSize: 11, color: c.inkFaint),
          ),
          const SizedBox(width: Gap.x3),
          SizedBox(
            width: 76,
            child: Text(
              Inr.format(s.paise),
              textAlign: TextAlign.right,
              style: _figure(c, 16),
            ),
          ),
        ],
      ),
    );
    final tap = onSliceTap;
    if (tap == null || s.isOther || s.categoryId == null) return row;
    return Pressable(onTap: () => tap(s), child: row);
  }
}

/// The first unfinished goal: the figure saved, the fraction as a settled
/// bar, the landing month as a plain fact.
class GoalSection extends ConsumerWidget {
  const GoalSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    return StreamBuilder<List<GoalView>>(
      stream: ref.watch(goalRepoProvider).watchViews(),
      builder: (context, snap) {
        final goal = (snap.data ?? const <GoalView>[])
            .where((g) => !g.reached)
            .firstOrNull;
        if (goal == null) return const SizedBox.shrink();
        final eta = goal.etaFrom(DateTime.now());
        final frac = goal.fraction.clamp(0.004, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHead('still saving'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Inr.format(goal.donePaise), style: _figure(c, 22)),
                const SizedBox(width: Gap.x2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    'of ${Inr.format(goal.goal.targetPaise)} — ${goal.goal.name}',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 12,
                      color: c.inkFaint,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.x2),
            SizedBox(
              height: 6,
              child: Row(
                children: [
                  Expanded(
                    flex: (frac * 1000).round(),
                    child: Container(color: c.quill),
                  ),
                  Expanded(
                    flex: 1000 - (frac * 1000).round(),
                    child: Container(color: c.rule.withValues(alpha: 0.45)),
                  ),
                ],
              ),
            ),
            if (eta != null) ...[
              const SizedBox(height: 6),
              Text(
                'on pace for ${_months[eta.month - 1]} ${eta.year}',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 11,
                  color: c.inkFaint,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The next two things the recurring shelf will ask for. Each line answers a
/// tap with a small sheet that can stamp the charge as paid.
class UpcomingSection extends ConsumerWidget {
  const UpcomingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    return StreamBuilder<List<DueItem>>(
      stream: ref.watch(recurringRepoProvider).watchUpcoming(),
      builder: (context, snapshot) {
        final next = (snapshot.data ?? const <DueItem>[]).take(2).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHead('coming up'),
            if (next.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.x1),
                child: Text(
                  'Nothing due in the next two weeks.',
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 13,
                    color: c.inkFaint,
                  ),
                ),
              )
            else
              for (final d in next)
                Pressable(
                  onTap: () => _paySheet(context, ref, d),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.x2),
                    child: Row(
                      children: [
                        // A leaf off the calendar: the day large, its month
                        // small above, ruled like everything on the page.
                        Container(
                          width: 42,
                          height: 46,
                          decoration: BoxDecoration(
                            border: Border.all(color: c.rule),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                LedgerDates.ddMmm(d.due).split(' ').last,
                                style: LedgerType.label.copyWith(
                                  fontSize: 9,
                                  color: c.inkFaint,
                                ),
                              ),
                              Text(
                                '${d.due.day}',
                                style: LedgerType.amount.copyWith(
                                  fontSize: 17,
                                  color: c.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Gap.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.recurring.title,
                                style: LedgerType.bodyStrong.copyWith(
                                  fontSize: 14,
                                  color: c.ink,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                'tap when paid',
                                style: LedgerType.bodyText.copyWith(
                                  fontSize: 11,
                                  color: c.inkFaint,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          Inr.format(d.recurring.amountPaise),
                          style: _figure(c, 16),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Future<void> _paySheet(BuildContext context, WidgetRef ref, DueItem d) async {
    final recurring = ref.read(recurringRepoProvider);
    // The pockets, read before the sheet stands — paying always says from
    // where, and one tap moves it.
    final db = ref.read(dbProvider);
    final pockets =
        (await (db.select(
              db.accounts,
            )..where((a) => a.archived.equals(false))).get())
            .where((a) => !a.keptAside)
            .toList();
    if (!context.mounted) return;
    var fromId = pockets.any((a) => a.id == d.recurring.accountId)
        ? d.recurring.accountId
        : (pockets.isEmpty ? d.recurring.accountId : pockets.first.id);
    final paid = await showLedgerSheet<bool>(
      context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return StatefulBuilder(
          builder: (context, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                const SizedBox(height: Gap.x2),
                Text(
                  d.recurring.title,
                  style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  'lands ${LedgerDates.ddMmm(d.due)} · ${Inr.format(d.recurring.amountPaise)}',
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 13,
                    color: c.inkFaint,
                  ),
                ),
                if (pockets.isNotEmpty) ...[
                  const SizedBox(height: Gap.x3),
                  Text(
                    'paid from',
                    style: LedgerType.label.copyWith(color: c.inkFaint),
                  ),
                  const SizedBox(height: Gap.x2),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final a in pockets) ...[
                          LedgerChip(
                            a.name,
                            selected: fromId == a.id,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setSheet(() => fromId = a.id);
                            },
                          ),
                          const SizedBox(width: Gap.x2),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: Gap.x4),
                Pressable(
                  onTap: () => Navigator.of(context).pop(true),
                  child: AbsorbPointer(
                    child: FilledButton(
                      onPressed: () {},
                      child: Text(
                        'Paid — stamp ${Inr.format(d.recurring.amountPaise)}',
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Not yet'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (paid == true) {
      HapticFeedback.lightImpact();
      // The written line inks itself onto today's page; the upcoming row
      // steps aside as the stream moves on.
      await recurring.markPaid(d.recurring, accountId: fromId);
    }
  }
}

/// The month as a real calendar: weekday columns, days ahead receding,
/// today ringed, and under each written day a dot in the ink of the
/// category that carried it. One derived line below — the loudest day —
/// because a specific fact beats a decoration.
///
/// Shared between Today (current month, [today] set, catch-up link shown)
/// and the Book's month view (any month, [today] null, every day written).
class CalendarSection extends StatelessWidget {
  const CalendarSection({
    super.key,
    required this.expenses,
    required this.monthTxns,
    required this.month,
    required this.catColor,
    this.today,
    this.onDayTap,
  });

  final List<Txn> expenses;
  final List<Txn> monthTxns;

  /// Any date inside the month being shown.
  final DateTime month;
  final Map<int?, Color> catColor;

  /// Day-of-month of "today" when this IS the current month; null for a
  /// finished month — no ring, no future days, no catch-up offer.
  final int? today;

  /// Overrides the built-in day peek sheet (the Book opens its day page).
  final ValueChanged<int>? onDayTap;

  void _peek(BuildContext context, int day) {
    HapticFeedback.selectionClick();
    final d = DateTime(month.year, month.month, day);
    final lines = expenses.where((t) => t.at.day == day).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final total = lines.fold(0, (s, t) => s + t.amountPaise);
    showLedgerSheet<void>(
      context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.x2),
              Text(
                LedgerDates.dayLabel(d),
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: 2),
              Text(Inr.format(total), style: _figure(c, 28)),
              const SizedBox(height: Gap.x2),
              if (lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x2),
                  child: Text(
                    'no entries this day',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 13,
                      color: c.inkFaint,
                    ),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final (i, t) in lines.indexed)
                          LedgerLine(
                            leading:
                                '${t.at.hour.toString().padLeft(2, '0')}:${t.at.minute.toString().padLeft(2, '0')}',
                            title: t.title,
                            amount: Inr.format(t.amountPaise),
                            last: i == lines.length - 1,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final totalDays = LedgerDates.daysInMonth(month);
    final written = today ?? totalDays;

    // Per day: total spend, for the loudest-day line.
    final dayTotals = List<int>.filled(totalDays + 1, 0);
    for (final t in expenses) {
      dayTotals[t.at.day] += t.amountPaise;
    }
    var loudest = 0;
    var loudestPaise = 0;
    for (var d = 1; d <= written && d <= totalDays; d++) {
      if (dayTotals[d] > loudestPaise) {
        loudest = d;
        loudestPaise = dayTotals[d];
      }
    }

    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    final rows = ((leading + totalDays) / 7).ceil();
    final quiet = today == null
        ? const <int>[]
        : quietDays(monthTxns, DateTime(month.year, month.month, today!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHead(
          'the month, day by day',
          trailing: today == null
              ? null
              : Text(
                  '$today of $totalDays',
                  style: LedgerType.amount.copyWith(
                    fontSize: 11,
                    color: c.inkFaint,
                  ),
                ),
        ),
        const SizedBox(height: Gap.x1),
        Row(
          children: [
            for (final w in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: LedgerType.label.copyWith(
                      fontSize: 9,
                      color: c.inkFaint.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.x2),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(child: _cell(context, c, r * 7 + col - leading + 1)),
            ],
          ),
        if (loudest > 0) ...[
          const SizedBox(height: Gap.x2),
          Text(
            '${_weekdaysShort[DateTime(month.year, month.month, loudest).weekday - 1]} '
            '$loudest was the loudest day · ${Inr.format(dayTotals[loudest])}',
            style: LedgerType.bodyText.copyWith(
              fontSize: 11,
              color: c.inkFaint,
            ),
          ),
        ],
        if (quiet.isNotEmpty) ...[
          const SizedBox(height: Gap.x1),
          Pressable(
            onTap: () => showCatchUpSheet(context),
            child: Text.rich(
              TextSpan(
                text:
                    '${quiet.length} ${quiet.length == 1 ? 'day' : 'days'} unrecorded this week — ',
                children: [
                  TextSpan(
                    text: 'catch up',
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 11,
                      color: c.quill,
                    ),
                  ),
                ],
              ),
              style: LedgerType.bodyText.copyWith(
                fontSize: 11,
                color: c.inkFaint,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _cell(BuildContext context, LedgerColors c, int day) {
    final totalDays = LedgerDates.daysInMonth(month);
    if (day < 1 || day > totalDays) return const SizedBox(height: 42);
    final isToday = today != null && day == today;
    final future = today != null && day > today!;
    final hasSpend = !future && expenses.any((t) => t.at.day == day);
    final dot = hasSpend ? _dotColorOf(c, day) : null;

    final number = Text(
      '$day',
      style: (isToday ? LedgerType.bodyStrong : LedgerType.bodyText).copyWith(
        fontSize: 12,
        color: future
            ? c.inkFaint.withValues(alpha: 0.35)
            : isToday
            ? c.ink
            : c.inkFaint,
      ),
    );

    final marker = isToday
        ? Container(
            width: 11,
            height: 11,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.quill, width: 1.1),
            ),
            child: dot == null
                ? null
                : Container(
                    width: 4.5,
                    height: 4.5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dot,
                    ),
                  ),
          )
        : dot == null
        ? const SizedBox(width: 11, height: 11)
        : Center(
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
            ),
          );

    final cell = SizedBox(
      height: 42,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [number, const SizedBox(height: 4), marker],
      ),
    );
    if (future || !hasSpend && !isToday) return cell;
    final open = onDayTap ?? (d) => _peek(context, d);
    return Pressable(onTap: () => open(day), child: cell);
  }

  Color? _dotColorOf(LedgerColors c, int day) {
    final byCat = <int?, int>{};
    for (final t in expenses.where((t) => t.at.day == day)) {
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amountPaise;
    }
    if (byCat.isEmpty) return null;
    final top = byCat.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return catColor[top.key] ?? c.inkFaint;
  }
}

/// The pinned one-tap repeats, as hairline tabs on the page instead of
/// raised blocks. The stamp ritual on tap is unchanged — that motion marks
/// a state change, which is exactly when the page is allowed to move.
class PinStrip extends ConsumerWidget {
  const PinStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(pinnedRepoProvider);
    return StreamBuilder<List<Pinned>>(
      stream: pins.watchAll(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in items) ...[
                _PinTab(pin: p),
                const SizedBox(width: Gap.x4),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The one-tap repeat, given its full ritual: the tab gives under the
/// finger, a small seal lands on it with the stamp's haptic, and only then
/// does the entry ink itself onto today's page as the hero rolls.
class _PinTab extends ConsumerStatefulWidget {
  const _PinTab({required this.pin});

  final Pinned pin;

  @override
  ConsumerState<_PinTab> createState() => _PinTabState();
}

class _PinTabState extends ConsumerState<_PinTab> {
  bool _stamping = false;

  void _tap() {
    if (_stamping) return;
    setState(() => _stamping = true);
  }

  Future<void> _landed() async {
    // The seal has pressed down — now the entry goes into the book, so the
    // fresh line inks in right behind the stamp.
    await ref.read(pinnedRepoProvider).stamp(widget.pin);
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (mounted) setState(() => _stamping = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final p = widget.pin;
    return Pressable(
      haptic: false, // the stamp's landing is the haptic
      onTap: _tap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            duration: Motion.quick,
            opacity: _stamping ? 0.35 : 1,
            // No box: the chop-outline before the words says "tap to
            // stamp" — the affordance is the mark, not a border.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SealOutline(size: 11, color: c.inkFaint),
                  const SizedBox(width: 5),
                  Text.rich(
                    TextSpan(
                      text: '${p.title.split(' ').first} ',
                      children: [
                        TextSpan(
                          text: Inr.format(p.amountPaise),
                          style: LedgerType.amount.copyWith(
                            fontSize: 12,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 13,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: !_stamping
                    ? const SizedBox.shrink()
                    : Center(child: StampIn(size: 24, onStamped: _landed)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
