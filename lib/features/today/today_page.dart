import 'dart:math' as math;

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/ledger_app_bar.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/seal.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/budget_math.dart';
import '../../data/repos/goal_repo.dart';
import '../../data/repos/recurring_repo.dart';
import '../add/money_moves.dart' show quietDays, showCatchUpSheet;
import '../book/book_page.dart' show whereItWent;
import '../insights/insights_page.dart';

/// The day's page: it greets, it counts, it knows what yesterday looked
/// like and when salary lands, and at night it takes the stamp. The screen
/// the whole app answers to.
class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

/// Small counts in the book's hand: 'three', not '3'.
String _spelled(int n) {
  const words = [
    'two', 'three', 'four', 'five', 'six', 'seven',
    'eight', 'nine', 'ten', 'eleven', 'twelve',
  ];
  return (n >= 2 && n <= 12) ? words[n - 2] : '$n';
}

class _TodayPageState extends ConsumerState<TodayPage> {
  String _name = 'Krish';
  int _salaryDay = 1;
  String? _intent;
  bool _yesterdaySealed = false;
  (int, int)? _birthday;
  bool _burst = false;
  final Set<int> _seenTxnIds = {};
  bool _firstEmission = true;

  @override
  void initState() {
    super.initState();
    _loadFacts();
  }

  Future<void> _loadFacts() async {
    final settings = ref.read(settingsRepoProvider);
    final db = ref.read(dbProvider);
    final name = await settings.name();
    final salaryDay = await settings.salaryDay();
    final intent = await settings.intent();
    final birthday = await settings.birthday();
    final now = DateTime.now();
    // The one day a year the book celebrates — once, then it composes itself.
    var burst = false;
    if (birthday != null &&
        now.day == birthday.$1 &&
        now.month == birthday.$2 &&
        await settings.birthdayBurstDue(now.year)) {
      burst = true;
      await settings.markBirthdayBurst(now.year);
    }
    final yKey = LedgerDates.dayKey(DateTime(now.year, now.month, now.day - 1));
    final ySeal = await (db.select(db.daySeals)
          ..where((s) => s.date.equals(yKey)))
        .getSingleOrNull();
    if (mounted) {
      setState(() {
        _name = name;
        _salaryDay = salaryDay;
        _intent = intent;
        _yesterdaySealed = ySeal != null;
        _birthday = birthday;
        _burst = burst;
      });
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'up late';
    if (h < 12) return 'good morning';
    if (h < 17) return 'good afternoon';
    return 'good evening';
  }

  /// One line that occasionally knows things: salary landing beats the date,
  /// a closed yesterday gets a quiet nod, and most days it's just the date.
  String _greetingLine(DateTime now) {
    final base = '$_greeting, $_name';
    final bd = _birthday;
    if (bd != null && now.day == bd.$1 && now.month == bd.$2) {
      return 'happy birthday, $_name — the book buys the chai to-day';
    }
    if (now.day == _salaryDay) return '$base — salary lands to-day';
    if (_daysToSalary(now) == 1) return '$base — salary lands to-morrow';
    if (_yesterdaySealed) return '$base — yesterday is sealed';
    return '$base — ${_dateLabel(now)}';
  }

  static String _dateLabel(DateTime d) {
    const days = [
      'monday', 'tuesday', 'wednesday', 'thursday',
      'friday', 'saturday', 'sunday',
    ];
    const months = [
      'january', 'february', 'march', 'april', 'may', 'june',
      'july', 'august', 'september', 'october', 'november', 'december',
    ];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  int _daysToSalary(DateTime now) {
    var next = DateTime(now.year, now.month, _salaryDay);
    if (!next.isAfter(DateTime(now.year, now.month, now.day))) {
      next = DateTime(now.year, now.month + 1, _salaryDay);
    }
    return next.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final txns = ref.watch(txnRepoProvider);
    final budgets = ref.watch(budgetRepoProvider);
    final now = DateTime.now();

    return StreamBuilder<List<Budget>>(
      stream: budgets.watchAll(),
      builder: (context, budgetSnap) {
        final monthLimit = (budgetSnap.data ?? const <Budget>[])
            .fold<int>(0, (s, b) => s + b.limitPaise);
        return StreamBuilder<List<Txn>>(
          stream: txns.watchRange(
              LedgerDates.monthStart(now), LedgerDates.monthEnd(now)),
          builder: (context, snapshot) {
            final month = snapshot.data ?? const <Txn>[];
            final expenses =
                month.where((t) => t.type == TxnType.expense).toList();
            final today =
                expenses.where((t) => t.at.day == now.day).toList()
                  ..sort((a, b) => b.at.compareTo(a.at));
            final todayPaise =
                today.fold(0, (s, t) => s + t.amountPaise);
            final yesterdayPaise = now.day > 1
                ? expenses
                    .where((t) => t.at.day == now.day - 1)
                    .fold(0, (s, t) => s + t.amountPaise)
                : null;
            final monthPaise =
                expenses.fold(0, (s, t) => s + t.amountPaise);

            // Which of today's lines are genuinely new since last frame.
            final freshIds = <int>{};
            if (snapshot.hasData) {
              for (final t in today) {
                if (!_seenTxnIds.contains(t.id) && !_firstEmission) {
                  freshIds.add(t.id);
                }
              }
              _seenTxnIds.addAll(today.map((t) => t.id));
              _firstEmission = false;
            }

            final cumulative = <int>[];
            var running = 0;
            for (var d = 1; d <= now.day; d++) {
              running += expenses
                  .where((t) => t.at.day == d)
                  .fold(0, (s, t) => s + t.amountPaise);
              cumulative.add(running);
            }

            final pace = BudgetPace(
              spentPaise: monthPaise,
              limitPaise: monthLimit,
              elapsedDays: now.day,
              totalDays: LedgerDates.daysInMonth(now),
            );

            // The modules, in the order setup promised: 'leaks' watches the
            // month and what's about to charge, 'goal' leads with the saving,
            // 'truth' (or an unasked book) keeps the plain order.
            final monthModule = <Widget>[
              if (monthLimit == 0)
                LedgerCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                    child: Text(
                      'No budget lines yet — the month runs unmeasured. '
                      'Draw them in plans when you want a pace to keep.',
                      style: LedgerType.bodyText
                          .copyWith(fontSize: 13, color: c.inkFaint),
                    ),
                  ),
                )
              else
              LedgerCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RuleHeader('this month'),
                    const SizedBox(height: Gap.x3),
                    // The number that decides the evening is what is LEFT —
                    // so it leads, in the book's own serif, with the verdict
                    // stamped beside it and the arithmetic as a footnote.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CountUp(
                                value:
                                    (monthLimit - monthPaise).clamp(0, 1 << 62),
                                format: Inr.format,
                                style: LedgerType.heroAmount
                                    .copyWith(fontSize: 34, color: c.ink),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'left · ${_daysToSalary(now)} '
                                '${_daysToSalary(now) == 1 ? 'day' : 'days'} to salary',
                                style: LedgerType.amount.copyWith(
                                    fontSize: 11, color: c.inkFaint),
                              ),
                            ],
                          ),
                        ),
                        _VerdictChip(pace: pace),
                      ],
                    ),
                    const SizedBox(height: Gap.x3),
                    DrawIn(
                      builder: (context, p) => PaceChart(
                        daily: cumulative,
                        elapsedDays: now.day,
                        totalDays: LedgerDates.daysInMonth(now),
                        progress: p,
                      ),
                    ),
                    const SizedBox(height: Gap.x2),
                    Row(
                      children: [
                        Text(
                          '${Inr.format(monthPaise)} spent',
                          style: LedgerType.amount
                              .copyWith(fontSize: 11, color: c.inkFaint),
                        ),
                        const Spacer(),
                        Text(
                          'of ${Inr.format(monthLimit)}',
                          style: LedgerType.amount
                              .copyWith(fontSize: 11, color: c.inkFaint),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ];
            const goalModule = <Widget>[
              LedgerCard(child: _GoalStrip()),
            ];
            const upcomingModule = <Widget>[
              LedgerCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RuleHeader('coming up'),
                    _Upcoming(),
                  ],
                ),
              ),
            ];
            final whereModule = <Widget>[
              if (expenses.isNotEmpty)
                _WhereCard(expenses: expenses),
            ];
            final heatModule = <Widget>[
              LedgerCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RuleHeader('the month, day by day'),
                    _MonthHeat(
                        expenses: expenses, monthTxns: month, now: now),
                  ],
                ),
              ),
            ];
            final ordered = switch (_intent) {
              'leaks' => [
                  ...monthModule,
                  ...whereModule,
                  ...upcomingModule,
                  ...goalModule,
                  ...heatModule,
                ],
              'goal' => [
                  ...goalModule,
                  ...monthModule,
                  ...whereModule,
                  ...upcomingModule,
                  ...heatModule,
                ],
              _ => [
                  ...monthModule,
                  ...whereModule,
                  ...goalModule,
                  ...upcomingModule,
                  ...heatModule,
                ],
            };

            final page = ListView(
              padding: const EdgeInsets.symmetric(horizontal: Gap.page),
              children: [
                const LedgerAppBar(),
                const SizedBox(height: Gap.x4),
                Text(
                  _greetingLine(now),
                  style: LedgerType.label.copyWith(color: c.inkFaint),
                ),
                const SizedBox(height: 2),
                CountUp(
                  value: todayPaise,
                  format: Inr.format,
                  style: LedgerType.heroAmount
                      .copyWith(fontSize: 64, color: c.ink)
                      .copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                const SizedBox(height: Gap.x2),
                // The day's entry underlined in the binding's vermilion —
                // the one stroke of red the page carries while it is open.
                InkIn(
                  delay: const Duration(milliseconds: 150),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(width: 72, height: 3, color: c.quill),
                  ),
                ),
                const SizedBox(height: 2),
                _reactiveSubline(c, today.length, todayPaise, yesterdayPaise),
                const SizedBox(height: Gap.x3),
                const _PinStrip(),
                ...ordered,
                const RuleHeader("today's page"),
                if (today.isEmpty)
                  InkIn(
                    delay: const Duration(milliseconds: 250),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: Gap.x3),
                      child: Text(
                        'A blank page. The plus below fills it.',
                        style: LedgerType.bodyText
                            .copyWith(color: c.inkFaint),
                      ),
                    ),
                  )
                else
                  _TodayLines(today: today, freshIds: freshIds),
                const SizedBox(height: Gap.x4),
                Center(child: _CloseDay(name: _name)),
                const SizedBox(height: Gap.x6),
              ],
            );
            if (!_burst) return page;
            // Once a year, and only with motion allowed: the seals rain.
            if (Motion.reduced(context)) return page;
            return Stack(
              children: [
                page,
                Positioned.fill(
                  child: IgnorePointer(
                    child: _BirthdayRain(
                        onDone: () => setState(() => _burst = false)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _reactiveSubline(
      LedgerColors c, int count, int todayPaise, int? yesterdayPaise) {
    final String line;
    if (count == 0) {
      line = 'nothing written yet';
    } else {
      final entries = '$count ${count == 1 ? 'entry' : 'entries'}';
      if (yesterdayPaise == null || yesterdayPaise == 0) {
        line = '$entries so far';
      } else if (todayPaise < yesterdayPaise) {
        line =
            '$entries · ${Inr.format(yesterdayPaise - todayPaise)} lighter than yesterday';
      } else if (todayPaise > yesterdayPaise) {
        line =
            '$entries · ${Inr.format(todayPaise - yesterdayPaise)} past yesterday';
      } else {
        line = '$entries · dead even with yesterday';
      }
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Text(
        line,
        key: ValueKey(line),
        style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
      ),
    );
  }

}

/// The next two things the recurring shelf will ask for. Each line answers a
/// tap with a small sheet that can stamp the charge as paid.
/// Forty small things falling once a year: seals, paper squares, a few
/// status-ink dots. Deterministic per index — no randomness source, same
/// shower every birthday, which is exactly the kind of joke this book tells.
class _BirthdayRain extends StatelessWidget {
  const _BirthdayRain({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final colors = [c.seal, c.jama, c.warn, c.quill];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 2800),
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
                    left: n(i, 1) * box.maxWidth +
                        math.sin(t * 6.28 * (1 + n(i, 2)) + i) * 18,
                    top: -40 +
                        (box.maxHeight + 80) *
                            Curves.easeIn.transform(
                                ((t * (0.7 + 0.5 * n(i, 3))).clamp(0.0, 1.0))),
                    child: Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0) * 0.9,
                      child: Transform.rotate(
                        angle: t * 6.28 * (n(i, 4) - 0.5) * 3,
                        child: Container(
                          width: 6 + 6 * n(i, 5),
                          height: 6 + 6 * n(i, 5),
                          decoration: BoxDecoration(
                            color: colors[i % colors.length]
                                .withValues(alpha: 0.9),
                            borderRadius:
                                BorderRadius.circular(i % 3 == 0 ? 99 : 2),
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

/// The month's weight by category, in brief — and the way into the full
/// story. Top four bars only: Today answers at a glance, Insights explains.
class _WhereCard extends ConsumerWidget {
  const _WhereCard({required this.expenses});

  final List<Txn> expenses;

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
        final slices = whereItWent(
          [for (final t in expenses) (t.categoryId, t.amountPaise)],
          top: 4,
        );
        if (slices.isEmpty) return const SizedBox.shrink();
        return LedgerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RuleHeader(
                'where it went',
                trailing: Pressable(
                  onTap: () => Navigator.of(context).push(
                    LedgerRoute<void>(builder: (_) => const InsightsPage()),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'the whole story',
                        style: LedgerType.bodyStrong
                            .copyWith(fontSize: 11, color: c.quill),
                      ),
                      const SizedBox(width: 3),
                      PenArrow(size: 11, color: c.quill),
                    ],
                  ),
                ),
              ),
              for (final (i, s) in slices.indexed)
                WhereRow(
                  key: ValueKey('tw-${s.isOther ? 'other' : s.categoryId}'),
                  label: s.isOther
                      ? 'everything else'
                      : (cats[s.categoryId]?.name ?? 'unfiled'),
                  iconKey: s.isOther ? null : cats[s.categoryId]?.icon,
                  amount: Inr.format(s.paise),
                  frac: slices.first.paise <= 0
                      ? 0
                      : s.paise / slices.first.paise,
                  stagger: i,
                  last: i == slices.length - 1,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The month's verdict, stamped small: a hard-cornered chip in the status
/// ink, washed faint behind. One glance, one colour, no gauge.
class _VerdictChip extends StatelessWidget {
  const _VerdictChip({required this.pace});

  final BudgetPace pace;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final (label, tone) = switch (pace.status) {
      BudgetStatus.onPace => ('on pace', c.jama),
      BudgetStatus.projectedOver => (
          '${Inr.format(pace.projectedOverspendPaise)} over at this rate',
          c.warn
        ),
      BudgetStatus.over =>
        ('${Inr.format(-pace.remainingPaise)} past the line', c.warn),
      BudgetStatus.pending => ('waiting on bills', c.inkFaint),
    };
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

class _Upcoming extends ConsumerWidget {
  const _Upcoming();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    return StreamBuilder<List<DueItem>>(
      stream: ref.watch(recurringRepoProvider).watchUpcoming(),
      builder: (context, snapshot) {
        final next = (snapshot.data ?? const <DueItem>[]).take(2).toList();
        if (next.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.x2),
            child: Text(
              'Nothing due soon.',
              style: LedgerType.bodyText
                  .copyWith(fontSize: 13, color: c.inkFaint),
            ),
          );
        }
        return Column(
          children: [
            for (final d in next)
              Pressable(
                onTap: () => _paySheet(context, ref, d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x2),
                  child: Row(
                    children: [
                      // A leaf off the calendar: the day large, its month
                      // small above, cut hard like everything in the book.
                      Container(
                        width: 42,
                        height: 46,
                        decoration: BoxDecoration(
                          color: c.paper,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              LedgerDates.ddMmm(d.due).split(' ').last,
                              style: LedgerType.label
                                  .copyWith(fontSize: 9, color: c.inkFaint),
                            ),
                            Text(
                              '${d.due.day}',
                              style: LedgerType.amount.copyWith(
                                  fontSize: 17,
                                  color: c.ink,
                                  fontWeight: FontWeight.w600),
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
                              style: LedgerType.bodyStrong
                                  .copyWith(fontSize: 14, color: c.ink),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'the usual — tap when paid',
                              style: LedgerType.bodyText.copyWith(
                                  fontSize: 11, color: c.inkFaint),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        Inr.format(d.recurring.amountPaise),
                        style: LedgerType.amount
                            .copyWith(fontSize: 14, color: c.ink),
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

  Future<void> _paySheet(
      BuildContext context, WidgetRef ref, DueItem d) async {
    final recurring = ref.read(recurringRepoProvider);
    final paid = await showLedgerSheet<bool>(
      context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return Padding(
          padding:
              const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
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
                style: LedgerType.bodyText
                    .copyWith(fontSize: 13, color: c.inkFaint),
              ),
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
        );
      },
    );
    if (paid == true) {
      HapticFeedback.lightImpact();
      // The written line inks itself onto today's page; the upcoming row
      // steps aside as the stream moves on.
      await recurring.markPaid(d.recurring);
    }
  }
}

/// The first unfinished goal, riding along under the month.
class _GoalStrip extends ConsumerWidget {
  const _GoalStrip();

  static String _month(DateTime d) {
    const s = ['January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'];
    return s[d.month - 1];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    return StreamBuilder<List<GoalView>>(
      stream: ref.watch(goalRepoProvider).watchViews(),
      builder: (context, snap) {
        final goal =
            (snap.data ?? const <GoalView>[]).where((g) => !g.reached).firstOrNull;
        if (goal == null) return const SizedBox.shrink();
        final eta = goal.etaFrom(DateTime.now());
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RuleHeader('still saving'),
            const SizedBox(height: Gap.x3),
            // What has been put away is the object; where it is going is the
            // caption; when it lands is the punchline.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CountUp(
                  value: goal.donePaise,
                  format: Inr.format,
                  style: LedgerType.heroAmount
                      .copyWith(fontSize: 30, color: c.ink),
                ),
                const SizedBox(width: Gap.x2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    'of ${Inr.format(goal.goal.targetPaise)} — ${goal.goal.name}',
                    style: LedgerType.bodyText
                        .copyWith(fontSize: 12, color: c.inkFaint),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.x2),
            // The stroke of red the goal has earned so far.
            DrawIn(
              builder: (context, p) => SizedBox(
                height: 8,
                child: Row(
                  children: [
                    Expanded(
                      flex: ((goal.fraction * p).clamp(0.004, 1.0) * 1000)
                          .round(),
                      child: Container(color: c.quill),
                    ),
                    Expanded(
                      flex: 1000 -
                          ((goal.fraction * p).clamp(0.004, 1.0) * 1000)
                              .round(),
                      child: Container(
                          color: c.rule.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ),
            ),
            if (eta != null) ...[
              const SizedBox(height: 6),
              Text(
                'lands ${_month(eta)} ${eta.year}, at this pace',
                style: LedgerType.bodyText
                    .copyWith(fontSize: 11, color: c.inkFaint),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The month so far as the shared heat grid — spend-tinted cells, quiet ones
/// pale. Hold a day to peek at what it wrote; a gap in the week offers the
/// catch-up sheet, gently.
class _MonthHeat extends StatelessWidget {
  const _MonthHeat({
    required this.expenses,
    required this.monthTxns,
    required this.now,
  });

  final List<Txn> expenses;
  final List<Txn> monthTxns;
  final DateTime now;

  void _peek(BuildContext context, int day) {
    HapticFeedback.selectionClick();
    final d = DateTime(now.year, now.month, day);
    final lines = expenses.where((t) => t.at.day == day).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final total = lines.fold(0, (s, t) => s + t.amountPaise);
    showLedgerSheet<void>(
      context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return Padding(
          padding:
              const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
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
              Text(
                Inr.format(total),
                style: LedgerType.heroAmount
                    .copyWith(fontSize: 28, color: c.ink),
              ),
              const SizedBox(height: Gap.x2),
              if (lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x2),
                  child: Text(
                    'a quiet day — nothing written',
                    style: LedgerType.bodyText
                        .copyWith(fontSize: 13, color: c.inkFaint),
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
    final dayTotals = <int>[
      for (var d = 1; d <= now.day; d++)
        expenses
            .where((t) => t.at.day == d)
            .fold(0, (s, t) => s + t.amountPaise),
    ];
    final quiet = quietDays(monthTxns, now);

    return Padding(
      padding: const EdgeInsets.only(top: Gap.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeatGrid(
            dayTotalsPaise: dayTotals,
            stagger: true,
            onDayLongPress: (day) => _peek(context, day),
          ),
          const SizedBox(height: Gap.x1),
          if (quiet.isEmpty)
            Text(
              'no quiet days this week',
              style: LedgerType.bodyText
                  .copyWith(fontSize: 11, color: c.inkFaint),
            )
          else
            Pressable(
              onTap: () => showCatchUpSheet(context),
              child: Text.rich(
                TextSpan(
                  text:
                      '${_spelled(quiet.length)} quiet ${quiet.length == 1 ? 'day' : 'days'} back there — ',
                  children: [
                    TextSpan(
                      text: 'catch up the quiet days?',
                      style: LedgerType.bodyStrong
                          .copyWith(fontSize: 11, color: c.quill),
                    ),
                  ],
                ),
                style: LedgerType.bodyText
                    .copyWith(fontSize: 11, color: c.inkFaint),
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayLines extends ConsumerWidget {
  const _TodayLines({required this.today, required this.freshIds});

  final List<Txn> today;
  final Set<int> freshIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountRepoProvider);
    return StreamBuilder<List<Account>>(
      stream: accounts.watchAll(),
      builder: (context, snapshot) {
        final names = {
          for (final a in snapshot.data ?? const <Account>[]) a.id: a.name,
        };
        return Column(
          children: [
            for (final (i, t) in today.indexed)
              InkIn(
                play: freshIds.contains(t.id),
                child: LedgerLine(
                  leading:
                      '${t.at.hour.toString().padLeft(2, '0')}:${t.at.minute.toString().padLeft(2, '0')}',
                  title: t.title,
                  detail: names[t.accountId],
                  amount: Inr.format(t.amountPaise),
                  last: i == today.length - 1,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PinStrip extends ConsumerWidget {
  const _PinStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
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
                _PinChip(pin: p),
                const SizedBox(width: Gap.x2),
              ],
              Text('one tap, stamped',
                  style: LedgerType.bodyText
                      .copyWith(fontSize: 11, color: c.inkFaint)),
            ],
          ),
        );
      },
    );
  }
}

/// The one-tap repeat, given its full ritual: the chip gives under the
/// finger, a small seal lands on it with the stamp's haptic, and only then
/// does the entry ink itself onto today's page below as the hero counts up.
class _PinChip extends ConsumerStatefulWidget {
  const _PinChip({required this.pin});

  final Pinned pin;

  @override
  ConsumerState<_PinChip> createState() => _PinChipState();
}

class _PinChipState extends ConsumerState<_PinChip> {
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
            child: LedgerChip(
              '${p.title.split(' ').first} · ${Inr.format(p.amountPaise)}',
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: !_stamping
                    ? const SizedBox.shrink()
                    : Center(
                        child: StampIn(size: 24, onStamped: _landed),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The once-daily ritual, with its full weight: the pill gives way to the
/// stamp before the page settles sealed. Beneath it, the book keeps quiet
/// count of the evenings it has been closed in a row.
class _CloseDay extends ConsumerStatefulWidget {
  const _CloseDay({required this.name});

  final String name;

  @override
  ConsumerState<_CloseDay> createState() => _CloseDayState();
}

class _CloseDayState extends ConsumerState<_CloseDay> {
  bool _stamping = false;

  Future<void> _close() async {
    if (_stamping) return;
    HapticFeedback.mediumImpact();
    setState(() => _stamping = true);
    // Let the stamp land before the sealed state takes over.
    await Future<void>.delayed(const Duration(milliseconds: 480));
    if (!mounted) return;
    final db = ref.read(dbProvider);
    await db.into(db.daySeals).insert(
          DaySealsCompanion(
              date: Value(LedgerDates.dayKey(DateTime.now()))),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Consecutive sealed days ending today (if sealed) or yesterday.
  static int _streak(Set<String> dates, DateTime now) {
    var day = DateTime(now.year, now.month, now.day);
    if (!dates.contains(LedgerDates.dayKey(day))) {
      day = DateTime(day.year, day.month, day.day - 1);
    }
    var n = 0;
    while (dates.contains(LedgerDates.dayKey(day))) {
      n++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final db = ref.watch(dbProvider);
    final key = LedgerDates.dayKey(DateTime.now());

    return StreamBuilder<List<DaySeal>>(
      stream: db.select(db.daySeals).watch(),
      builder: (context, snapshot) {
        final dates = {
          for (final s in snapshot.data ?? const <DaySeal>[]) s.date,
        };
        final sealed = dates.contains(key);
        final streak = _streak(dates, DateTime.now());
        final whisper = streak >= 2
            ? Padding(
                padding: const EdgeInsets.only(top: Gap.x2),
                child: Text(
                  '${_spelled(streak)} evenings in a row',
                  style: LedgerType.bodyText
                      .copyWith(fontSize: 11, color: c.inkFaint),
                ),
              )
            : null;

        if (sealed || _stamping) {
          return Column(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: sealed && !_stamping ? 1 : 0, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (context, v, child) => Transform.rotate(
                  angle: 6 * (1 - v) * 3.14159 / 180,
                  child: Transform.scale(
                    scale: 1.6 - 0.6 * v.clamp(0, 1),
                    child: Opacity(opacity: v.clamp(0, 1), child: child),
                  ),
                ),
                child: const Seal(size: 40),
              ),
              const SizedBox(height: Gap.x2),
              InkIn(
                delay: const Duration(milliseconds: 300),
                child: Text(
                  'day closed · good night, ${widget.name}',
                  style: LedgerType.bodyText
                      .copyWith(fontSize: 12, color: c.inkFaint),
                ),
              ),
              ?whisper,
            ],
          );
        }
        return Column(
          children: [
            Pressable(
              onTap: _close,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Gap.x4, vertical: Gap.x2),
                decoration: BoxDecoration(
                  border: Border.all(color: c.rule, width: 1),
                  borderRadius: BorderRadius.circular(Corner.chip),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The chop before it lands — the mark this tap will make,
                    // not a form's checkbox.
                    SealOutline(size: 15, color: c.inkFaint),
                    const SizedBox(width: Gap.x2),
                    Text('close the day',
                        style: LedgerType.bodyStrong
                            .copyWith(fontSize: 13, color: c.inkFaint)),
                  ],
                ),
              ),
            ),
            ?whisper,
          ],
        );
      },
    );
  }
}
