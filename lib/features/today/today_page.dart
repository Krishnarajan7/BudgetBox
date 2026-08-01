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
import '../../core/widgets/seal.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/budget_math.dart';
import '../../data/repos/goal_repo.dart';
import '../../data/repos/recurring_repo.dart';

/// The day's page: it greets, it counts, it knows what yesterday looked
/// like and when salary lands, and at night it takes the stamp. The screen
/// the whole app answers to.
class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  String _name = 'Krish';
  int _salaryDay = 1;
  final Set<int> _seenTxnIds = {};
  bool _firstEmission = true;

  @override
  void initState() {
    super.initState();
    _loadFacts();
  }

  Future<void> _loadFacts() async {
    final settings = ref.read(settingsRepoProvider);
    final name = await settings.name();
    final salaryDay = await settings.salaryDay();
    if (mounted) {
      setState(() {
        _name = name;
        _salaryDay = salaryDay;
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

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: Gap.page),
              children: [
                const LedgerAppBar(),
                const SizedBox(height: Gap.x4),
                Text(
                  '$_greeting, $_name — ${_dateLabel(now)}',
                  style: LedgerType.label.copyWith(color: c.inkFaint),
                ),
                const SizedBox(height: 2),
                CountUp(
                  value: todayPaise,
                  format: Inr.format,
                  style: LedgerType.heroAmount
                      .copyWith(fontSize: 42, color: c.ink)
                      .copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                const SizedBox(height: 2),
                _reactiveSubline(c, today.length, todayPaise, yesterdayPaise),
                const SizedBox(height: Gap.x3),
                const _PinStrip(),
                const RuleHeader('this month'),
                DrawIn(
                  builder: (context, p) => PaceChart(
                    daily: cumulative,
                    elapsedDays: now.day,
                    totalDays: LedgerDates.daysInMonth(now),
                    progress: p,
                  ),
                ),
                _monthFooter(c, monthPaise, monthLimit, pace, now),
                const _GoalStrip(),
                const RuleHeader('coming up'),
                const _Upcoming(),
                const RuleHeader('the last fortnight'),
                _MiniHeat(expenses: expenses, now: now),
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
                const Center(child: _CloseDay()),
                const SizedBox(height: Gap.x6),
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

  Widget _monthFooter(LedgerColors c, int monthPaise, int monthLimit,
      BudgetPace pace, DateTime now) {
    final left = (monthLimit - monthPaise).clamp(0, 1 << 62);
    final days = _daysToSalary(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CountUp(
              value: monthPaise,
              format: Inr.format,
              style: LedgerType.amountTotal.copyWith(color: c.ink),
            ),
            Text(
              '  of ${Inr.format(monthLimit)}',
              style:
                  LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
            ),
            const Spacer(),
            Text(
              switch (pace.status) {
                BudgetStatus.onPace => 'on pace',
                BudgetStatus.projectedOver =>
                  '${Inr.format(pace.projectedOverspendPaise)} over at this rate',
                BudgetStatus.over =>
                  '${Inr.format(-pace.remainingPaise)} past the line',
                BudgetStatus.pending => 'waiting on bills',
              },
              style: LedgerType.bodyStrong.copyWith(
                fontSize: 12,
                color: switch (pace.status) {
                  BudgetStatus.onPace => c.jama,
                  BudgetStatus.projectedOver => c.warn,
                  BudgetStatus.over => c.seal,
                  BudgetStatus.pending => c.inkFaint,
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          '${Inr.format(left)} left · $days ${days == 1 ? 'day' : 'days'} to salary',
          style: LedgerType.amount.copyWith(fontSize: 11, color: c.inkFaint),
        ),
      ],
    );
  }
}

/// The first unfinished goal, riding along under the month.
class _GoalStrip extends ConsumerWidget {
  const _GoalStrip();

  static String _month(DateTime d) {
    const s = ['January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'];
    return '${s[d.month - 1]}';
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
            Row(
              children: [
                Text(goal.goal.name,
                    style: LedgerType.bodyStrong
                        .copyWith(fontSize: 13, color: c.ink)),
                const Spacer(),
                CountUp(
                  value: goal.donePaise,
                  format: Inr.format,
                  style: LedgerType.amount
                      .copyWith(fontSize: 12, color: c.ink),
                ),
                Text(
                  ' of ${Inr.format(goal.goal.targetPaise)}',
                  style: LedgerType.amount
                      .copyWith(fontSize: 12, color: c.inkFaint),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DrawIn(
              builder: (context, p) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 5,
                  child: Stack(children: [
                    Container(color: c.rule.withValues(alpha: 0.45)),
                    FractionallySizedBox(
                      widthFactor: (goal.fraction * p).clamp(0.01, 1.0),
                      child: Container(color: c.jama),
                    ),
                  ]),
                ),
              ),
            ),
            if (eta != null) ...[
              const SizedBox(height: 4),
              Text(
                'on pace for ${_month(eta)} ${eta.year}',
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

/// Fourteen small days, spend-tinted, quiet ones pale — the month's texture
/// at a glance.
class _MiniHeat extends StatelessWidget {
  const _MiniHeat({required this.expenses, required this.now});

  final List<Txn> expenses;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final days = <DateTime>[
      for (var i = 13; i >= 0; i--)
        DateTime(now.year, now.month, now.day).subtract(Duration(days: i)),
    ];
    final totals = <int>[
      for (final d in days)
        expenses
            .where((t) =>
                t.at.year == d.year &&
                t.at.month == d.month &&
                t.at.day == d.day)
            .fold(0, (s, t) => s + t.amountPaise),
    ];
    final maxPaise =
        totals.fold(0, (a, b) => a > b ? a : b).clamp(1, 1 << 62);
    final quiet = totals.where((t) => t == 0).length;

    return Padding(
      padding: const EdgeInsets.only(top: Gap.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final (i, t) in totals.indexed) ...[
                Expanded(
                  child: InkIn(
                    delay: Duration(milliseconds: i * 20),
                    child: Container(
                      height: 18,
                      decoration: BoxDecoration(
                        color: t == 0
                            ? c.paperRaised
                            : Color.lerp(
                                c.paper, c.quill, 0.12 + 0.68 * t / maxPaise),
                        border:
                            t == 0 ? Border.all(color: c.rule) : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                if (i != totals.length - 1) const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            quiet == 0
                ? 'no quiet days in the last fortnight'
                : '$quiet quiet ${quiet == 1 ? 'day' : 'days'} in the last fortnight',
            style:
                LedgerType.bodyText.copyWith(fontSize: 11, color: c.inkFaint),
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
                Pressable(
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    await pins.stamp(p);
                  },
                  child: LedgerChip(
                    '${p.title.split(' ').first} · ${Inr.format(p.amountPaise)}',
                  ),
                ),
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

/// The once-daily ritual, with its full weight: the pill gives way to the
/// stamp before the page settles sealed.
class _CloseDay extends ConsumerStatefulWidget {
  const _CloseDay();

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

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final db = ref.watch(dbProvider);
    final key = LedgerDates.dayKey(DateTime.now());

    return StreamBuilder<DaySeal?>(
      stream: (db.select(db.daySeals)..where((s) => s.date.equals(key)))
          .watchSingleOrNull(),
      builder: (context, snapshot) {
        final sealed = snapshot.data != null;
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
                  'day closed · good night, Krish',
                  style: LedgerType.bodyText
                      .copyWith(fontSize: 12, color: c.inkFaint),
                ),
              ),
            ],
          );
        }
        return Pressable(
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
                Icon(Icons.check_box_outline_blank,
                    size: 14, color: c.inkFaint),
                const SizedBox(width: Gap.x2),
                Text('close the day',
                    style: LedgerType.bodyStrong
                        .copyWith(fontSize: 13, color: c.inkFaint)),
              ],
            ),
          ),
        );
      },
    );
  }
}
