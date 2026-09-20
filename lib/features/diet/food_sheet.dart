import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/foods.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/repos/diet_repo.dart';
import '../today/widgets/ledger_rows.dart';
import 'diet_math.dart';

/// What the sheet hands back: the dish, how much of it, and which sitting.
typedef FoodPick = ({FoodItem food, double servings, MealSlot slot});

/// Find a dish and say how much. Opens on the search; the quick row shows
/// what he eats most so the tenth idli is one tap. Pre-seed [query] to
/// weigh an old words-only line, and [slot] to write into a sitting.
Future<FoodPick?> showFoodSheet(
  BuildContext context, {
  required FoodCatalogue catalogue,
  required DateTime day,
  String? query,
  MealSlot? slot,
  FoodKind? prefer,
  FoodItem? preselected,
}) {
  return showLedgerSheet<FoodPick>(
    context,
    builder: (_) => _FoodSheet(
      catalogue: catalogue,
      day: day,
      query: query,
      slot: slot,
      prefer: prefer,
      preselected: preselected,
    ),
  );
}

class _FoodSheet extends ConsumerStatefulWidget {
  const _FoodSheet({
    required this.catalogue,
    required this.day,
    this.query,
    this.slot,
    this.prefer,
    this.preselected,
  });

  final FoodCatalogue catalogue;
  final DateTime day;
  final String? query;
  final MealSlot? slot;
  final FoodKind? prefer;
  final FoodItem? preselected;

  @override
  ConsumerState<_FoodSheet> createState() => _FoodSheetState();
}

class _FoodSheetState extends ConsumerState<_FoodSheet> {
  late final _ctl = TextEditingController(text: widget.query ?? '');
  late String _q = widget.query ?? '';
  late FoodItem? _picked = widget.preselected;
  double _servings = 1;
  late MealSlot _slot = widget.slot ?? slotFor(DateTime.now());
  List<FoodItem> _frequent = const [];

  static const _steps = [0.5, 1.0, 1.5, 2.0, 3.0];

  @override
  void initState() {
    super.initState();
    ref.read(dietRepoProvider).frequent(widget.catalogue).then((f) {
      if (mounted) setState(() => _frequent = f);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _pick(FoodItem f) {
    HapticFeedback.selectionClick();
    setState(() => _picked = f);
  }

  void _commit() {
    final f = _picked;
    if (f == null) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop((food: f, servings: _servings, slot: _slot));
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final results = widget.catalogue.search(_q, prefer: widget.prefer);
    final picked = _picked;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x2, Gap.page, 0),
              child: Row(
                children: [
                  PenSearch(size: 16, color: c.inkFaint),
                  const SizedBox(width: Gap.x2),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('food-search'),
                      controller: _ctl,
                      autofocus: picked == null,
                      onChanged: (v) => setState(() {
                        _q = v;
                        if (_picked != null) _picked = null;
                      }),
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 16,
                        color: c.ink,
                      ),
                      cursorColor: c.quill,
                      decoration: InputDecoration(
                        hintText: 'idli, chai, biryani…',
                        hintStyle: LedgerType.bodyText.copyWith(
                          fontSize: 16,
                          color: c.inkFaint,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_q.isNotEmpty)
                    Pressable(
                      haptic: false,
                      onTap: () {
                        _ctl.clear();
                        setState(() {
                          _q = '';
                          _picked = null;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: PenCross(size: 11, color: c.inkFaint),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: Gap.page),
              color: c.rule,
            ),
            Expanded(
              child: picked != null
                  ? _portion(c, picked)
                  : _q.isEmpty
                  ? _quickRow(c)
                  : _results(c, results),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickRow(LedgerColors c) {
    if (_frequent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Gap.page),
        child: Text(
          'type a dish — the ones you write most will gather here',
          style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x2, Gap.page, Gap.x6),
      children: [
        const SectionHead('what you eat most'),
        for (final (i, f) in _frequent.indexed)
          _foodRow(c, f, last: i == _frequent.length - 1),
      ],
    );
  }

  Widget _results(LedgerColors c, List<FoodItem> results) {
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Gap.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'the book has no "$_q" to weigh',
              style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
            ),
            const SizedBox(height: Gap.x3),
            Pressable(
              key: const ValueKey('food-keep-words'),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop();
                ref
                    .read(dietRepoProvider)
                    .addUnmeasured(_q, day: widget.day, slot: _slot);
              },
              child: Row(
                children: [
                  Text(
                    'keep it as words',
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
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x2, Gap.page, Gap.x6),
      children: [
        for (final (i, f) in results.indexed)
          _foodRow(c, f, last: i == results.length - 1),
      ],
    );
  }

  Widget _foodRow(LedgerColors c, FoodItem f, {required bool last}) {
    final one = f.forServings(1);
    return Pressable(
      key: ValueKey('food-${f.key}'),
      onTap: () => _pick(f),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.rule)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LedgerType.bodyText.copyWith(color: c.ink),
                  ),
                  Text(
                    [
                      'a ${f.unit.isEmpty ? 'serving' : f.unit} · ${f.servingGrams.round()} g',
                      if (f.kind != FoodKind.veg)
                        f.kind == FoodKind.egg ? 'egg' : 'non-veg',
                    ].join(' · '),
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 11,
                      color: c.inkFaint,
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
                  '${one.kcal.round()} kcal',
                  style: LedgerType.amount.copyWith(color: c.ink),
                ),
                Text(
                  '${one.protein.round()} g protein',
                  style: LedgerType.amount.copyWith(
                    fontSize: 11,
                    color: c.inkFaint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// How much, and which sitting — then the stamp.
  Widget _portion(LedgerColors c, FoodItem f) {
    final facts = f.forServings(_servings);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x4, Gap.page, Gap.x6),
      children: [
        Text(
          f.name,
          style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
        ),
        const SizedBox(height: 2),
        Text(
          f.spokenServing(_servings),
          style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
        ),
        const SizedBox(height: Gap.x4),
        Row(
          children: [
            for (final s in _steps) ...[
              QuillTab(
                s == 0.5
                    ? '½'
                    : s == 1.5
                    ? '1½'
                    : '${s.round()}',
                selected: _servings == s,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _servings = s);
                },
              ),
              const SizedBox(width: Gap.x4),
            ],
            const Spacer(),
            Text(
              '${(f.servingGrams * _servings).round()} g',
              style: LedgerType.amount.copyWith(
                fontSize: 12,
                color: c.inkFaint,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.x4),
        // The figures settle as the portion changes — never snap.
        Row(
          children: [
            _figure(c, facts.kcal, 'kcal'),
            const SizedBox(width: Gap.x6),
            _figure(c, facts.protein, 'g protein'),
            const SizedBox(width: Gap.x6),
            _figure(c, facts[Nutrient.carbs], 'g carbs'),
            const SizedBox(width: Gap.x6),
            _figure(c, facts[Nutrient.fat], 'g fat'),
          ],
        ),
        const SizedBox(height: Gap.x2),
        Text(
          [
            'fibre ${facts[Nutrient.fibre].toStringAsFixed(1)} g',
            'iron ${facts[Nutrient.iron].toStringAsFixed(1)} mg',
            'calcium ${facts[Nutrient.calcium].round()} mg',
            'sodium ${facts[Nutrient.sodium].round()} mg',
          ].join(' · '),
          style: LedgerType.bodyText.copyWith(fontSize: 11, color: c.inkFaint),
        ),
        const SectionHead('which sitting'),
        Row(
          children: [
            for (final s in MealSlot.values) ...[
              QuillTab(
                slotName(s),
                selected: _slot == s,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _slot = s);
                },
              ),
              const SizedBox(width: Gap.x4),
            ],
          ],
        ),
        const SizedBox(height: Gap.x6),
        Pressable(
          key: const ValueKey('food-stamp'),
          onTap: _commit,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: c.quill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'write it',
              textAlign: TextAlign.center,
              style: LedgerType.bodyStrong.copyWith(
                fontSize: 15,
                color: c.paper,
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.x3),
        Pressable(
          haptic: false,
          onTap: () => setState(() => _picked = null),
          child: Text(
            '‹ a different dish',
            style: LedgerType.bodyStrong.copyWith(
              fontSize: 13,
              color: c.inkFaint,
            ),
          ),
        ),
      ],
    );
  }

  Widget _figure(LedgerColors c, double v, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CountUp(
          value: v.round(),
          format: (n) => '$n',
          style: LedgerType.amountTotal.copyWith(fontSize: 22, color: c.ink),
          duration: const Duration(milliseconds: 350),
        ),
        Text(
          unit,
          style: LedgerType.bodyText.copyWith(fontSize: 11, color: c.inkFaint),
        ),
      ],
    );
  }
}
