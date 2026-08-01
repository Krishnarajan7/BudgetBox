import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../data/db.dart';
import '../../data/providers.dart';

/// The monthly story: five swipeable pages in the app's voice, ending in the
/// Sankey. The one place the app gets to be theatrical — it earned it.
class StoryPage extends ConsumerStatefulWidget {
  const StoryPage({super.key});

  @override
  ConsumerState<StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends ConsumerState<StoryPage> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final db = ref.watch(dbProvider);
    final txns = ref.watch(txnRepoProvider);
    final now = DateTime.now();

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Txn>>(
          stream: txns.watchRange(
              LedgerDates.monthStart(now), LedgerDates.monthEnd(now)),
          builder: (context, txnSnap) {
            final month = txnSnap.data ?? const [];
            return StreamBuilder<List<Category>>(
              stream: db.select(db.categories).watch(),
              builder: (context, catSnap) {
                final cats = {
                  for (final x in catSnap.data ?? const <Category>[])
                    x.id: x
                };
                final facts = _MonthFacts(month, cats, now);
                final pages = _buildPages(c, facts);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Gap.page, Gap.x3, Gap.page, 0),
                      child: Row(
                        children: [
                          Text(
                            '${facts.monthName}, page ${_page + 1} of ${pages.length}',
                            style: LedgerType.amount
                                .copyWith(fontSize: 12, color: c.inkFaint),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            child: Icon(Icons.close,
                                size: 18, color: c.inkFaint),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _controller,
                        onPageChanged: (i) => setState(() => _page = i),
                        children: pages,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.x6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < pages.length; i++)
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == _page ? c.ink : c.rule,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildPages(LedgerColors c, _MonthFacts f) {
    Widget page(List<InlineSpan> spans, {Widget? extra}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: spans),
                style:
                    LedgerType.title.copyWith(fontSize: 28, color: c.ink),
              ),
              if (extra != null) ...[const SizedBox(height: Gap.x4), extra],
            ],
          ),
        );

    TextSpan bold(String t) => TextSpan(
        text: t,
        style: const TextStyle(
            fontVariations: [FontVariation('wght', 660)]));

    return [
      page([
        const TextSpan(text: 'This month, '),
        bold(Inr.format(f.spent)),
        const TextSpan(text: ' left the book.'),
      ]),
      page([
        bold(f.topCategoryName),
        const TextSpan(text: ' took the biggest bite — '),
        bold(Inr.format(f.topCategoryPaise)),
        const TextSpan(text: '.'),
      ]),
      page(
        [
          const TextSpan(text: 'Your biggest day was the '),
          bold('${f.biggestDay}th'),
          const TextSpan(text: ' — '),
          bold(Inr.format(f.biggestDayPaise)),
          const TextSpan(text: '.'),
        ],
        extra: Text(
          'Worth it? Only you know. The book just keeps the score.',
          style: LedgerType.bodyText.copyWith(color: c.inkFaint),
        ),
      ),
      page([
        bold('${f.quietDays}'),
        const TextSpan(text: ' quiet days — pages with nothing on them.'),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.page),
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
              child: CustomPaint(
                painter: _SankeyPainter(
                  income: math.max(f.income, f.spent),
                  flows: f.sankeyFlows,
                  c: c,
                ),
              ),
            ),
            const SizedBox(height: Gap.x4),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '${Inr.format(math.max(f.income, f.spent))} came in. '),
                TextSpan(
                  text: '${Inr.format(f.kept)} stayed.',
                  style: const TextStyle(
                      fontVariations: [FontVariation('wght', 660)]),
                ),
              ]),
              style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
            ),
          ],
        ),
      ),
    ];
  }
}

class _MonthFacts {
  _MonthFacts(List<Txn> month, Map<int, Category> cats, DateTime now) {
    final expenses =
        month.where((t) => t.type == TxnType.expense).toList();
    spent = expenses.fold(0, (s, t) => s + t.amountPaise);
    income = month
        .where((t) => t.type == TxnType.income)
        .fold(0, (s, t) => s + t.amountPaise);
    kept = math.max(income - spent, 0);
    monthName = const [
      'january', 'february', 'march', 'april', 'may', 'june',
      'july', 'august', 'september', 'october', 'november', 'december',
    ][now.month - 1];

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

    quietDays =
        List.generate(now.day, (i) => i + 1).where((d) => !byDay.containsKey(d)).length;

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
  }

  late final int spent;
  late final int income;
  late final int kept;
  late final String monthName;
  late final String topCategoryName;
  late final int topCategoryPaise;
  late final int biggestDay;
  late final int biggestDayPaise;
  late final int quietDays;
  late final List<(String, int, bool)> sankeyFlows;
}

/// One hue, weighted by magnitude — income fanning into where it went.
class _SankeyPainter extends CustomPainter {
  _SankeyPainter({required this.income, required this.flows, required this.c});

  final int income;
  final List<(String, int, bool)> flows;
  final LedgerColors c;

  @override
  void paint(Canvas canvas, Size size) {
    if (income <= 0 || flows.isEmpty) return;
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
      label.paint(
          canvas, Offset(x1 + 12, yr + h / 2 - label.height / 2));

      yl += h;
      yr += h + gapPx;
    }
  }

  @override
  bool shouldRepaint(_SankeyPainter old) =>
      old.income != income || old.flows != flows;
}
