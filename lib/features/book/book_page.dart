import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/ledger_app_bar.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import 'txn_editor.dart';

/// The transactions list IS the ledger: day-ruled pages, running totals,
/// swipe to strike an entry out, and a heat view where quiet days stay pale.
class BookPage extends ConsumerStatefulWidget {
  const BookPage({super.key});

  @override
  ConsumerState<BookPage> createState() => _BookPageState();
}

class _BookPageState extends ConsumerState<BookPage> {
  bool _heat = false;
  int? _categoryFilter;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final txns = ref.watch(txnRepoProvider);
    final db = ref.watch(dbProvider);
    final now = DateTime.now();

    return StreamBuilder<List<Txn>>(
      stream: txns.watchRange(
          LedgerDates.monthStart(now), LedgerDates.monthEnd(now)),
      builder: (context, txnSnap) {
        final all = txnSnap.data ?? const [];
        return StreamBuilder<List<Category>>(
          stream: db.select(db.categories).watch(),
          builder: (context, catSnap) {
            final cats = catSnap.data ?? const [];
            final catName = {for (final x in cats) x.id: x};

            var rows = all;
            if (_categoryFilter != null) {
              rows = rows
                  .where((t) => t.categoryId == _categoryFilter)
                  .toList();
            }
            if (_query.isNotEmpty) {
              final q = _query.toLowerCase();
              rows = rows
                  .where((t) => t.title.toLowerCase().contains(q))
                  .toList();
            }

            final monthSpent = all
                .where((t) => t.type == TxnType.expense)
                .fold(0, (s, t) => s + t.amountPaise);

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: Gap.page),
              children: [
                LedgerAppBar(
                  title: 'Book',
                  trailing: InkWell(
                    onTap: () => setState(() => _heat = !_heat),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _heat ? Icons.view_list_outlined : Icons.grid_on_outlined,
                          size: 14,
                          color: c.quill,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _heat ? 'list' : 'heat',
                          style: LedgerType.bodyStrong
                              .copyWith(fontSize: 13, color: c.quill),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Gap.x3),
                if (_heat)
                  ..._heatView(c, now, all, monthSpent)
                else ...[
                  _filters(c, cats),
                  ..._ledgerView(c, now, rows, catName),
                ],
                const SizedBox(height: Gap.x6),
              ],
            );
          },
        );
      },
    );
  }

  Widget _filters(LedgerColors c, List<Category> cats) {
    final used = cats
        .where((x) => x.kind == CategoryKind.expense)
        .take(3)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              LedgerChip('all',
                  selected: _categoryFilter == null,
                  onTap: () => setState(() => _categoryFilter = null)),
              const SizedBox(width: Gap.x2),
              for (final x in used) ...[
                LedgerChip(x.name.split(' ').first.toLowerCase(),
                    icon: LedgerIcons.resolve(x.icon),
                    selected: _categoryFilter == x.id,
                    onTap: () => setState(() =>
                        _categoryFilter = _categoryFilter == x.id ? null : x.id)),
                const SizedBox(width: Gap.x2),
              ],
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: Gap.x3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.rule)),
          ),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: LedgerType.bodyText.copyWith(color: c.ink, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'search the book…',
              hintStyle: LedgerType.bodyText
                  .copyWith(fontSize: 14, color: c.inkFaint),
              icon: Icon(Icons.search, size: 16, color: c.inkFaint),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  // `cats` is kept threaded through for the next pass, when LedgerLine grows
  // a drawn category mark to replace the detail column.
  List<Widget> _ledgerView(LedgerColors c, DateTime now, List<Txn> rows,
      Map<int, Category> cats) {
    if (rows.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.x8),
          child: Text(
            _query.isEmpty
                ? 'This month\'s pages are blank so far.'
                : 'Nothing in the book matches "$_query".',
            style: LedgerType.bodyText.copyWith(color: c.inkFaint),
          ),
        ),
      ];
    }

    final byDay = <int, List<Txn>>{};
    for (final t in rows) {
      byDay.putIfAbsent(t.at.day, () => []).add(t);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    final widgets = <Widget>[];
    for (final day in days) {
      final list = byDay[day]!;
      final spent = list
          .where((t) => t.type == TxnType.expense)
          .fold(0, (s, t) => s + t.amountPaise);
      widgets.add(DayHeader(
        label: day == now.day
            ? 'Today · ${_weekday(DateTime(now.year, now.month, day))} $day'
            : '${_weekday(DateTime(now.year, now.month, day))} $day',
        total: Inr.format(spent),
      ));
      for (final (i, t) in list.indexed) {
        widgets.add(
          Dismissible(
            key: ValueKey('txn-${t.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              color: c.seal.withValues(alpha: 0.12),
              padding: const EdgeInsets.only(right: Gap.x4),
              child: Icon(Icons.close, size: 16, color: c.seal),
            ),
            onDismissed: (_) async {
              HapticFeedback.mediumImpact();
              await ref.read(txnRepoProvider).deleteTxn(t.id);
            },
            child: LedgerLine(
              leading:
                  '${t.at.hour.toString().padLeft(2, '0')}:${t.at.minute.toString().padLeft(2, '0')}',
              title: t.title,
              amount: t.type == TxnType.income
                  ? Inr.format(t.amountPaise, signed: true)
                  : Inr.format(t.amountPaise),
              amountColor: t.type == TxnType.income ? c.jama : null,
              last: i == list.length - 1,
              onTap: () => showTxnEditor(context, t),
              onLongPress: () => showTxnActions(context, ref, t),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  List<Widget> _heatView(
      LedgerColors c, DateTime now, List<Txn> all, int monthSpent) {
    final days = List<int>.filled(LedgerDates.daysInMonth(now), 0);
    for (final t in all.where((t) => t.type == TxnType.expense)) {
      days[t.at.day - 1] += t.amountPaise;
    }
    var maxDay = 1;
    var maxPaise = 0;
    for (final (i, v) in days.indexed) {
      if (v > maxPaise) {
        maxPaise = v;
        maxDay = i + 1;
      }
    }
    final quiet = days.take(now.day).where((v) => v == 0).length;

    return [
      HeroAmount(
        caption: '${_monthName(now.month)}, day by day',
        amount: Inr.format(monthSpent),
        size: 30,
      ),
      const SizedBox(height: Gap.x3),
      HeatGrid(dayTotalsPaise: days),
      const SizedBox(height: Gap.x2),
      Row(
        children: [
          Text('pale = quiet day',
              style:
                  LedgerType.bodyText.copyWith(fontSize: 11, color: c.inkFaint)),
          const Spacer(),
          if (maxPaise > 0)
            Text('darkest = ${Inr.format(maxPaise)} · day $maxDay',
                style: LedgerType.bodyText
                    .copyWith(fontSize: 11, color: c.inkFaint)),
        ],
      ),
      const RuleHeader('what the month looks like'),
      LedgerLine(title: 'Quiet days', amount: '$quiet'),
      LedgerLine(
          title: 'Entries written',
          amount: '${all.length}',
          last: true),
    ];
  }

  static String _weekday(DateTime d) {
    const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return w[d.weekday - 1];
  }

  static String _monthName(int m) {
    const s = [
      'january', 'february', 'march', 'april', 'may', 'june',
      'july', 'august', 'september', 'october', 'november', 'december',
    ];
    return s[m - 1];
  }
}
