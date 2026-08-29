import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'insight_math.dart';

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
import '../book/book_page.dart';

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
                  return _body(c, nowAll, thenAll, pastAll, cats);
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
    List<Txn> pastAll,
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

    // Four slices at most — one per ink in the drawer; the rest folds.
    final slices = whereItWent(nowSpend, top: 4);
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

        // ————— the one sentence worth reading first —————
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

        // ————— where it went —————
        if (slices.isNotEmpty)
          LedgerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RuleHeader('where it went'),
                const SizedBox(height: Gap.x3),
                Center(
                  child: DrawIn(
                    duration: const Duration(milliseconds: 700),
                    builder: (context, t) => CustomPaint(
                      size: const Size.square(148),
                      painter: _WheelPainter(
                        fractions: [
                          for (final s in slices)
                            s.paise /
                                slices.fold<int>(0, (a, b) => a + b.paise),
                        ],
                        sweep: t,
                        inks: c.chartInks,
                        rest: c.rule,
                        hole: c.paperRaised,
                        foldedLast: slices.last.isOther,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.x1),
                for (final (i, s) in slices.indexed)
                  WhereRow(
                    key: ValueKey('iw-${s.isOther ? 'other' : s.categoryId}'),
                    label: s.isOther
                        ? 'everything else'
                        : catName(s.categoryId),
                    iconKey: s.isOther ? null : catIcon(s.categoryId),
                    amount: Inr.format(s.paise),
                    frac: slices.first.paise <= 0
                        ? 0
                        : s.paise / slices.first.paise,
                    // The row wears its slice's ink — colour follows the
                    // category from wheel to legend.
                    ink: s.isOther
                        ? c.rule
                        : c.chartInks[i % c.chartInks.length],
                    stagger: i,
                    last: i == slices.length - 1,
                  ),
              ],
            ),
          ),

        // ————— what holds the most —————
        //
        // The whole month, ranked — no fold, no "everything else" hiding
        // two-thirds of the money. Each category carries its share, a bar
        // against the heaviest, and one line of judgement against its own
        // last three months. Tap a row and the book opens already turned
        // to this month and narrowed to that category.
        if (stories.isNotEmpty)
          LedgerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RuleHeader('what holds the most'),
                const SizedBox(height: Gap.x2),
                for (final (i, story) in stories.indexed)
                  _StoryRow(
                    story: story,
                    name: catName(story.categoryId),
                    iconKey: catIcon(story.categoryId),
                    topPaise: stories.first.paise,
                    ink: i < c.chartInks.length ? c.chartInks[i] : c.inkFaint,
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

/// A wheel of the drawer's four print inks, heaviest slice first,
/// "everything else" in rule grey — each slice parted from its neighbour by
/// a hairline of the card, the way inked areas never quite touch on paper.
/// The bars beneath are its legend, each wearing its slice's ink — the
/// wheel shows the shape of the month, the rows name it.
class _WheelPainter extends CustomPainter {
  const _WheelPainter({
    required this.fractions,
    required this.sweep,
    required this.inks,
    required this.rest,
    required this.hole,
    required this.foldedLast,
  });

  /// Slice shares in row order (already heaviest-first).
  final List<double> fractions;

  /// Draw-in progress, 0–1: the wheel sweeps itself clockwise.
  final double sweep;
  final List<Color> inks;
  final Color rest;
  final Color hole;

  /// True when the last share is a folded "everything else" — only then
  /// does it wear rule grey instead of an ink.
  final bool foldedLast;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.width / 2;
    var start = -1.5707963; // twelve o'clock
    final total = fractions.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;

    final bounds = <double>[start];
    for (final (i, f) in fractions.indexed) {
      final full = (f / total) * 6.2831853;
      final drawn = (sweep * 6.2831853) - (start + 1.5707963);
      if (drawn <= 0) break;
      final paint = Paint()
        ..color = foldedLast && i == fractions.length - 1
            ? rest
            : inks[i % inks.length];
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        start,
        full.clamp(0, drawn),
        true,
        paint,
      );
      start += full;
      bounds.add(start);
    }
    // The breath of card between slices — none when one slice is the wheel.
    if (fractions.length > 1) {
      final gap = Paint()
        ..color = hole
        ..strokeWidth = 2;
      for (final b in bounds) {
        canvas.drawLine(
          centre,
          centre + Offset(math.cos(b), math.sin(b)) * radius,
          gap,
        );
      }
    }
    // The hole that makes it a wheel, not a pie chart from a template.
    canvas.drawCircle(centre, radius * 0.62, Paint()..color = hole);
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.sweep != sweep || old.fractions != fractions || old.inks != inks;
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
/// share — and beneath them, its bar against the heaviest category.
class _StoryRow extends StatelessWidget {
  const _StoryRow({
    required this.story,
    required this.name,
    required this.iconKey,
    required this.topPaise,
    required this.ink,
    required this.last,
    required this.onTap,
  });

  final CategoryStory story;
  final String name;
  final String? iconKey;
  final int topPaise;
  final Color ink;
  final bool last;
  final VoidCallback onTap;

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
        return s.count == 1 ? '1 entry · about usual' : '${s.count} entries · about usual';
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
        padding: EdgeInsets.only(top: Gap.x2, bottom: last ? Gap.x1 : Gap.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CatMark(iconKey, size: 14),
                const SizedBox(width: Gap.x2),
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
            // Its length against the heaviest — the differentiation at a
            // glance the wheel's four slices could not give.
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: DrawIn(
                duration: const Duration(milliseconds: 500),
                builder: (context, t) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor:
                      (topPaise <= 0 ? 0.0 : story.paise / topPaise) * t,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
