import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/cat_mark.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../book/book_page.dart' show whereItWent, bookMonthShift;

/// Where the money went, said plainly.
///
/// One month at a time: what it cost against last month, which categories
/// carried it, where the weight *moved* — the "you spend more on X" the book
/// exists to say — and the few single lines heavy enough to name. Everything
/// is computed from the ledger itself, on the phone, so the page is exactly
/// as correct offline as on.
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
                child: PenChevron(
                    size: 14, color: onNow ? c.rule : c.inkFaint),
              ),
            ),
          ),
        ],
      ),
      child: StreamBuilder<List<Txn>>(
        stream: txns.watchRange(_month, LedgerDates.monthEnd(_month)),
        builder: (context, nowSnap) {
          return StreamBuilder<List<Txn>>(
            stream: txns.watchRange(prev, LedgerDates.monthEnd(prev)),
            builder: (context, prevSnap) {
              return StreamBuilder<List<Category>>(
                stream: db.select(db.categories).watch(),
                builder: (context, catSnap) {
                  final nowAll = nowSnap.data ?? const <Txn>[];
                  final thenAll = prevSnap.data ?? const <Txn>[];
                  final cats = {
                    for (final cat in catSnap.data ?? const <Category>[])
                      cat.id: cat,
                  };
                  return _body(c, nowAll, thenAll, cats);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _body(
    LedgerColors c,
    List<Txn> nowAll,
    List<Txn> thenAll,
    Map<int, Category> cats,
  ) {
    List<(int?, int)> spend(List<Txn> all) => [
          for (final t in all.where((t) => t.type == TxnType.expense))
            (t.categoryId, t.amountPaise),
        ];
    final nowSpend = spend(nowAll);
    final thenSpend = spend(thenAll);
    final nowTotal = nowSpend.fold(0, (s, e) => s + e.$2);
    final thenTotal = thenSpend.fold(0, (s, e) => s + e.$2);
    final delta = nowTotal - thenTotal;

    final slices = whereItWent(nowSpend);
    final shifts = categoryShifts(nowSpend, thenSpend);
    final heaviest = nowAll
        .where((t) => t.type == TxnType.expense)
        .toList()
      ..sort((a, b) => b.amountPaise.compareTo(a.amountPaise));

    String catName(int? id) =>
        id == null ? 'unfiled' : (cats[id]?.name ?? 'unfiled');
    String? catIcon(int? id) => id == null ? null : cats[id]?.icon;

    if (nowSpend.isEmpty && thenSpend.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Gap.page),
        child: Text(
          'Nothing written in $_label — a quiet page has nothing to explain.',
          style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Gap.page),
      children: [
        const SizedBox(height: Gap.x4),
        // ————— the month, in one figure —————
        Text(_label.toLowerCase(),
            style: LedgerType.label.copyWith(color: c.inkFaint)),
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

        // ————— where it went —————
        if (slices.isNotEmpty)
          LedgerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RuleHeader('where it went'),
                for (final (i, s) in slices.indexed)
                  WhereRow(
                    key: ValueKey('iw-${s.isOther ? 'other' : s.categoryId}'),
                    label: s.isOther ? 'everything else' : catName(s.categoryId),
                    iconKey: s.isOther ? null : catIcon(s.categoryId),
                    amount: Inr.format(s.paise),
                    frac: slices.first.paise <= 0
                        ? 0
                        : s.paise / slices.first.paise,
                    stagger: i,
                    last: i == slices.length - 1,
                  ),
              ],
            ),
          ),

        // ————— what moved —————
        if (shifts.isNotEmpty)
          LedgerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RuleHeader('versus last month'),
                for (final (i, s) in shifts.indexed)
                  LedgerLine(
                    mark: CatMark(catIcon(s.categoryId), size: 14),
                    title: catName(s.categoryId),
                    detail: s.isNew
                        ? 'new this month'
                        : s.wentQuiet
                            ? 'went quiet'
                            : s.deltaPaise > 0
                                ? 'more than last month'
                                : 'less than last month',
                    amount:
                        '${s.deltaPaise > 0 ? '+' : '−'}${Inr.format(s.deltaPaise.abs())}',
                    amountColor: s.deltaPaise > 0 ? c.warn : c.jama,
                    last: i == shifts.length - 1,
                  ),
              ],
            ),
          ),

        // ————— the heaviest single lines —————
        if (heaviest.isNotEmpty)
          LedgerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RuleHeader('heaviest lines'),
                for (final (i, t) in heaviest.take(3).indexed)
                  LedgerLine(
                    leading: LedgerDates.ddMmm(t.at),
                    title: t.title,
                    detail: catName(t.categoryId),
                    amount: Inr.format(t.amountPaise),
                    last: i == heaviest.take(3).length - 1,
                  ),
              ],
            ),
          ),
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
