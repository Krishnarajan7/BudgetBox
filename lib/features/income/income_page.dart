import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/plates.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/txn_repo.dart';
import '../add/money_moves.dart';
import '../book/txn_editor.dart';
import '../today/widgets/digit_roll.dart';
import '../today/widgets/ledger_rows.dart';
import 'pot_math.dart';

/// How wide a window the page reads. The chip is what's tapped; the phrase
/// is what the comparison tile says underneath the hero.
enum IncomeRange { month, quarter, fy, year }

extension IncomeRangeCopy on IncomeRange {
  String get chip => switch (this) {
    IncomeRange.month => 'month',
    IncomeRange.quarter => '3M',
    IncomeRange.fy => 'FY',
    IncomeRange.year => '12M',
  };

  /// The window's first month, given the month the page is anchored on.
  DateTime start(DateTime anchor) => switch (this) {
    IncomeRange.month => anchor,
    IncomeRange.quarter => DateTime(anchor.year, anchor.month - 2, 1),
    IncomeRange.fy => LedgerDates.fyStart(anchor),
    IncomeRange.year => DateTime(anchor.year, anchor.month - 11, 1),
  };

  /// How many months the window holds — the previous equal window is the
  /// same count of months ending just before this one begins.
  int months(DateTime anchor) {
    final s = start(anchor);
    return (anchor.year - s.year) * 12 + (anchor.month - s.month) + 1;
  }

  String phrase(DateTime anchor, DateTime now) => switch (this) {
    IncomeRange.month => 'last month',
    IncomeRange.quarter => 'the three months before',
    IncomeRange.fy => 'the same stretch of last ${LedgerDates.fyLabel(now)}',
    IncomeRange.year => 'the twelve months before',
  };

  /// The short form the tile wears.
  String tile(DateTime anchor) => switch (this) {
    IncomeRange.month =>
      'vs ${LedgerDates.months[(anchor.month + 10) % 12].toLowerCase()}',
    IncomeRange.quarter => 'vs prior 3M',
    IncomeRange.fy => 'vs last FY',
    IncomeRange.year => 'vs prior 12M',
  };
}

/// The sum of income across a stretch of [flows], and the same for the
/// stretch just before it — the two figures every comparison needs.
/// Pure, so the arithmetic is testable without a widget in sight.
({int now, int before, int spent}) incomeWindow(
  List<MonthFlow> flows,
  DateTime start,
  int months,
) {
  bool inside(DateTime m, DateTime from, int n) {
    final idx = (m.year - from.year) * 12 + (m.month - from.month);
    return idx >= 0 && idx < n;
  }

  final before = DateTime(start.year, start.month - months, 1);
  var now = 0;
  var prev = 0;
  var spent = 0;
  for (final f in flows) {
    if (inside(f.month, start, months)) {
      now += f.inPaise;
      spent += f.outPaise;
    } else if (inside(f.month, before, months)) {
      prev += f.inPaise;
    }
  }
  return (now: now, before: prev, spent: spent);
}

/// Income grouped by where it came from — the title, case-folded, so
/// "Salary" and "salary" are one source. Heaviest first.
List<({String name, int paise, int count, int? categoryId})> incomeSources(
  List<Txn> rows,
) {
  final byKey =
      <String, ({String name, int paise, int count, int? categoryId})>{};
  for (final t in rows) {
    if (t.type != TxnType.income) continue;
    final key = t.title.trim().toLowerCase();
    final cur = byKey[key];
    byKey[key] = (
      name: cur?.name ?? t.title.trim(),
      paise: (cur?.paise ?? 0) + t.amountPaise,
      count: (cur?.count ?? 0) + 1,
      categoryId: cur?.categoryId ?? t.categoryId,
    );
  }
  return byKey.values.toList()..sort((a, b) => b.paise.compareTo(a.paise));
}

/// What kept means, as a share of what came in — the savings rate, said as
/// a whole percent. Null when nothing came in, because 0 ÷ 0 is not a
/// figure a page should print.
int? keptShare(int inPaise, int outPaise) {
  if (inPaise <= 0) return null;
  return ((inPaise - outPaise) * 100 / inPaise).round().clamp(-999, 100);
}

/// The income page: everything the book earned, on its own paper.
///
/// A gliding pill picks the window. The hero is the window's figure; three
/// tiles beneath it answer what the hero raises — how much was kept, how
/// it compares to the window before, when the next salary lands. Then the
/// year as paired strokes on a plate, the sources on a plate with their
/// medallions, and the lines.
class IncomePage extends ConsumerStatefulWidget {
  const IncomePage({super.key, this.initialMonth});

  /// Which month to anchor on — the Book hands over the month it was open
  /// to. Null anchors on the current month.
  final DateTime? initialMonth;

  @override
  ConsumerState<IncomePage> createState() => _IncomePageState();
}

class _IncomePageState extends ConsumerState<IncomePage> {
  IncomeRange _range = IncomeRange.month;
  late DateTime _anchor = LedgerDates.monthStart(
    widget.initialMonth ?? DateTime.now(),
  );
  Future<List<MonthFlow>>? _flows;
  int _salaryDay = 1;
  int _drawToken = 0;

  @override
  void initState() {
    super.initState();
    _flows = ref.read(txnRepoProvider).monthlyFlow(months: 24);
    ref.read(settingsRepoProvider).salaryDay().then((d) {
      if (mounted) setState(() => _salaryDay = d);
    });
  }

  void _pick(IncomeRange r) {
    if (r == _range) return;
    setState(() {
      _range = r;
      _drawToken++;
    });
  }

  void _anchorOn(DateTime month) {
    HapticFeedback.selectionClick();
    setState(() {
      _anchor = month;
      _range = IncomeRange.month;
      _drawToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final now = DateTime.now();
    final start = _range.start(_anchor);
    final months = _range.months(_anchor);
    final end = DateTime(_anchor.year, _anchor.month + 1, 1);
    final db = ref.watch(dbProvider);

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: StreamBuilder<List<Category>>(
          stream: db.select(db.categories).watch(),
          builder: (context, catSnap) {
            final cats = {
              for (final x in catSnap.data ?? const <Category>[]) x.id: x,
            };
            return StreamBuilder<List<Txn>>(
              stream: ref.watch(txnRepoProvider).watchRange(start, end),
              builder: (context, snap) {
                final window = snap.data ?? const <Txn>[];
                final lines = [
                  for (final t in window)
                    if (t.type == TxnType.income) t,
                ];
                // The pots are added up since the book began as well as
                // for the window: "what is left of the salary" is a
                // running answer, not a monthly one.
                return StreamBuilder<List<Txn>>(
                  stream: ref
                      .watch(txnRepoProvider)
                      .watchRange(DateTime(2000), DateTime(2100)),
                  builder: (context, allSnap) {
                    final everything = allSnap.data ?? window;
                    final pots = potLedgers(
                      window,
                      everything,
                      catSnap.data ?? const <Category>[],
                    );
                    final loose = unassigned(window);
                    return FutureBuilder<List<MonthFlow>>(
                      future: _flows,
                      builder: (context, flowSnap) {
                        final flows = flowSnap.data ?? const <MonthFlow>[];
                        final w = incomeWindow(flows, start, months);
                        // While the flows are still on their way, the lines
                        // already in hand say the figure — the hero never
                        // waits on a second read to print.
                        final earned = flows.isEmpty
                            ? lines.fold(0, (s, t) => s + t.amountPaise)
                            : w.now;
                        final share = keptShare(earned, w.spent);
                        final sources = incomeSources(lines);
                        return ListView(
                          padding: EdgeInsets.fromLTRB(
                            Gap.page,
                            0,
                            Gap.page,
                            MediaQuery.paddingOf(context).bottom + Gap.x8,
                          ),
                          children: [
                            _bar(c),
                            const SizedBox(height: Gap.x4),
                            PillSegments(
                              labels: [
                                for (final r in IncomeRange.values) r.chip,
                              ],
                              index: _range.index,
                              onSelect: (i) => _pick(IncomeRange.values[i]),
                            ),
                            const SizedBox(height: Gap.x6),
                            Text(
                              _windowLabel(start, months, now),
                              style: LedgerType.label.copyWith(
                                color: c.inkFaint,
                              ),
                            ),
                            const SizedBox(height: 2),
                            DigitRoll(
                              paise: earned,
                              style: LedgerType.heroAmount.copyWith(
                                fontSize: 44,
                                color: c.ink,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            // ————— the three answers —————
                            StatTiles(
                              tiles: [
                                StatTile(
                                  label: 'kept',
                                  value: share == null
                                      ? '—'
                                      : Inr.format((earned - w.spent).abs()),
                                  tone: share == null
                                      ? c.inkFaint
                                      : share >= 0
                                      ? c.jama
                                      : c.warn,
                                  sub: share == null
                                      ? 'nothing in yet'
                                      : share >= 0
                                      ? '$share% of it'
                                      : 'spent past it',
                                ),
                                StatTile(
                                  label: _range.tile(_anchor),
                                  value: flows.isEmpty
                                      ? '—'
                                      : w.before == 0
                                      ? (w.now == 0 ? '—' : 'new')
                                      : (w.now - w.before).abs() < 100
                                      ? 'level'
                                      : '${w.now > w.before ? '+' : '−'}'
                                            '${Inr.format((w.now - w.before).abs())}',
                                  tone: flows.isEmpty || w.before == 0
                                      ? c.inkFaint
                                      : w.now >= w.before
                                      ? c.jama
                                      : c.ink,
                                  sub: w.before == 0
                                      ? 'nothing to compare'
                                      : 'was ${Inr.compact(w.before)}',
                                ),
                                _salaryTile(c, lines, now),
                              ],
                            ),
                            // ————— the pots: what each source has left —————
                            //
                            // Salary and extra work land in the same pocket,
                            // but the rule he keeps is about where the money
                            // came from. Each pot: in, drawn on, kept — for
                            // the window and since the book began.
                            if (pots.isNotEmpty) ...[
                              SectionHead(
                                'kept by source',
                                trailing: Text(
                                  'what each pot has left',
                                  style: LedgerType.bodyText.copyWith(
                                    fontSize: 11,
                                    color: c.inkFaint,
                                  ),
                                ),
                              ),
                              for (final p in pots)
                                Plate(
                                  key: ValueKey('pot-${p.categoryId}'),
                                  margin: const EdgeInsets.only(bottom: Gap.x3),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      PlateHead(
                                        p.name.toLowerCase(),
                                        sub: potLine(p),
                                        trailing: Text(
                                          p.keptPaise < 0
                                              ? '−${Inr.format(-p.keptPaise)}'
                                              : Inr.format(p.keptPaise),
                                          style: LedgerType.amountTotal
                                              .copyWith(
                                                fontSize: 17,
                                                color: p.keptPaise < 0
                                                    ? c.warn
                                                    : c.jama,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(height: Gap.x2),
                                      RoundedBar(
                                        fraction: p.keptShare,
                                        ink: p.keptPaise < 0 ? c.warn : c.jama,
                                        height: 5,
                                      ),
                                      const SizedBox(height: Gap.x2),
                                      Row(
                                        children: [
                                          _potFigure(c, 'came in', p.inPaise),
                                          _potFigure(c, 'drawn on', p.outPaise),
                                          _potFigure(
                                            c,
                                            'kept, ever',
                                            p.allKeptPaise,
                                            signed: true,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              if (loose.count > 0)
                                Pressable(
                                  key: const ValueKey('income-assign'),
                                  onTap: () => _assign(
                                    context,
                                    window,
                                    catSnap.data ?? const [],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 2,
                                      bottom: Gap.x2,
                                    ),
                                    child: Text(
                                      '${loose.count} ${loose.count == 1 ? 'line' : 'lines'} '
                                      'worth ${Inr.format(loose.paise)} never named a pot — settle them ›',
                                      style: LedgerType.bodyStrong.copyWith(
                                        fontSize: 12.5,
                                        height: 1.4,
                                        color: c.quill,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                            // ————— the year, as paired strokes —————
                            if (flows.length >= 2) ...[
                              SectionHead(
                                'month by month',
                                trailing: Text(
                                  'tap a month to read it',
                                  style: LedgerType.bodyText.copyWith(
                                    fontSize: 11,
                                    color: c.inkFaint,
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _FlowStrokes(
                                    key: ValueKey('strokes-$_drawToken'),
                                    flows: flows.length > 12
                                        ? flows.sublist(flows.length - 12)
                                        : flows,
                                    highlighted: (m) =>
                                        !m.isBefore(start) && m.isBefore(end),
                                    onTap: _anchorOn,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      _legend(c, c.quill, 'in'),
                                      const SizedBox(width: Gap.x3),
                                      _legend(
                                        c,
                                        c.inkFaint.withValues(alpha: 0.45),
                                        'out',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                            // ————— where it came from —————
                            if (sources.isNotEmpty) ...[
                              SectionHead(
                                'where it came from',
                                trailing: Text(
                                  '${sources.length} '
                                  '${sources.length == 1 ? 'source' : 'sources'}',
                                  style: LedgerType.bodyText.copyWith(
                                    fontSize: 12,
                                    color: c.inkFaint,
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final (i, s) in sources.take(6).indexed)
                                    PlateRow(
                                      leading: Medallion(
                                        icon: LedgerIcons.resolve(
                                          cats[s.categoryId]?.icon,
                                        ),
                                        ink: i == 0 ? c.jama : c.inkFaint,
                                      ),
                                      title: s.name,
                                      sub: s.count == 1
                                          ? 'once'
                                          : '${s.count} times',
                                      amount: Inr.format(s.paise),
                                      amountSub: earned > 0
                                          ? Text(
                                              '${(s.paise * 100 / earned).round()}%',
                                              style: LedgerType.amount.copyWith(
                                                fontSize: 11,
                                                color: c.inkFaint,
                                              ),
                                            )
                                          : null,
                                    ),
                                  if (sources.length > 1)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: Gap.x2,
                                      ),
                                      child: _ShareStrip(
                                        key: ValueKey('share-$_drawToken'),
                                        parts: [
                                          for (final s in sources.take(6))
                                            s.paise,
                                        ],
                                        ink: c.jama,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            // ————— the lines —————
                            SectionHead(
                              'the lines',
                              trailing: lines.isEmpty
                                  ? null
                                  : Text(
                                      '${lines.length}',
                                      style: LedgerType.amount.copyWith(
                                        fontSize: 12,
                                        color: c.inkFaint,
                                      ),
                                    ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (lines.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: Gap.x2,
                                    ),
                                    child: Text(
                                      snap.hasData
                                          ? 'nothing came in ${_windowLabel(start, months, now).toLowerCase()}'
                                          : '',
                                      style: LedgerType.bodyText.copyWith(
                                        fontSize: 13,
                                        color: c.inkFaint,
                                      ),
                                    ),
                                  )
                                else
                                  for (final t in lines)
                                    PlateRow(
                                      key: ValueKey('income-${t.id}'),
                                      leading: Medallion(
                                        icon: LedgerIcons.resolve(
                                          cats[t.categoryId]?.icon,
                                        ),
                                        ink: c.jama,
                                        size: 32,
                                        iconSize: 15,
                                      ),
                                      title: t.title,
                                      sub:
                                          '${LedgerDates.ddMmm(t.at)}'
                                          '${cats[t.categoryId] == null ? '' : ' · ${cats[t.categoryId]!.name.toLowerCase()}'}',
                                      amount: Inr.format(
                                        t.amountPaise,
                                        signed: true,
                                      ),
                                      amountColor: c.jama,
                                      dense: true,
                                      onTap: () => showTxnEditor(context, t),
                                    ),
                              ],
                            ),
                            const SizedBox(height: Gap.x4),
                            Pressable(
                              key: const ValueKey('income-write'),
                              onTap: () => showIncomeSheet(context),
                              child: Row(
                                children: [
                                  Text(
                                    'write money in',
                                    style: LedgerType.bodyStrong.copyWith(
                                      fontSize: 14,
                                      color: c.quill,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  PenChevron(size: 12, color: c.quill),
                                ],
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
          },
        ),
      ),
    );
  }

  Widget _legend(LedgerColors c, Color ink, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 4,
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: LedgerType.bodyText.copyWith(fontSize: 11, color: c.inkFaint),
      ),
    ],
  );

  /// The page's own bar: a way back, the title, and the door to write.
  Widget _bar(LedgerColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x2),
      child: Row(
        children: [
          Pressable(
            onTap: () => Navigator.of(context).pop(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, Gap.x2, Gap.x3, Gap.x2),
              child: RotatedBox(
                quarterTurns: 2,
                child: PenChevron(size: 16, color: c.ink),
              ),
            ),
          ),
          Text(
            'Income',
            style: LedgerType.title.copyWith(fontSize: 24, color: c.ink),
          ),
        ],
      ),
    );
  }

  String _windowLabel(DateTime start, int months, DateTime now) {
    if (months == 1) {
      final sameYear = start.year == now.year;
      return LedgerDates.monthsFull[start.month - 1] +
          (sameYear ? '' : ' ${start.year}');
    }
    final last = DateTime(start.year, start.month + months - 1, 1);
    return '${LedgerDates.months[start.month - 1]} – '
        '${LedgerDates.months[last.month - 1]}'
        '${last.year == now.year ? '' : ' ${last.year}'}';
  }

  /// The salary's rhythm as a tile: when the next lands, and when the last
  /// did. The largest income line in the window is read as the salary —
  /// the book never asked for a label, and the biggest line is the pay.
  Widget _potFigure(
    LedgerColors c,
    String label,
    int paise, {
    bool signed = false,
  }) {
    final text = signed && paise < 0
        ? '−${Inr.compact(-paise)}'
        : Inr.compact(paise);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: LedgerType.label.copyWith(color: c.inkFaint)),
          const SizedBox(height: 1),
          Text(
            text,
            style: LedgerType.amount.copyWith(fontSize: 14, color: c.ink),
          ),
        ],
      ),
    );
  }

  Future<void> _assign(
    BuildContext context,
    List<Txn> window,
    List<Category> cats,
  ) {
    final pots = [
      for (final c in cats)
        if (c.kind == CategoryKind.income && !c.archived) c,
    ];
    final rows = [
      for (final t in window)
        if (t.type == TxnType.expense && t.sourceId == null) t,
    ]..sort((a, b) => b.at.compareTo(a.at));
    return showLedgerSheet<void>(
      context,
      builder: (_) => _AssignSheet(rows: rows, pots: pots),
    );
  }

  Widget _salaryTile(LedgerColors c, List<Txn> lines, DateTime now) {
    Txn? biggest;
    for (final t in lines) {
      if (biggest == null || t.amountPaise > biggest.amountPaise) biggest = t;
    }
    var next = DateTime(now.year, now.month, _salaryDay);
    final today = DateTime(now.year, now.month, now.day);
    if (!next.isAfter(today)) {
      next = DateTime(now.year, now.month + 1, _salaryDay);
    }
    final days = next.difference(today).inDays;
    return StatTile(
      label: 'next salary',
      value: days == 0
          ? 'to-day'
          : days == 1
          ? 'to-morrow'
          : '$days days',
      sub: biggest == null
          ? LedgerDates.ddMmm(next)
          : 'last ${LedgerDates.ddMmm(biggest.at)}',
    );
  }
}

/// Twelve months as paired strokes: money in beside money out, so the gap
/// between a pair is what was kept that month. The window on show is drawn
/// at full voice; the rest sit back. Strokes rise left to right as the
/// page draws itself, and a tap on a month reads that month.
class _FlowStrokes extends StatelessWidget {
  const _FlowStrokes({
    super.key,
    required this.flows,
    required this.highlighted,
    required this.onTap,
  });

  final List<MonthFlow> flows;
  final bool Function(DateTime month) highlighted;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final slot = box.maxWidth / flows.length;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final i = (d.localPosition.dx / slot).floor().clamp(
              0,
              flows.length - 1,
            );
            onTap(flows[i].month);
          },
          child: SizedBox(
            height: 110,
            width: double.infinity,
            child: DrawIn(
              duration: const Duration(milliseconds: 650),
              builder: (context, t) => CustomPaint(
                painter: _FlowPainter(
                  flows: flows,
                  highlighted: highlighted,
                  quill: c.quill,
                  faint: c.inkFaint,
                  rule: c.rule,
                  labelStyle: LedgerType.amount.copyWith(
                    fontSize: 9,
                    color: c.inkFaint,
                  ),
                  progress: t,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.flows,
    required this.highlighted,
    required this.quill,
    required this.faint,
    required this.rule,
    required this.labelStyle,
    required this.progress,
  });

  final List<MonthFlow> flows;
  final bool Function(DateTime) highlighted;
  final Color quill;
  final Color faint;
  final Color rule;
  final TextStyle labelStyle;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (flows.isEmpty) return;
    const labelH = 14.0;
    final base = size.height - labelH;
    var top = 0;
    for (final f in flows) {
      top = math.max(top, math.max(f.inPaise, f.outPaise));
    }
    if (top == 0) top = 1;
    final slot = size.width / flows.length;
    final stroke = math.min(7.0, slot * 0.24);
    for (final (i, f) in flows.indexed) {
      // Each pair rises on its own beat, left to right.
      final local = ((progress * flows.length) - i).clamp(0.0, 1.0);
      final rise = Curves.easeOutCubic.transform(local);
      final lit = highlighted(f.month);
      final cx = slot * i + slot / 2;
      final hIn = (base - 8) * (f.inPaise / top) * rise;
      final hOut = (base - 8) * (f.outPaise / top) * rise;
      // A faint track behind every pair, so an empty month is still a
      // month and not a gap.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - stroke * 1.5, 0, stroke * 3, base),
          Radius.circular(stroke),
        ),
        Paint()..color = rule.withValues(alpha: lit ? 0.55 : 0.28),
      );
      final inPaint = Paint()
        ..color = lit ? quill : quill.withValues(alpha: 0.38)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      final outPaint = Paint()
        ..color = lit
            ? faint.withValues(alpha: 0.7)
            : faint.withValues(alpha: 0.28)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      if (f.inPaise > 0) {
        canvas.drawLine(
          Offset(cx - stroke * 0.7, base - stroke / 2),
          Offset(cx - stroke * 0.7, base - math.max(hIn, stroke / 2)),
          inPaint,
        );
      }
      if (f.outPaise > 0) {
        canvas.drawLine(
          Offset(cx + stroke * 0.7, base - stroke / 2),
          Offset(cx + stroke * 0.7, base - math.max(hOut, stroke / 2)),
          outPaint,
        );
      }
      final label = f.month.month == 1
          ? "J'${f.month.year % 100}"
          : LedgerDates.months[f.month.month - 1].substring(0, 1);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: lit ? labelStyle.copyWith(color: quill) : labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, base + 3));
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.flows != flows || old.progress != progress;
}

/// One strip, each source's share laid end to end — the biggest in the
/// credit ink, the rest stepping down through it.
class _ShareStrip extends StatelessWidget {
  const _ShareStrip({super.key, required this.parts, required this.ink});

  final List<int> parts;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold(0, (s, p) => s + p);
    if (total <= 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: DrawIn(
        duration: const Duration(milliseconds: 500),
        builder: (context, t) => ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: t,
            child: SizedBox(
              height: 8,
              width: double.infinity,
              child: Row(
                children: [
                  for (final (i, p) in parts.indexed)
                    Expanded(
                      flex: math.max(1, (p * 1000 / total).round()),
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: i == parts.length - 1 ? 0 : 2,
                        ),
                        child: ColoredBox(
                          color: ink.withValues(
                            alpha: (1 - i * 0.18).clamp(0.25, 1.0),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The lines that never named a pot, settled one tap each — or all at
/// once, when the answer is the same for the lot.
class _AssignSheet extends ConsumerStatefulWidget {
  const _AssignSheet({required this.rows, required this.pots});

  final List<Txn> rows;
  final List<Category> pots;

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  late final List<Txn> _rows = [...widget.rows];

  Future<void> _settle(List<int> ids, int potId) async {
    HapticFeedback.selectionClick();
    await ref.read(txnRepoProvider).assignSource(ids, potId);
    if (!mounted) return;
    setState(() => _rows.removeWhere((t) => ids.contains(t.id)));
    if (_rows.isEmpty && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.8;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x4, Gap.page, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'which pot did these draw on?',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 16,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'tap a pot on a line, or settle the lot at once.',
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12.5,
                    color: c.inkFaint,
                  ),
                ),
                const SizedBox(height: Gap.x3),
                Row(
                  children: [
                    Text(
                      'all of them ·',
                      style: LedgerType.label.copyWith(color: c.inkFaint),
                    ),
                    const SizedBox(width: Gap.x2),
                    for (final p in widget.pots) ...[
                      QuillTab(
                        key: ValueKey('assign-all-${p.id}'),
                        p.name.toLowerCase(),
                        selected: false,
                        onTap: () =>
                            _settle([for (final t in _rows) t.id], p.id),
                      ),
                      const SizedBox(width: Gap.x2),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                Gap.page,
                Gap.x3,
                Gap.page,
                Gap.x6,
              ),
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final t = _rows[i];
                return Container(
                  key: ValueKey('assign-${t.id}'),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.rule)),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LedgerType.bodyStrong.copyWith(
                                fontSize: 14,
                                color: c.ink,
                              ),
                            ),
                          ),
                          Text(
                            Inr.format(t.amountPaise),
                            style: LedgerType.amount.copyWith(
                              fontSize: 14,
                              color: c.ink,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            LedgerDates.ddMmm(t.at),
                            style: LedgerType.label.copyWith(color: c.inkFaint),
                          ),
                          const SizedBox(width: Gap.x3),
                          for (final p in widget.pots) ...[
                            QuillTab(
                              key: ValueKey('assign-${t.id}-${p.id}'),
                              p.name.toLowerCase(),
                              selected: false,
                              onTap: () => _settle([t.id], p.id),
                            ),
                            const SizedBox(width: Gap.x2),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
