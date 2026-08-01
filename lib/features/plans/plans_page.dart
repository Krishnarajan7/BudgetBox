import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/cat_mark.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/ledger_app_bar.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/budget_math.dart';
import '../../data/repos/budget_repo.dart';
import '../../data/repos/goal_repo.dart';
import '../../data/repos/recurring_repo.dart';

class PlansPage extends ConsumerStatefulWidget {
  const PlansPage({super.key});

  @override
  ConsumerState<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends ConsumerState<PlansPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Gap.page),
      children: [
        const LedgerAppBar(title: 'Plans'),
        const SizedBox(height: Gap.x3),
        Row(
          children: [
            for (final (i, label) in [
              'budgets',
              'recurring',
              'goals',
            ].indexed) ...[
              LedgerChip(
                label,
                selected: _tab == i,
                onTap: () => setState(() => _tab = i),
              ),
              const SizedBox(width: Gap.x2),
            ],
          ],
        ),
        const SizedBox(height: Gap.x4),
        ...switch (_tab) {
          0 => [const _BudgetsTab()],
          1 => [const _RecurringTab()],
          _ => [const _GoalsTab()],
        },
        const SizedBox(height: Gap.x6),
      ],
    );
  }
}

// ————— budgets —————

class _BudgetsTab extends ConsumerWidget {
  const _BudgetsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final budgets = ref.watch(budgetRepoProvider);
    final recurring = ref.watch(recurringRepoProvider);
    final now = DateTime.now();

    return FutureBuilder<Map<int, int>>(
      future: recurring.upcomingByCategory(),
      builder: (context, upcomingSnap) {
        final upcoming = upcomingSnap.data ?? const <int, int>{};
        return StreamBuilder<List<BudgetView>>(
          stream: budgets.watchViews(now, upcomingByCategory: upcoming),
          builder: (context, snapshot) {
            final views = snapshot.data ?? const <BudgetView>[];
            if (snapshot.hasData && views.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.x6),
                child: Text(
                  'No budgets yet. The setup ritual proposes them, or add '
                  'one from a category.',
                  style: LedgerType.bodyText.copyWith(color: c.inkFaint),
                ),
              );
            }

            final totalLimit = views.fold(0, (s, v) => s + v.pace.limitPaise);
            final totalSpent = views.fold(0, (s, v) => s + v.pace.spentPaise);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HeroAmount(
                  caption: 'left to spend this month',
                  amount: Inr.format(
                    (totalLimit - totalSpent).clamp(0, 1 << 62),
                  ),
                  size: 34,
                ),
                const SizedBox(height: Gap.x3),
                for (final v in views) _BudgetRow(view: v),
                const SizedBox(height: Gap.x4),
                Center(
                  child: InkWell(
                    onTap: () async {
                      HapticFeedback.mediumImpact();
                      await budgets.rebalance(views);
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
            );
          },
        );
      },
    );
  }
}

class _BudgetRow extends ConsumerWidget {
  const _BudgetRow({required this.view});

  final BudgetView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final pace = view.pace;
    final (statusText, statusColor) = switch (pace.status) {
      BudgetStatus.onPace => ('on pace', c.jama),
      BudgetStatus.projectedOver => (
        '${Inr.format(pace.projectedOverspendPaise)} over at this rate',
        c.warn,
      ),
      BudgetStatus.over => (
        '${Inr.format(-pace.remainingPaise)} past its line',
        c.seal,
      ),
      BudgetStatus.pending => ('due soon', c.inkFaint),
    };

    return InkWell(
      onLongPress: () => _editLimit(context, ref),
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
                Text(
                  view.name,
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 14,
                    color: c.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  statusText,
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              pace.status == BudgetStatus.pending
                  ? '${Inr.format(0)} of ${Inr.format(pace.limitPaise)} · lands soon'
                  : '${Inr.format(pace.spentPaise)} of ${Inr.format(pace.limitPaise)}'
                        '${pace.remainingPaise > 0 ? ' · ${Inr.format(pace.remainingPaise)} left' : ''}',
              style: LedgerType.amount.copyWith(
                fontSize: 12,
                color: c.inkFaint,
              ),
            ),
            const SizedBox(height: 5),
            BudgetBar(pace: pace),
          ],
        ),
      ),
    );
  }

  /// Long-press a budget to argue with its number.
  Future<void> _editLimit(BuildContext context, WidgetRef ref) async {
    final c = LedgerColors.of(context);
    final controller = TextEditingController(
      text: (view.pace.limitPaise ~/ 100).toString(),
    );
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: Gap.page,
          right: Gap.page,
          top: Gap.x4,
          bottom: MediaQuery.of(context).viewInsets.bottom + Gap.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${view.name} — the monthly line',
              style: LedgerType.bodyStrong.copyWith(color: c.ink),
            ),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: LedgerType.heroAmount.copyWith(fontSize: 32, color: c.ink),
              decoration: InputDecoration(
                prefixText: '₹',
                prefixStyle: LedgerType.heroAmount.copyWith(
                  fontSize: 32,
                  color: c.inkFaint,
                ),
                border: InputBorder.none,
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Set the line'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final rupees = int.tryParse(controller.text.trim());
      if (rupees != null && rupees > 0) {
        await ref
            .read(budgetRepoProvider)
            .setLimit(view.budget.id, rupees * 100);
      }
    }
  }
}

// ————— recurring —————

class _RecurringTab extends ConsumerWidget {
  const _RecurringTab();

  static String _short(DateTime d) {
    const s = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${s[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final recurring = ref.watch(recurringRepoProvider);

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
                HeroAmount(
                  caption: 'already spoken for, this month',
                  amount: Inr.format(committedSnap.data ?? 0),
                  size: 34,
                  sub: Text(
                    'before you spend a rupee',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 13,
                      color: c.inkFaint,
                    ),
                  ),
                ),
                if (due.isEmpty && dueSnap.hasData)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.x4),
                    child: Text(
                      'Nothing on the recurring shelf yet.',
                      style: LedgerType.bodyText.copyWith(color: c.inkFaint),
                    ),
                  ),
                if (bills.isNotEmpty) const RuleHeader('bills'),
                for (final (i, d) in bills.indexed)
                  LedgerLine(
                    leading: _short(d.due),
                    title: d.recurring.title,
                    amount: Inr.format(d.recurring.amountPaise),
                    last: i == bills.length - 1,
                    onTap: () => _paySheet(context, ref, d),
                  ),
                if (subs.isNotEmpty) const RuleHeader('subscriptions'),
                for (final (i, d) in subs.indexed)
                  LedgerLine(
                    leading: _short(d.due),
                    title: d.recurring.title,
                    amount: Inr.format(d.recurring.amountPaise),
                    last: i == subs.length - 1,
                    onTap: () => _paySheet(context, ref, d),
                  ),
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
  }

  Future<void> _paySheet(BuildContext context, WidgetRef ref, DueItem d) async {
    final c = LedgerColors.of(context);
    final paid = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.recurring.title,
                style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                'lands ${_short(d.due)} · ${Inr.format(d.recurring.amountPaise)}',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
              const SizedBox(height: Gap.x4),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  'Paid — stamp ${Inr.format(d.recurring.amountPaise)}',
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not yet'),
              ),
            ],
          ),
        ),
      ),
    );
    if (paid == true) {
      HapticFeedback.lightImpact();
      await ref.read(recurringRepoProvider).markPaid(d.recurring);
    }
  }
}

// ————— goals —————

class _GoalsTab extends ConsumerWidget {
  const _GoalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final goals = ref.watch(goalRepoProvider);

    return StreamBuilder<List<GoalView>>(
      stream: goals.watchViews(),
      builder: (context, snapshot) {
        final views = snapshot.data ?? const <GoalView>[];
        if (snapshot.hasData && views.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.x6),
            child: Text(
              'Nothing being saved for yet.',
              style: LedgerType.bodyText.copyWith(color: c.inkFaint),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, v) in views.indexed)
              _GoalCard(view: v, last: i == views.length - 1),
          ],
        );
      },
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.view, required this.last});

  final GoalView view;
  final bool last;

  static String _month(DateTime d) {
    const s = [
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
    return '${s[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final g = view.goal;
    final eta = view.etaFrom(DateTime.now());
    final saving = g.kind == GoalKind.save;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: Gap.x4),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.rule)),
      ),
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
            style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              text: Inr.format(view.donePaise),
              children: [
                TextSpan(
                  text:
                      '  of ${Inr.format(g.targetPaise)}${saving ? '' : ' cleared'}',
                  style: LedgerType.amount.copyWith(
                    fontSize: 12,
                    color: c.inkFaint,
                  ),
                ),
              ],
            ),
            style: LedgerType.amountTotal.copyWith(color: c.ink),
          ),
          const SizedBox(height: Gap.x2),
          BudgetBar(
            pace: BudgetPace(
              spentPaise: view.donePaise,
              limitPaise: g.targetPaise,
              elapsedDays: 1,
              totalDays: 1,
            ),
            showToday: false,
          ),
          const SizedBox(height: Gap.x2),
          Text(
            view.reached
                ? 'Done. The seal is yours.'
                : eta == null
                ? 'Fed by ${view.entryCount} stamped '
                      '${view.entryCount == 1 ? 'entry' : 'entries'}.'
                : 'On pace for ${_month(eta)} · fed by '
                      '${view.entryCount} stamped '
                      '${view.entryCount == 1 ? 'entry' : 'entries'}.',
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              color: c.inkFaint,
            ),
          ),
          const SizedBox(height: Gap.x3),
          Row(
            children: [
              LedgerChip(
                'add to this',
                icon: Icons.add,
                selected: true,
                onTap: () => _contribute(context, ref),
              ),
              const SizedBox(width: Gap.x2),
              LedgerChip(
                'the entries',
                icon: LedgerIcons.resolve('book'),
                onTap: () => _entries(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _contribute(BuildContext context, WidgetRef ref) async {
    final c = LedgerColors.of(context);
    final accounts = await ref
        .read(dbProvider)
        .select(ref.read(dbProvider).accounts)
        .get();
    if (accounts.isEmpty || !context.mounted) return;
    final controller = TextEditingController(
      text: view.goal.monthlyPaise == null
          ? ''
          : (view.goal.monthlyPaise! ~/ 100).toString(),
    );
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: Gap.page,
          right: Gap.page,
          top: Gap.x4,
          bottom: MediaQuery.of(context).viewInsets.bottom + Gap.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add to ${view.goal.name}',
              style: LedgerType.bodyStrong.copyWith(color: c.ink),
            ),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: LedgerType.heroAmount.copyWith(fontSize: 32, color: c.ink),
              decoration: InputDecoration(
                prefixText: '₹',
                prefixStyle: LedgerType.heroAmount.copyWith(
                  fontSize: 32,
                  color: c.inkFaint,
                ),
                border: InputBorder.none,
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Stamp it'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final rupees = int.tryParse(controller.text.trim());
      if (rupees != null && rupees > 0) {
        HapticFeedback.lightImpact();
        await ref
            .read(goalRepoProvider)
            .contribute(
              goal: view.goal,
              amountPaise: rupees * 100,
              accountId: accounts.first.id,
            );
      }
    }
  }

  Future<void> _entries(BuildContext context, WidgetRef ref) async {
    final c = LedgerColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.page),
          child: StreamBuilder<List<Txn>>(
            stream: ref.read(goalRepoProvider).watchEntries(view.goal.id),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <Txn>[];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      leading: '${t.at.day}/${t.at.month}',
                      title: t.title,
                      amount: Inr.format(t.amountPaise),
                      last: i == rows.length - 1 || i == 7,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
