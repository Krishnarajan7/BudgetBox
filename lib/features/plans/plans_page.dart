import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/cat_mark.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/ledger_app_bar.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pickers.dart';
import '../../core/widgets/seal.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/budget_math.dart';
import '../../data/repos/budget_repo.dart';
import '../../data/repos/goal_repo.dart';
import '../../data/repos/recurring_repo.dart';

/// True when a budget's line has drifted more than [threshold] away from
/// the spending it's supposed to describe — the cue for a suggested line.
bool budgetLineDrifted({
  required int limitPaise,
  required int avgPaise,
  double threshold = 0.25,
}) {
  if (avgPaise <= 0 || limitPaise <= 0) return false;
  return (limitPaise - avgPaise).abs() / avgPaise > threshold;
}

class PlansPage extends ConsumerStatefulWidget {
  const PlansPage({super.key});

  @override
  ConsumerState<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends ConsumerState<PlansPage> {
  static const _tabs = ['budgets', 'recurring', 'goals'];

  int _tab = 0;

  /// Which way the page turned last — the slide follows the thumb.
  int _dir = 1;

  void _go(int i) {
    if (i == _tab) return;
    setState(() {
      _dir = i > _tab ? 1 : -1;
      _tab = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Gap.page),
      children: [
        const LedgerAppBar(title: 'Plans'),
        const SizedBox(height: Gap.x3),
        Row(
          children: [
            for (final (i, label) in _tabs.indexed) ...[
              LedgerChip(label, selected: _tab == i, onTap: () => _go(i)),
              const SizedBox(width: Gap.x2),
            ],
          ],
        ),
        const SizedBox(height: Gap.x4),
        _PageTurn(
          tag: _tab,
          dir: _dir,
          child: switch (_tab) {
            0 => const _BudgetsTab(),
            1 => const _RecurringTab(),
            _ => const _GoalsTab(),
          },
        ),
        const SizedBox(height: Gap.x6),
      ],
    );
  }
}

/// One page sliding off another: a cross-fade with a hair of directional
/// travel, on the book's one spring. [tag] names the page on show; [dir] is
/// +1 when the book moves forward.
class _PageTurn extends StatelessWidget {
  const _PageTurn({
    required this.tag,
    required this.dir,
    required this.child,
  });

  final Object tag;
  final int dir;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The stack hands its children loose constraints; the page wants the
    // full width it would have had on the paper.
    final page = KeyedSubtree(
      key: ValueKey(tag),
      child: SizedBox(width: double.infinity, child: child),
    );
    if (Motion.reduced(context)) return page;
    return AnimatedSwitcher(
      duration: Motion.spring,
      switchInCurve: Motion.curve,
      switchOutCurve: Motion.curve,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, anim) {
        final incoming = child.key == ValueKey(tag);
        final dx = (incoming ? dir : -dir) * 0.045;
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(
              begin: Offset(dx, 0),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        );
      },
      child: page,
    );
  }
}

// ————— budgets —————

class _BudgetsTab extends ConsumerStatefulWidget {
  const _BudgetsTab();

  @override
  ConsumerState<_BudgetsTab> createState() => _BudgetsTabState();
}

class _BudgetsTabState extends ConsumerState<_BudgetsTab> {
  /// The month being read — always the first of a month.
  DateTime _month = LedgerDates.monthStart(DateTime.now());

  /// +1 when the last flip went forward in time.
  int _dir = 1;

  late final Future<Map<int, int>> _upcoming =
      ref.read(recurringRepoProvider).upcomingByCategory();
  late final Future<Map<int, int>> _suggested =
      ref.read(budgetRepoProvider).suggestFromHistory();

  Stream<List<BudgetView>>? _viewStream;
  DateTime? _streamMonth;
  Map<int, int>? _streamUpcoming;

  static String _label(DateTime m) {
    final name = LedgerDates.monthsFull[m.month - 1].toLowerCase();
    return m.year == DateTime.now().year ? name : '$name ${m.year}';
  }

  void _flip(int delta) {
    final current = LedgerDates.monthStart(DateTime.now());
    var target = DateTime(_month.year, _month.month + delta);
    if (target.isAfter(current)) target = current;
    if (target == _month) return;
    setState(() {
      _dir = delta;
      _month = target;
    });
  }

  void _toThisMonth() {
    final now = LedgerDates.monthStart(DateTime.now());
    if (now == _month) return;
    setState(() {
      _dir = 1;
      _month = now;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final onNow = _month == LedgerDates.monthStart(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _monthNav(c, onNow),
        const SizedBox(height: Gap.x3),
        _PageTurn(
          tag: '${_month.year}-${_month.month}',
          dir: _dir,
          child: _monthPage(onNow),
        ),
      ],
    );
  }

  Widget _monthPage(bool onNow) {
    return FutureBuilder<Map<int, int>>(
      future: _upcoming,
      builder: (context, upcomingSnap) {
        final c = LedgerColors.of(context);
        // Past months are closed books: no committed-bill projections.
        final upcoming = onNow
            ? (upcomingSnap.data ?? const <int, int>{})
            : const <int, int>{};
        if (_streamMonth != _month || !identical(_streamUpcoming, upcoming)) {
          _streamMonth = _month;
          _streamUpcoming = upcoming;
          _viewStream = ref
              .read(budgetRepoProvider)
              .watchViews(_month, upcomingByCategory: upcoming);
        }
        return StreamBuilder<List<BudgetView>>(
          stream: _viewStream,
          builder: (context, snapshot) {
            final views = snapshot.data ?? const <BudgetView>[];
            if (snapshot.hasData && views.isEmpty) {
              return EmptyPage(
                line: 'No lines drawn yet.',
                sub: 'The setup ritual proposes them — or one category can '
                    'start on its own.',
                action: LedgerChip(
                  'draw the first line',
                  icon: Icons.add,
                  selected: true,
                  onTap: () => _newBudget(context),
                ),
              );
            }

            final totalLimit = views.fold(0, (s, v) => s + v.pace.limitPaise);
            final totalSpent = views.fold(0, (s, v) => s + v.pace.spentPaise);

            // The page's one seal: the single worst overrun's verdict. Every
            // other verdict stays ink — the bars carry the forecast.
            int? sealId;
            var worst = 0;
            for (final v in views) {
              final over = v.pace.spentPaise - v.pace.limitPaise;
              if (over > worst) {
                worst = over;
                sealId = v.budget.id;
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CountHero(
                  caption: onNow
                      ? 'left to spend this month'
                      : 'spent in ${_label(_month)}',
                  paise: onNow
                      ? (totalLimit - totalSpent).clamp(0, 1 << 62)
                      : totalSpent,
                  format: Inr.format,
                  size: 34,
                  sub: onNow
                      ? null
                      : Text(
                          'the lines added up to ${Inr.format(totalLimit)}',
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 13,
                            color: c.inkFaint,
                          ),
                        ),
                ),
                const SizedBox(height: Gap.x3),
                // Keyed by id, position, and month: a rebalance that
                // re-sorts the rows — or a flipped page — re-inks them.
                for (final (i, v) in views.indexed)
                  InkIn(
                    key: ValueKey(
                        'budget-${v.budget.id}-$i-${_month.year}-${_month.month}'),
                    delay: Duration(milliseconds: 40 * i),
                    child: _BudgetRow(
                      view: v,
                      month: _month,
                      finalized: !onNow,
                      sealed: v.budget.id == sealId,
                    ),
                  ),
                if (onNow) ...[
                  _suggestions(c, views),
                  const SizedBox(height: Gap.x4),
                  Center(
                    child: Pressable(
                      haptic: false,
                      onTap: () async {
                        // The rows re-sorting and re-filling are the
                        // confirmation; the haptic lands with them.
                        await ref.read(budgetRepoProvider).rebalance(views);
                        HapticFeedback.lightImpact();
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync, size: 14, color: c.quill),
                          const SizedBox(width: 5),
                          Text(
                            'rebalance to match how the month actually went',
                            style: LedgerType.bodyStrong.copyWith(
                              fontSize: 13,
                              color: c.quill,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _monthNav(LedgerColors c, bool onNow) {
    return Row(
      children: [
        Pressable(
          onTap: () => _flip(-1),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.chevron_left, size: 18, color: c.inkFaint),
          ),
        ),
        const SizedBox(width: Gap.x1),
        Text(
          _label(_month),
          style: LedgerType.bodyStrong.copyWith(fontSize: 14, color: c.ink),
        ),
        const SizedBox(width: Gap.x1),
        Pressable(
          onTap: onNow ? null : () => _flip(1),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.chevron_right,
                size: 18, color: onNow ? c.rule : c.inkFaint),
          ),
        ),
        const Spacer(),
        if (!onNow)
          LedgerChip(
            'this month',
            icon: Icons.undo,
            selected: true,
            onTap: _toThisMonth,
          ),
      ],
    );
  }

  /// Lines that no longer describe the spending they watch — up to three,
  /// each with the three-month average and one tap to adopt it.
  Widget _suggestions(LedgerColors c, List<BudgetView> views) {
    return FutureBuilder<Map<int, int>>(
      future: _suggested,
      builder: (context, snap) {
        final avg = snap.data ?? const <int, int>{};
        final drifted = <(BudgetView, int)>[];
        for (final v in views) {
          final catId = v.budget.categoryId;
          if (catId == null) continue;
          final a = avg[catId];
          if (a == null) continue;
          if (budgetLineDrifted(limitPaise: v.pace.limitPaise, avgPaise: a)) {
            drifted.add((v, a));
            if (drifted.length == 3) break;
          }
        }
        if (drifted.isEmpty) return const SizedBox.shrink();

        final mono = LedgerType.amount.copyWith(fontSize: 13, color: c.ink);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RuleHeader('suggested lines'),
            for (final (i, (v, a)) in drifted.indexed)
              InkIn(
                key: ValueKey('suggest-${v.budget.id}'),
                delay: Duration(milliseconds: 40 * i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                  decoration: i == drifted.length - 1
                      ? null
                      : BoxDecoration(
                          border: Border(bottom: BorderSide(color: c.rule)),
                        ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: '${v.name} runs ',
                            children: [
                              TextSpan(text: Inr.format(a), style: mono),
                              const TextSpan(text: ' — the line says '),
                              TextSpan(
                                text: Inr.format(v.pace.limitPaise),
                                style: mono,
                              ),
                            ],
                          ),
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 13,
                            color: c.inkFaint,
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.x3),
                      LedgerChip(
                        'adopt',
                        icon: Icons.check,
                        selected: true,
                        onTap: () async {
                          // The bar gliding to its new line is the
                          // confirmation; the row retires itself.
                          HapticFeedback.lightImpact();
                          await ref
                              .read(budgetRepoProvider)
                              .setLimit(v.budget.id, a);
                        },
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

  /// The first line on a blank budgets page: pick the category, name the
  /// number.
  Future<void> _newBudget(BuildContext context) async {
    final db = ref.read(dbProvider);
    final cats = await (db.select(db.categories)
          ..where((t) =>
              t.kind.equalsValue(CategoryKind.expense) &
              t.archived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    if (cats.isEmpty || !context.mounted) return;
    final picked = await showLedgerSheet<(int, int)>(
      context,
      builder: (context) => _BudgetSheet(categories: cats),
    );
    if (picked == null) return;
    final (categoryId, rupees) = picked;
    final cat = cats.firstWhere((x) => x.id == categoryId);
    await ref.read(budgetRepoProvider).create(
          name: cat.name,
          limitPaise: rupees * 100,
          categoryId: categoryId,
        );
  }
}

class _BudgetRow extends ConsumerStatefulWidget {
  const _BudgetRow({
    required this.view,
    required this.month,
    this.finalized = false,
    this.sealed = false,
  });

  final BudgetView view;
  final DateTime month;

  /// A past month: the verdict is binary — held its line, or went past it.
  final bool finalized;

  /// This row carries the page's one seal (the worst overrun). Every other
  /// verdict stays ink.
  final bool sealed;

  @override
  ConsumerState<_BudgetRow> createState() => _BudgetRowState();
}

class _BudgetRowState extends ConsumerState<_BudgetRow> {
  /// The pace line is folded away until the row is asked about.
  bool _open = false;
  Future<List<int>>? _daily;

  /// The six whole months before this one — the sparkline and the streak.
  late final Future<List<int>> _history = _loadHistory();

  BudgetView get view => widget.view;
  int? get _catId => view.budget.categoryId;

  Future<List<int>> _loadHistory() async {
    final repo = ref.read(txnRepoProvider);
    final out = <int>[];
    for (var i = 6; i >= 1; i--) {
      final m = DateTime(widget.month.year, widget.month.month - i);
      out.add(await repo.spentBetween(
        LedgerDates.monthStart(m),
        LedgerDates.monthEnd(m),
        categoryId: _catId,
      ));
    }
    return out;
  }

  /// Cumulative spend, day by day, up to today — the solid line.
  Future<List<int>> _loadDaily() async {
    final repo = ref.read(txnRepoProvider);
    final from = LedgerDates.monthStart(widget.month);
    final days = view.pace.elapsedDays.clamp(1, view.pace.totalDays);
    final out = <int>[];
    for (var d = 1; d <= days; d++) {
      out.add(await repo.spentBetween(
        from,
        DateTime(from.year, from.month, d + 1),
        categoryId: _catId,
      ));
    }
    return out;
  }

  void _toggle() {
    setState(() {
      _open = !_open;
      _daily ??= _loadDaily();
    });
  }

  /// Whole months, most recent backwards, that stayed inside the line. A
  /// month with no spend at all is no evidence, so the count stops there.
  static int _held(List<int> months, int limitPaise) {
    if (limitPaise <= 0) return 0;
    var n = 0;
    for (var i = months.length - 1; i >= 0; i--) {
      if (months[i] <= 0 || months[i] > limitPaise) break;
      n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final pace = view.pace;
    final finalized = widget.finalized;
    final verdict = finalized
        ? (pace.spentPaise > pace.limitPaise
            ? '${Inr.format(pace.spentPaise - pace.limitPaise)} past its line'
            : 'held its line')
        : switch (pace.status) {
            BudgetStatus.onPace => 'on pace',
            BudgetStatus.projectedOver =>
              '${Inr.format(pace.projectedOverspendPaise)} over at this rate',
            BudgetStatus.over =>
              '${Inr.format(-pace.remainingPaise)} past its line',
            BudgetStatus.pending => 'due soon',
          };

    final mono = LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint);
    final pending = !finalized && pace.status == BudgetStatus.pending;
    final tail = pending
        ? ' · lands soon'
        : (!finalized && pace.remainingPaise > 0
            ? ' · ${Inr.format(pace.remainingPaise)} left'
            : '');

    return Pressable(
      onTap: _toggle,
      onLongPress: finalized ? null : () => _editLimit(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.rule)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CatMark(view.icon, size: 14, color: c.ink),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    view.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 14,
                      color: c.ink,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.x2),
                Text(
                  verdict,
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12,
                    color: widget.sealed ? c.seal : c.inkFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  '${Inr.format(pending ? 0 : pace.spentPaise)} of ',
                  style: mono,
                ),
                // The line itself settles into its new number when it's
                // argued with.
                CountUp(
                  value: pace.limitPaise,
                  format: Inr.format,
                  style: mono,
                ),
                if (tail.isNotEmpty) Text(tail, style: mono),
                const Spacer(),
                FutureBuilder<List<int>>(
                  future: _history,
                  builder: (context, snap) {
                    final months = snap.data;
                    if (months == null || months.every((v) => v == 0)) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(left: Gap.x2),
                      child: Sparkline([
                        for (final v in months) v.toDouble(),
                      ]),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 5),
            _GlidingBar(pace: pace, showToday: !finalized),
            FutureBuilder<List<int>>(
              future: _history,
              builder: (context, snap) {
                final months = snap.data;
                if (months == null) return const SizedBox.shrink();
                final n = _held(months, pace.limitPaise);
                if (n < 2) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'held its line $n months running',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 11,
                      color: c.inkFaint,
                    ),
                  ),
                );
              },
            ),
            // The signature element, one tap away on every budget.
            AnimatedSize(
              duration: Motion.reduced(context) ? Duration.zero : Motion.spring,
              curve: Motion.curve,
              alignment: Alignment.topCenter,
              child: _open
                  ? _paceLine(c)
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paceLine(LedgerColors c) {
    final pace = view.pace;
    final even = (pace.limitPaise * pace.fractionElapsed).round();
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x3),
      child: FutureBuilder<List<int>>(
        future: _daily,
        builder: (context, snap) {
          final daily = snap.data;
          if (daily == null || daily.isEmpty) {
            return const SizedBox(width: double.infinity, height: 74);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DrawIn(
                builder: (context, p) => PaceChart(
                  daily: daily,
                  elapsedDays: pace.elapsedDays,
                  totalDays: pace.totalDays,
                  progress: p,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.finalized
                    ? 'even pace for the month read ${Inr.format(even)}; '
                        'this line spent ${Inr.format(pace.spentPaise)}'
                    : 'even pace by today reads ${Inr.format(even)}; '
                        'spent so far ${Inr.format(pace.spentPaise)}',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 11,
                  color: c.inkFaint,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Long-press a budget to argue with its number.
  Future<void> _editLimit(BuildContext context) async {
    final result = await showLedgerSheet<(int, int?)>(
      context,
      builder: (context) => _AmountSheet(
        title: view.name,
        line: 'the monthly line, in rupees',
        cta: 'set the line',
        initial: view.pace.limitPaise ~/ 100,
      ),
    );
    if (result == null) return;
    final (rupees, _) = result;
    if (rupees > 0) {
      await ref.read(budgetRepoProvider).setLimit(view.budget.id, rupees * 100);
    }
  }
}

// ————— recurring —————

class _RecurringTab extends ConsumerStatefulWidget {
  const _RecurringTab();

  @override
  ConsumerState<_RecurringTab> createState() => _RecurringTabState();
}

class _RecurringTabState extends ConsumerState<_RecurringTab> {
  /// The row being stamped out — mid-fade, before the stream removes it.
  int? _fadingOutId;

  /// The day salary landed this month (largest income entry), if any.
  late final Future<int?> _salaryDay = _findSalaryDay();

  Future<int?> _findSalaryDay() async {
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final rows = await (db.select(db.txns)
          ..where((t) =>
              t.type.equalsValue(TxnType.income) &
              t.at.isBiggerOrEqualValue(LedgerDates.monthStart(now)) &
              t.at.isSmallerThanValue(LedgerDates.monthEnd(now)))
          ..orderBy([(t) => OrderingTerm.desc(t.amountPaise)])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first.at.day;
  }

  /// One due line: inks in on entry, gives under the thumb, inks out when
  /// its stamp lands. Swiped right, it's paid.
  Widget _dueRow(DueItem d, int stagger, {required bool last}) => InkIn(
        key: ValueKey('due-${d.recurring.id}'),
        delay: Duration(milliseconds: 40 * stagger),
        child: AnimatedOpacity(
          opacity: _fadingOutId == d.recurring.id ? 0 : 1,
          duration: Motion.spring,
          curve: Motion.curve,
          child: SwipeRow(
            rowKey: ValueKey('due-swipe-${d.recurring.id}'),
            editLabel: 'paid',
            onEdit: () => _pay(d),
            child: Pressable(
              onTap: () => _paySheet(context, d),
              child: LedgerLine(
                leading: LedgerDates.ddMmm(d.due),
                title: d.recurring.title,
                amount: Inr.format(d.recurring.amountPaise),
                last: last,
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final recurring = ref.watch(recurringRepoProvider);

    return StreamBuilder<List<Recurring>>(
      stream: recurring.watchAll(),
      builder: (context, shelfSnap) {
        if (shelfSnap.hasData && shelfSnap.data!.isEmpty) {
          return EmptyPage(
            line: 'Nothing on the recurring shelf yet.',
            sub: 'The rent, the phone, the one subscription I keep '
                'forgetting about.',
            action: LedgerChip(
              'add a bill',
              icon: Icons.add,
              selected: true,
              onTap: _addRecurring,
            ),
          );
        }
        return StreamBuilder<int>(
          stream: recurring.watchCommittedThisMonth(),
          builder: (context, committedSnap) {
            return StreamBuilder<List<DueItem>>(
              stream: recurring.watchUpcoming(),
              builder: (context, dueSnap) {
                final due = dueSnap.data ?? const <DueItem>[];
                final bills = due.where((d) => d.isBill).toList();
                final subs = due.where((d) => !d.isBill).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CountHero(
                      caption: 'already spoken for, this month',
                      paise: committedSnap.data ?? 0,
                      format: Inr.format,
                      size: 34,
                      sub: Text(
                        'before you spend a rupee',
                        style: LedgerType.bodyText.copyWith(
                          fontSize: 13,
                          color: c.inkFaint,
                        ),
                      ),
                    ),
                    if (due.isNotEmpty) ...[
                      const RuleHeader('how the month lands'),
                      FutureBuilder<int?>(
                        future: _salaryDay,
                        builder: (context, sal) => _MonthTickStrip(
                          due: due,
                          salaryDay: sal.data,
                        ),
                      ),
                    ],
                    if (bills.isNotEmpty) const RuleHeader('bills'),
                    for (final (i, d) in bills.indexed)
                      _dueRow(d, i, last: i == bills.length - 1),
                    if (subs.isNotEmpty) const RuleHeader('subscriptions'),
                    for (final (i, d) in subs.indexed)
                      _dueRow(d, bills.length + i, last: i == subs.length - 1),
                    _addLine(c),
                    const SizedBox(height: Gap.x3),
                    FutureBuilder<int>(
                      future: recurring.yearlyTotal(
                        kind: RecurringKind.subscription,
                      ),
                      builder: (context, yearly) => Text.rich(
                        TextSpan(
                          text: 'Subscriptions cost ',
                          children: [
                            TextSpan(
                              text: Inr.format(yearly.data ?? 0),
                              style: LedgerType.amount.copyWith(
                                fontSize: 13,
                                color: c.ink,
                              ),
                            ),
                            const TextSpan(text: ' a year.'),
                          ],
                        ),
                        style: LedgerType.bodyText.copyWith(
                          fontSize: 13,
                          color: c.inkFaint,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// The last ruled line on the shelf: one quiet way to add to it.
  Widget _addLine(LedgerColors c) {
    return Pressable(
      onTap: _addRecurring,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.rule)),
        ),
        child: Row(
          children: [
            Icon(Icons.add, size: 14, color: c.quill),
            const SizedBox(width: 7),
            Text(
              'add a bill or a subscription',
              style: LedgerType.bodyStrong.copyWith(
                fontSize: 13,
                color: c.quill,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addRecurring() async {
    final db = ref.read(dbProvider);
    final accounts = await (db.select(db.accounts)
          ..where((a) => a.archived.equals(false))
          ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
        .get();
    if (accounts.isEmpty || !mounted) return;
    final cats = await (db.select(db.categories)
          ..where((t) =>
              t.kind.equalsValue(CategoryKind.expense) &
              t.archived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    if (!mounted) return;
    final made = await showLedgerSheet<_NewRecurring>(
      context,
      builder: (context) => _RecurringSheet(
        accounts: accounts,
        categories: cats,
      ),
    );
    if (made == null) return;
    await ref.read(recurringRepoProvider).create(
          title: made.title,
          amountPaise: made.rupees * 100,
          accountId: made.accountId,
          dayOfMonth: made.day,
          kind: made.kind,
          categoryId: made.categoryId,
        );
  }

  /// Ink the row out first; the stream taking it away, and the committed
  /// hero counting down, land right behind it.
  Future<void> _pay(DueItem d) async {
    if (mounted) setState(() => _fadingOutId = d.recurring.id);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    await ref.read(recurringRepoProvider).markPaid(d.recurring);
    if (mounted) setState(() => _fadingOutId = null);
  }

  Future<void> _paySheet(BuildContext context, DueItem d) async {
    final paid = await showLedgerSheet<bool>(
      context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.x2),
              Text(
                d.recurring.title,
                style: LedgerType.title.copyWith(fontSize: 20, color: c.ink),
              ),
              const SizedBox(height: 2),
              Text(
                'lands ${LedgerDates.ddMmm(d.due)} · '
                '${Inr.format(d.recurring.amountPaise)}',
                style: LedgerType.bodyText
                    .copyWith(fontSize: 13, color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x4),
              _StampButton(
                label: 'paid — stamp ${Inr.format(d.recurring.amountPaise)}',
                onStamped: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: Gap.x2),
              Pressable(
                haptic: false,
                onTap: () => Navigator.of(context).pop(false),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x2),
                  child: Center(
                    child: Text(
                      'not yet',
                      style: LedgerType.bodyText
                          .copyWith(fontSize: 13, color: c.inkFaint),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (paid == true) await _pay(d);
  }
}

/// The month as one row of day-ticks: a quill tick where a charge lands,
/// a jama tick on salary day, today ringed, quiet days barely there.
class _MonthTickStrip extends StatelessWidget {
  const _MonthTickStrip({required this.due, required this.salaryDay});

  final List<DueItem> due;
  final int? salaryDay;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final now = DateTime.now();
    final total = LedgerDates.daysInMonth(now);

    final landsPaise = <int, int>{};
    for (final d in due) {
      if (d.due.year == now.year && d.due.month == now.month) {
        landsPaise[d.due.day] =
            (landsPaise[d.due.day] ?? 0) + d.recurring.amountPaise;
      }
    }

    Widget tick(int day) {
      final salary = day == salaryDay;
      final lands = landsPaise.containsKey(day);
      final color = salary
          ? c.jama
          : lands
              ? c.quill
              : c.rule;
      if (day == now.day) {
        return Container(
          width: 14,
          height: 14,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.inkFaint),
          ),
          child: Container(width: 2, height: 6, color: color),
        );
      }
      return Container(
        width: 2,
        height: salary || lands ? 12 : 5,
        color: color,
      );
    }

    return InkIn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 18,
            child: Row(
              children: [
                for (var day = 1; day <= total; day++)
                  Expanded(child: Center(child: tick(day))),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _caption(landsPaise, total),
            style:
                LedgerType.bodyText.copyWith(fontSize: 11, color: c.inkFaint),
          ),
        ],
      ),
    );
  }

  static String _caption(Map<int, int> landsPaise, int totalDays) {
    if (landsPaise.isEmpty) return 'nothing lands this month';
    final sums = List<int>.filled(5, 0);
    landsPaise.forEach(
        (day, paise) => sums[math.min((day - 1) ~/ 7, 4)] += paise);
    var best = 0;
    for (var i = 1; i < 5; i++) {
      if (sums[i] > sums[best]) best = i;
    }
    final start = best * 7 + 1;
    final end = best == 4 ? totalDays : math.min(start + 6, totalDays);
    return 'heaviest week: $start–$end';
  }
}

// ————— goals —————

class _GoalsTab extends ConsumerWidget {
  const _GoalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalRepoProvider);

    return StreamBuilder<List<GoalView>>(
      stream: goals.watchViews(),
      builder: (context, snapshot) {
        final views = snapshot.data ?? const <GoalView>[];
        if (snapshot.hasData && views.isEmpty) {
          return EmptyPage(
            line: 'Nothing being saved for yet.',
            sub: 'A goal here is just entries in the book, added up.',
            action: LedgerChip(
              'name the first thing',
              icon: Icons.add,
              selected: true,
              onTap: () => _newGoal(context, ref),
            ),
          );
        }

        // The seal is earned, and rationed: at most two stamps on a page.
        final stamped = <int>{};
        for (final v in views) {
          if (v.reached && stamped.length < 2) stamped.add(v.goal.id);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, v) in views.indexed)
              InkIn(
                key: ValueKey('goal-${v.goal.id}'),
                delay: Duration(milliseconds: 40 * i),
                child: _GoalCard(
                  view: v,
                  last: i == views.length - 1,
                  sealed: stamped.contains(v.goal.id),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _newGoal(BuildContext context, WidgetRef ref) async {
    final made = await showLedgerSheet<(String, int)>(
      context,
      builder: (context) => const _GoalSheet(),
    );
    if (made == null) return;
    final (name, rupees) = made;
    await ref
        .read(goalRepoProvider)
        .create(name: name, targetPaise: rupees * 100);
  }
}

class _GoalCard extends ConsumerStatefulWidget {
  const _GoalCard({
    required this.view,
    required this.last,
    this.sealed = false,
  });

  final GoalView view;
  final bool last;

  /// This goal is allowed the page's stamp.
  final bool sealed;

  @override
  ConsumerState<_GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends ConsumerState<_GoalCard> {
  /// Cached so stream emissions upstream don't resubscribe (and flicker)
  /// the rhythm cells.
  late final Stream<List<Txn>> _entryStream =
      ref.read(goalRepoProvider).watchEntries(widget.view.goal.id);

  /// Already done when the page opened: the stamp is drawn, but it doesn't
  /// buzz — that moment already happened.
  late final bool _wasReached = widget.view.reached;

  GoalView get view => widget.view;

  static String _monthLabel(DateTime d) =>
      '${LedgerDates.monthsFull[d.month - 1]} ${d.year}';

  /// Which of the last six months (oldest first) saw a contribution.
  static List<bool> _rhythm(Iterable<DateTime> dates, DateTime now) {
    final marks = <int>{for (final d in dates) d.year * 12 + d.month};
    final out = <bool>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i);
      out.add(marks.contains(m.year * 12 + m.month));
    }
    return out;
  }

  Widget _hair(LedgerColors c) => Container(
        height: 1,
        color: c.rule,
        margin: const EdgeInsets.symmetric(vertical: Gap.x3),
      );

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final g = view.goal;
    final eta = view.etaFrom(DateTime.now());
    final saving = g.kind == GoalKind.save;

    return Container(
      padding: const EdgeInsets.only(top: Gap.x4, bottom: Gap.x4),
      decoration: BoxDecoration(
        border:
            widget.last ? null : Border(bottom: BorderSide(color: c.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The name line — and the stamp, when the copy has earned it.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      saving ? 'saving for' : 'clearing',
                      style: LedgerType.label.copyWith(color: c.inkFaint),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      g.name,
                      style:
                          LedgerType.title.copyWith(fontSize: 22, color: c.ink),
                    ),
                  ],
                ),
              ),
              if (widget.sealed)
                Padding(
                  padding: const EdgeInsets.only(left: Gap.x3),
                  child: StampIn(size: 34, haptic: !_wasReached),
                ),
            ],
          ),
          _hair(c),
          // The figure settles in place whenever the goal is fed.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              CountUp(
                value: view.donePaise,
                format: Inr.format,
                style: LedgerType.amountTotal.copyWith(color: c.ink),
              ),
              const SizedBox(width: Gap.x2),
              Text(
                'of ${Inr.format(g.targetPaise)}${saving ? '' : ' cleared'}',
                style:
                    LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: Gap.x2),
          // Saving is completion, so this one is allowed to fill.
          _FillLine(fraction: view.fraction),
          _hair(c),
          // The ETA line cross-fades when a contribution moves it.
          AnimatedSwitcher(
            duration: Motion.quick,
            switchInCurve: Motion.curve,
            switchOutCurve: Motion.curve,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, ?current],
            ),
            child: Text(
              view.reached
                  ? 'Done. The seal is yours.'
                  : eta == null
                      ? 'Fed by ${view.entryCount} stamped '
                          '${view.entryCount == 1 ? 'entry' : 'entries'}.'
                      : 'On pace for ${_monthLabel(eta)} · fed by '
                          '${view.entryCount} stamped '
                          '${view.entryCount == 1 ? 'entry' : 'entries'}.',
              key: ValueKey(
                '${view.reached}-${eta?.month}-${eta?.year}-${view.entryCount}',
              ),
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
          ),
          _hair(c),
          // The last six months as cells: filled = the goal got fed.
          StreamBuilder<List<Txn>>(
            stream: _entryStream,
            builder: (context, snap) {
              final months = _rhythm(
                [for (final t in snap.data ?? const <Txn>[]) t.at],
                DateTime.now(),
              );
              final fed = months.where((m) => m).length;
              return Row(
                children: [
                  for (final m in months)
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: m ? c.jama.withValues(alpha: 0.8) : null,
                        border: m ? null : Border.all(color: c.rule),
                      ),
                    ),
                  const SizedBox(width: Gap.x2),
                  Text(
                    fed == 0
                        ? 'quiet these six months'
                        : 'steady $fed of 6 months',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 12,
                      color: c.inkFaint,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: Gap.x3),
          Row(
            children: [
              LedgerChip(
                'add to this',
                icon: Icons.add,
                selected: true,
                onTap: () => _contribute(context),
              ),
              const SizedBox(width: Gap.x2),
              LedgerChip(
                'the entries',
                icon: LedgerIcons.resolve('book'),
                onTap: () => _entries(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _contribute(BuildContext context) async {
    final db = ref.read(dbProvider);
    final accounts = await (db.select(db.accounts)
          ..where((a) => a.archived.equals(false))
          ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
        .get();
    if (accounts.isEmpty || !context.mounted) return;
    final result = await showLedgerSheet<(int, int?)>(
      context,
      builder: (context) => _AmountSheet(
        title: 'Add to ${view.goal.name}',
        line: 'in rupees',
        cta: 'stamp it',
        initial: view.goal.monthlyPaise == null
            ? null
            : view.goal.monthlyPaise! ~/ 100,
        accounts: accounts,
      ),
    );
    if (result == null) return;
    final (rupees, accountId) = result;
    if (rupees <= 0) return;
    await ref.read(goalRepoProvider).contribute(
          goal: view.goal,
          amountPaise: rupees * 100,
          accountId: accountId ?? accounts.first.id,
        );
  }

  Future<void> _entries(BuildContext context) async {
    await showLedgerSheet<void>(
      context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: StreamBuilder<List<Txn>>(
            stream: _entryStream,
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <Txn>[];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SheetHandle(),
                  const SizedBox(height: Gap.x2),
                  Text(
                    'behind ${view.goal.name}',
                    style: LedgerType.label.copyWith(color: c.inkFaint),
                  ),
                  const SizedBox(height: Gap.x2),
                  if (rows.isEmpty)
                    Text(
                      'No entries yet.',
                      style: LedgerType.bodyText.copyWith(color: c.inkFaint),
                    ),
                  for (final (i, t) in rows.take(8).indexed)
                    LedgerLine(
                      leading: LedgerDates.ddMmm(t.at),
                      title: t.title,
                      amount: Inr.format(t.amountPaise),
                      last: i == rows.length - 1 || i == 7,
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// A goal's thin fill line — the one bar in the book allowed to fill,
/// because saving really is completion.
class _FillLine extends StatelessWidget {
  const _FillLine({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final f = fraction.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, box) {
        Widget fill(double v) => Stack(
              children: [
                Container(height: 3, color: c.rule),
                Container(
                  height: 3,
                  width: box.maxWidth * v,
                  color: c.jama,
                ),
              ],
            );
        if (Motion.reduced(context)) return fill(f);
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: f),
          duration: Motion.settle,
          curve: Motion.curve,
          builder: (context, v, _) => fill(v),
        );
      },
    );
  }
}

// ————— sheets —————

/// A ledger field: plain ink on one ruled line. No boxes, no borders, no
/// rupee glyph typed into a decoration — the label carries the currency.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    this.hint,
    this.style,
    this.autofocus = false,
    this.digits = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? hint;
  final TextStyle? style;
  final bool autofocus;
  final bool digits;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final text = style ?? LedgerType.bodyText.copyWith(color: c.ink);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: digits ? TextInputType.number : TextInputType.text,
        textCapitalization:
            digits ? TextCapitalization.none : TextCapitalization.sentences,
        inputFormatters:
            digits ? [FilteringTextInputFormatter.digitsOnly] : null,
        style: text,
        cursorColor: c.quill,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: text.copyWith(color: c.inkFaint),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: Gap.x2),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// The save: it presses, it stamps, and the seal landing is what closes the
/// sheet. No toast follows it.
class _StampButton extends StatefulWidget {
  const _StampButton({
    required this.label,
    required this.onStamped,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onStamped;
  final bool enabled;

  @override
  State<_StampButton> createState() => _StampButtonState();
}

class _StampButtonState extends State<_StampButton> {
  bool _stamping = false;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final live = widget.enabled && !_stamping;
    return Pressable(
      haptic: false,
      onTap: live ? () => setState(() => _stamping = true) : null,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.enabled ? c.quillSoft : null,
          border: Border.all(color: widget.enabled ? c.quill : c.rule),
          borderRadius: BorderRadius.circular(Corner.key),
        ),
        child: _stamping
            ? StampIn(size: 30, onStamped: widget.onStamped)
            : Text(
                widget.label,
                style: LedgerType.bodyStrong.copyWith(
                  fontSize: 15,
                  color: widget.enabled ? c.quill : c.inkFaint,
                ),
              ),
      ),
    );
  }
}

/// "from which pocket" as a ruled line inside a sheet.
class _PocketLine extends StatelessWidget {
  const _PocketLine({required this.account, required this.onTap});

  final Account account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.x2),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.rule)),
        ),
        child: Row(
          children: [
            Text(
              'from',
              style:
                  LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
            ),
            const SizedBox(width: Gap.x2),
            Expanded(
              child: Text(
                account.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    LedgerType.bodyStrong.copyWith(fontSize: 14, color: c.ink),
              ),
            ),
            Text(
              Inr.format(account.balancePaise),
              style:
                  LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
            ),
            Icon(Icons.chevron_right, size: 16, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// One number, asked for plainly: a title, a ruled field of bare digits, the
/// figure echoed underneath in the book's own hand, and a stamp to close it.
/// Pops `(rupees, accountId)`.
class _AmountSheet extends StatefulWidget {
  const _AmountSheet({
    required this.title,
    required this.line,
    required this.cta,
    this.initial,
    this.accounts = const [],
  });

  final String title;
  final String line;
  final String cta;
  final int? initial;

  /// When given, the sheet also asks which pocket the money comes from.
  final List<Account> accounts;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late final TextEditingController _ctl = TextEditingController(
    text: (widget.initial ?? 0) > 0 ? '${widget.initial}' : '',
  );
  late int _rupees = widget.initial ?? 0;
  late Account? _account =
      widget.accounts.isEmpty ? null : widget.accounts.first;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _pickPocket() async {
    final picked = await pickLedgerAccount(
      context,
      accounts: widget.accounts,
      selectedId: _account?.id,
    );
    if (picked != null && mounted) setState(() => _account = picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.x2),
              Text(
                widget.title,
                style: LedgerType.title.copyWith(fontSize: 20, color: c.ink),
              ),
              const SizedBox(height: 2),
              Text(
                widget.line,
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x3),
              _Field(
                controller: _ctl,
                autofocus: true,
                digits: true,
                hint: '0',
                style:
                    LedgerType.heroAmount.copyWith(fontSize: 32, color: c.ink),
                onChanged: (v) =>
                    setState(() => _rupees = int.tryParse(v.trim()) ?? 0),
              ),
              const SizedBox(height: Gap.x2),
              Text(
                Inr.format(_rupees * 100),
                style:
                    LedgerType.amount.copyWith(fontSize: 13, color: c.inkFaint),
              ),
              if (_account != null) ...[
                const SizedBox(height: Gap.x3),
                _PocketLine(account: _account!, onTap: _pickPocket),
              ],
              const SizedBox(height: Gap.x4),
              _StampButton(
                label: widget.cta,
                enabled: _rupees > 0,
                onStamped: () =>
                    Navigator.of(context).pop((_rupees, _account?.id)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A first budget: which category, and what the line says. Pops
/// `(categoryId, rupees)`.
class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet({required this.categories});

  final List<Category> categories;

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  final _ctl = TextEditingController();
  int _rupees = 0;
  late int _categoryId = widget.categories.first.id;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.x2),
              Text(
                'the first line',
                style: LedgerType.title.copyWith(fontSize: 20, color: c.ink),
              ),
              const SizedBox(height: 2),
              Text(
                'what is being watched',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x2),
              _CategoryStrip(
                categories: widget.categories,
                selectedId: _categoryId,
                onPick: (id) => setState(() => _categoryId = id ?? _categoryId),
              ),
              const SizedBox(height: Gap.x4),
              Text(
                'the monthly line, in rupees',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x2),
              _Field(
                controller: _ctl,
                digits: true,
                hint: '0',
                style:
                    LedgerType.heroAmount.copyWith(fontSize: 32, color: c.ink),
                onChanged: (v) =>
                    setState(() => _rupees = int.tryParse(v.trim()) ?? 0),
              ),
              const SizedBox(height: Gap.x2),
              Text(
                Inr.format(_rupees * 100),
                style:
                    LedgerType.amount.copyWith(fontSize: 13, color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x4),
              _StampButton(
                label: 'draw the line',
                enabled: _rupees > 0,
                onStamped: () =>
                    Navigator.of(context).pop((_categoryId, _rupees)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A first goal: a name and a target. Pops `(name, rupees)`.
class _GoalSheet extends StatefulWidget {
  const _GoalSheet();

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  int _rupees = 0;
  String _title = '';

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.x2),
              Text(
                'name the first thing',
                style: LedgerType.title.copyWith(fontSize: 20, color: c.ink),
              ),
              const SizedBox(height: Gap.x3),
              _Field(
                controller: _name,
                autofocus: true,
                hint: 'what is it for?',
                onChanged: (v) => setState(() => _title = v.trim()),
              ),
              const SizedBox(height: Gap.x4),
              Text(
                'the target, in rupees',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x2),
              _Field(
                controller: _target,
                digits: true,
                hint: '0',
                style:
                    LedgerType.heroAmount.copyWith(fontSize: 32, color: c.ink),
                onChanged: (v) =>
                    setState(() => _rupees = int.tryParse(v.trim()) ?? 0),
              ),
              const SizedBox(height: Gap.x2),
              Text(
                Inr.format(_rupees * 100),
                style:
                    LedgerType.amount.copyWith(fontSize: 13, color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x4),
              _StampButton(
                label: 'start it',
                enabled: _rupees > 0 && _title.isNotEmpty,
                onStamped: () => Navigator.of(context).pop((_title, _rupees)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a new shelf line needs to exist.
class _NewRecurring {
  const _NewRecurring({
    required this.title,
    required this.rupees,
    required this.accountId,
    required this.day,
    required this.kind,
    this.categoryId,
  });

  final String title;
  final int rupees;
  final int accountId;
  final int day;
  final RecurringKind kind;
  final int? categoryId;
}

/// Putting something on the recurring shelf: what it is, what it costs, when
/// it lands, which pocket it leaves from.
class _RecurringSheet extends StatefulWidget {
  const _RecurringSheet({required this.accounts, required this.categories});

  final List<Account> accounts;
  final List<Category> categories;

  @override
  State<_RecurringSheet> createState() => _RecurringSheetState();
}

class _RecurringSheetState extends State<_RecurringSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  late final TextEditingController _day =
      TextEditingController(text: '${DateTime.now().day}');

  String _name = '';
  int _rupees = 0;
  int _dayOfMonth = DateTime.now().day;
  RecurringKind _kind = RecurringKind.bill;
  int? _categoryId;
  late Account _account = widget.accounts.first;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _day.dispose();
    super.dispose();
  }

  Future<void> _pickPocket() async {
    final picked = await pickLedgerAccount(
      context,
      accounts: widget.accounts,
      selectedId: _account.id,
    );
    if (picked != null && mounted) setState(() => _account = picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final ok = _name.isNotEmpty &&
        _rupees > 0 &&
        _dayOfMonth >= 1 &&
        _dayOfMonth <= 31;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.x2),
              Text(
                'onto the shelf',
                style: LedgerType.title.copyWith(fontSize: 20, color: c.ink),
              ),
              const SizedBox(height: Gap.x3),
              _Field(
                controller: _title,
                autofocus: true,
                hint: 'what lands, month after month?',
                onChanged: (v) => setState(() => _name = v.trim()),
              ),
              const SizedBox(height: Gap.x4),
              Text(
                'what it costs, in rupees',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x2),
              _Field(
                controller: _amount,
                digits: true,
                hint: '0',
                style:
                    LedgerType.heroAmount.copyWith(fontSize: 28, color: c.ink),
                onChanged: (v) =>
                    setState(() => _rupees = int.tryParse(v.trim()) ?? 0),
              ),
              const SizedBox(height: Gap.x2),
              Text(
                Inr.format(_rupees * 100),
                style:
                    LedgerType.amount.copyWith(fontSize: 13, color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x4),
              Row(
                children: [
                  LedgerChip(
                    'a bill',
                    selected: _kind == RecurringKind.bill,
                    onTap: () => setState(() => _kind = RecurringKind.bill),
                  ),
                  const SizedBox(width: Gap.x2),
                  LedgerChip(
                    'a subscription',
                    selected: _kind == RecurringKind.subscription,
                    onTap: () =>
                        setState(() => _kind = RecurringKind.subscription),
                  ),
                ],
              ),
              const SizedBox(height: Gap.x4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'lands on the',
                    style: LedgerType.bodyText
                        .copyWith(fontSize: 14, color: c.inkFaint),
                  ),
                  const SizedBox(width: Gap.x2),
                  SizedBox(
                    width: 44,
                    child: _Field(
                      controller: _day,
                      digits: true,
                      hint: '1',
                      style: LedgerType.amount
                          .copyWith(fontSize: 16, color: c.ink),
                      onChanged: (v) => setState(
                          () => _dayOfMonth = int.tryParse(v.trim()) ?? 0),
                    ),
                  ),
                  const SizedBox(width: Gap.x2),
                  Text(
                    'of the month',
                    style: LedgerType.bodyText
                        .copyWith(fontSize: 14, color: c.inkFaint),
                  ),
                ],
              ),
              const SizedBox(height: Gap.x4),
              _PocketLine(account: _account, onTap: _pickPocket),
              if (widget.categories.isNotEmpty) ...[
                const SizedBox(height: Gap.x4),
                Text(
                  'filed under (so the budget sees it coming)',
                  style: LedgerType.label.copyWith(color: c.inkFaint),
                ),
                const SizedBox(height: Gap.x2),
                _CategoryStrip(
                  categories: widget.categories,
                  selectedId: _categoryId,
                  onPick: (id) => setState(() => _categoryId = id),
                ),
              ],
              const SizedBox(height: Gap.x4),
              _StampButton(
                label: 'put it on the shelf',
                enabled: ok,
                onStamped: () => Navigator.of(context).pop(
                  _NewRecurring(
                    title: _name,
                    rupees: _rupees,
                    accountId: _account.id,
                    day: _dayOfMonth,
                    kind: _kind,
                    categoryId: _categoryId,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Categories as a single scrolling row of marked chips; tapping the chosen
/// one again lets it go.
class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.selectedId,
    required this.onPick,
  });

  final List<Category> categories;
  final int? selectedId;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final cat in categories) ...[
            LedgerChip(
              cat.name,
              icon: LedgerIcons.resolve(cat.icon),
              selected: cat.id == selectedId,
              onTap: () {
                HapticFeedback.selectionClick();
                onPick(cat.id == selectedId ? null : cat.id);
              },
            ),
            const SizedBox(width: Gap.x2),
          ],
        ],
      ),
    );
  }
}

// ————— motion helpers —————

/// A [BudgetPace] with its verdict frozen and its fill fraction overridden,
/// so a bar can animate width without its status color flickering mid-glide.
class _PaceAt extends BudgetPace {
  _PaceAt(BudgetPace base, this._fraction)
      : _status = base.status,
        super(
          spentPaise: base.spentPaise,
          limitPaise: base.limitPaise,
          elapsedDays: base.elapsedDays,
          totalDays: base.totalDays,
          upcomingPaise: base.upcomingPaise,
        );

  final double _fraction;
  final BudgetStatus _status;

  @override
  double get fractionSpent => _fraction;

  @override
  BudgetStatus get status => _status;
}

/// A budget bar whose fill draws in on first build and glides to any new
/// width after that. Pending bars stay as they are — an outline has nothing
/// to fill.
class _GlidingBar extends StatefulWidget {
  const _GlidingBar({required this.pace, this.showToday = true});

  final BudgetPace pace;
  final bool showToday;

  @override
  State<_GlidingBar> createState() => _GlidingBarState();
}

class _GlidingBarState extends State<_GlidingBar> {
  var _settled = false;

  @override
  Widget build(BuildContext context) {
    if (widget.pace.status == BudgetStatus.pending ||
        Motion.reduced(context)) {
      return BudgetBar(pace: widget.pace, showToday: widget.showToday);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: widget.pace.fractionSpent.clamp(0.0, 1.0)),
      duration: _settled ? Motion.spring : Motion.settle,
      curve: Motion.curve,
      onEnd: () => _settled = true,
      builder: (context, f, _) => BudgetBar(
        pace: _PaceAt(widget.pace, f),
        showToday: widget.showToday,
      ),
    );
  }
}
