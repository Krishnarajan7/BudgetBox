import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/foods.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/plates.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/repos/diet_repo.dart';
import '../today/widgets/ledger_rows.dart';
import 'diet_math.dart';
import 'diet_setup.dart';
import 'food_sheet.dart';

/// The diet book: what was eaten, weighed against what a day should hold.
///
/// The page leads with the day's figure set against its line, the way the
/// money pages set spend against budget — one number, its target, and the
/// three macros as short strokes beneath. Then the day as a timeline of
/// sittings, each either written, skipped, or quietly asked about once its
/// hour has passed. Then the week's balance: a bar per nutrient the book
/// watches, grey while short, green when met, warning only for the two that
/// harm in excess — and never a red bar for a floor, because a bar that
/// scolds gets ignored (MacroFactor's "adherence-neutral" finding, borrowed
/// whole). Last, the few things worth saying, each with the dish that
/// answers it.
class DietPage extends ConsumerStatefulWidget {
  const DietPage({super.key});

  @override
  ConsumerState<DietPage> createState() => _DietPageState();
}

class _DietPageState extends ConsumerState<DietPage> {
  late final DateTime _today = _startOfToday();
  late DateTime _day = _today;

  DietProfile? _profile;
  bool _profileRead = false;
  FoodCatalogue? _catalogue;
  Map<String, List<MealEntry>> _byDay = const {};
  List<MealEntry> _eaten = const [];
  List<Txn> _foodSpend = const [];
  StreamSubscription<void>? _sub;

  /// Lines already on the page — only genuinely new ones ink in.
  final _seen = <String>{};
  bool _primed = false;

  static DateTime _startOfToday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool get _isToday => LedgerDates.dayKey(_day) == LedgerDates.dayKey(_today);
  String get _key => LedgerDates.dayKey(_day);

  @override
  void initState() {
    super.initState();
    final repo = ref.read(dietRepoProvider);
    repo.profile().then((p) {
      if (mounted) {
        setState(() {
          _profile = p;
          _profileRead = true;
        });
      }
    });
    FoodCatalogue.load().then((c) {
      if (mounted) setState(() => _catalogue = c);
    });
    _watch();
  }

  void _watch() {
    _sub?.cancel();
    _seen.clear();
    _primed = false;
    final repo = ref.read(dietRepoProvider);
    _sub = repo.watchSince(_day, days: 7).listen((byDay) {
      if (!mounted) return;
      setState(() => _byDay = byDay);
      _refreshSide();
    });
    _refreshSide();
  }

  Future<void> _refreshSide() async {
    final repo = ref.read(dietRepoProvider);
    final eaten = await repo.eatenRecently(_day, days: 14);
    final spend = await repo.foodSpend(_day);
    if (!mounted) return;
    setState(() {
      _eaten = eaten;
      _foodSpend = spend;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _turnDay(int delta) {
    final next = DateTime(_day.year, _day.month, _day.day + delta);
    if (next.isAfter(_today)) return;
    HapticFeedback.selectionClick();
    setState(() => _day = next);
    _watch();
  }

  Future<void> _setup() async {
    final p = await showDietSetup(context, existing: _profile);
    if (p != null && mounted) setState(() => _profile = p);
  }

  Future<void> _write({MealSlot? slot, String? query, MealEntry? legacy}) async {
    final cat = _catalogue;
    if (cat == null) return;
    final pick = await showFoodSheet(
      context,
      catalogue: cat,
      day: _day,
      slot: slot ?? legacy?.slot,
      query: query ?? legacy?.name,
      prefer: _profile?.kind,
    );
    if (pick == null || !mounted) return;
    final repo = ref.read(dietRepoProvider);
    if (legacy != null) {
      await repo.measure(legacy, pick.food, servings: pick.servings);
    } else {
      await repo.add(pick.food, day: _day, servings: pick.servings, slot: pick.slot);
    }
  }

  Future<void> _addSuggested(Suggestion s) async {
    final f = s.food;
    if (f == null) return;
    HapticFeedback.mediumImpact();
    await ref
        .read(dietRepoProvider)
        .add(f, day: _day, servings: s.servings, slot: s.slot);
  }

  Future<void> _skip(MealSlot slot) async {
    HapticFeedback.selectionClick();
    await ref.read(dietRepoProvider).skip(_day, slot);
  }

  Future<void> _strike(MealEntry e) async {
    HapticFeedback.mediumImpact();
    await ref.read(dietRepoProvider).remove(e);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final profile = _profile;
    final entries = _byDay[_key] ?? const <MealEntry>[];
    final now = DateTime.now();

    // Which lines are new since the page last drew.
    final ids = {for (final e in entries) 'm${e.mealId}-k${e.markId}'};
    final fresh = <String>{
      if (_primed)
        for (final id in ids)
          if (!_seen.contains(id)) id,
    };
    _primed = true;
    _seen.addAll(ids);

    return ModuleScaffold(
      title: 'Diet',
      trailing: profile == null
          ? null
          : Pressable(
              key: const ValueKey('diet-profile'),
              onTap: _setup,
              child: Text(
                '${profile.weightKg.round()} kg · ${profile.heightCm} cm',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
            ),
      child: !_profileRead
          ? const SizedBox.shrink()
          : profile == null
          ? _unopened(c)
          : _page(c, profile, entries, fresh, now),
    );
  }

  /// Before the six answers: one sentence and the door.
  Widget _unopened(LedgerColors c) {
    return EmptyPage(
      line: 'This book weighs what you eat.',
      sub:
          'Six answers set the day\'s targets — an Indian adult\'s, from '
          'ICMR-NIN — and every dish written after that is counted '
          'against them.',
      action: Pressable(
        key: const ValueKey('diet-open'),
        onTap: _setup,
        child: Text(
          'open the diet book ›',
          style: LedgerType.bodyStrong.copyWith(fontSize: 14, color: c.quill),
        ),
      ),
    );
  }

  Widget _page(
    LedgerColors c,
    DietProfile profile,
    List<MealEntry> entries,
    Set<String> fresh,
    DateTime now,
  ) {
    final targets = targetsFor(profile);
    final totals = totalsFor(_key, entries);
    final kcalT = targetOf(targets, Nutrient.kcal);
    final proT = targetOf(targets, Nutrient.protein);
    final week = [
      for (var i = 6; i >= 0; i--)
        () {
          final d = DateTime(_day.year, _day.month, _day.day - i);
          final k = LedgerDates.dayKey(d);
          return totalsFor(k, _byDay[k] ?? const []);
        }(),
    ];
    final readings = weekReadings(week, targets);
    final cat = _catalogue;
    final says = cat == null
        ? const <Suggestion>[]
        : suggestions(
            profile: profile,
            targets: targets,
            history: week,
            eaten: _eaten,
            catalogue: cat,
            now: _isToday ? now : DateTime(_day.year, _day.month, _day.day, 23),
          );

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Gap.page,
        Gap.x3,
        Gap.page,
        MediaQuery.paddingOf(context).bottom + Gap.x8,
      ),
      children: [
        _dayNav(c),
        const SizedBox(height: Gap.x4),
        // ————— the figure: the day's energy as a ring, its macros as
        // the ring's segments, the target as the track —————
        Plate(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Row(
            children: [
              Donut(
                key: ValueKey('donut-$_key'),
                size: 132,
                thickness: 13,
                total: kcalT.rda,
                segments: [
                  (totals.nutrients.protein * 4, c.chartInks[0]),
                  (totals.nutrients[Nutrient.carbs] * 4, c.chartInks[1]),
                  (totals.nutrients[Nutrient.fat] * 9, c.chartInks[2]),
                ],
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isToday ? 'eaten so far' : 'eaten that day',
                      style: LedgerType.label.copyWith(
                        fontSize: 9.5,
                        color: c.inkFaint,
                      ),
                    ),
                    CountUp(
                      value: totals.nutrients.kcal.round(),
                      format: (n) => _group(n),
                      style: LedgerType.amountTotal.copyWith(
                        fontSize: 24,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      'of ${_group(kcalT.rda.round())} kcal',
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 10.5,
                        color: c.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Macro(
                      label: 'protein',
                      value: totals.nutrients.protein,
                      target: proT.rda,
                      unit: 'g',
                      ink: c.chartInks[0],
                    ),
                    const SizedBox(height: Gap.x3),
                    _Macro(
                      label: 'carbs',
                      value: totals.nutrients[Nutrient.carbs],
                      target: targetOf(targets, Nutrient.carbs).rda,
                      unit: 'g',
                      ink: c.chartInks[1],
                    ),
                    const SizedBox(height: Gap.x3),
                    _Macro(
                      label: 'fat',
                      value: totals.nutrients[Nutrient.fat],
                      target: targetOf(targets, Nutrient.fat).rda,
                      unit: 'g',
                      ink: c.chartInks[2],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (totals.unmeasured > 0)
          Padding(
            padding: const EdgeInsets.only(top: Gap.x2),
            child: Text(
              totals.unmeasured == 1
                  ? 'and one line the book couldn\'t weigh — tap it to'
                  : 'and ${totals.unmeasured} lines the book couldn\'t weigh — tap one to',
              style: LedgerType.bodyText.copyWith(
                fontSize: 12,
                color: c.inkFaint,
              ),
            ),
          ),
        // ————— the day, sitting by sitting —————
        const SectionHead('the day'),
        for (final (i, slot) in MealSlot.values.indexed)
          Plate(
            key: ValueKey('sitting-${slot.name}'),
            margin: EdgeInsets.only(top: i == 0 ? 0 : Gap.x3),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _sitting(c, slot, entries, totals, fresh, now),
            ),
          ),
        // ————— the week —————
        const SectionHead('the week'),
        Plate(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
        _WeekStrokes(
          key: ValueKey('week-$_key'),
          days: week,
          target: kcalT.rda,
          proteinTarget: proT.rda,
          ink: c.quill,
          faint: c.inkFaint,
          rule: c.rule,
          met: c.jama,
          labelStyle: LedgerType.amount.copyWith(fontSize: 9, color: c.inkFaint),
        ),
        const SizedBox(height: 4),
        Text(
          _weekLine(week, kcalT.rda),
          style: LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint),
        ),
            ],
          ),
        ),
        // ————— the balance —————
        SectionHead(
          'the balance',
          trailing: Text(
            readings.first.daysCounted == 0
                ? ''
                : 'over ${readings.first.daysCounted} '
                      '${readings.first.daysCounted == 1 ? 'day' : 'days'}',
            style: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
          ),
        ),
        Plate(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          child: readings.first.daysCounted == 0
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'write a measured dish and the week\'s lines begin',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 13,
                      color: c.inkFaint,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, r) in readings.indexed)
                      _NutrientBar(
                        key: ValueKey('bar-${r.nutrient.name}-$_key'),
                        reading: r,
                        stagger: i,
                        onTap: () => _contributors(r),
                      ),
                  ],
                ),
        ),
        // ————— worth saying —————
        if (says.isNotEmpty) ...[
          const SectionHead('worth saying'),
          Plate(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, s) in says.take(4).indexed)
                  _SuggestionLine(
                    suggestion: s,
                    last: i == math.min(says.length, 4) - 1,
                    onAdd: s.food == null ? null : () => _addSuggested(s),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Gap.x4),
        Pressable(
          key: const ValueKey('diet-write'),
          onTap: () => _write(),
          child: Row(
            children: [
              Text(
                'write a dish',
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
  }

  Widget _dayNav(LedgerColors c) {
    final label = _isToday
        ? 'to-day'
        : LedgerDates.dayKey(_day) ==
              LedgerDates.dayKey(_today.subtract(const Duration(days: 1)))
        ? 'yesterday'
        : LedgerDates.dayLabel(_day).toLowerCase();
    return Row(
      children: [
        Pressable(
          onTap: () => _turnDay(-1),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: RotatedBox(
              quarterTurns: 1,
              child: PenChevron(size: 15, color: c.inkFaint),
            ),
          ),
        ),
        const SizedBox(width: Gap.x1),
        Text(
          label,
          style: LedgerType.bodyStrong.copyWith(fontSize: 14, color: c.ink),
        ),
        const SizedBox(width: Gap.x1),
        Pressable(
          onTap: _isToday ? null : () => _turnDay(1),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: RotatedBox(
              quarterTurns: 3,
              child: PenChevron(size: 15, color: _isToday ? c.rule : c.inkFaint),
            ),
          ),
        ),
        const Spacer(),
        if (!_isToday)
          Pressable(
            onTap: () {
              setState(() => _day = _today);
              _watch();
            },
            child: Text(
              'back to now',
              style: LedgerType.bodyStrong.copyWith(fontSize: 12, color: c.quill),
            ),
          ),
      ],
    );
  }

  /// One sitting: its name and the lines under it, or the honest state of
  /// an empty one — a quiet door before its hour, a question after.
  List<Widget> _sitting(
    LedgerColors c,
    MealSlot slot,
    List<MealEntry> entries,
    DayTotals totals,
    Set<String> fresh,
    DateTime now,
  ) {
    final lines = [
      for (final e in entries)
        if (e.slot == slot && !e.skipped) e,
    ];
    final skipped = totals.slotsSkipped.contains(slot);
    final deadline = slotDeadline(slot, _day);
    final past = _isToday ? now.isAfter(deadline) : true;
    final slotKcal = lines.fold(0.0, (s, e) => s + (e.facts?.kcal ?? 0));
    // A food expense inside this sitting's window with nothing written
    // against it: the ledger's cue, said once.
    Txn? cue;
    if (lines.isEmpty && !skipped) {
      for (final t in _foodSpend) {
        if (slotFor(t.at) == slot) cue = t;
      }
    }
    final faint = LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint);
    final slotInk = c.chartInks[slot.index % c.chartInks.length];
    final slotIcon = switch (slot) {
      MealSlot.breakfast => Icons.free_breakfast_outlined,
      MealSlot.lunch => Icons.lunch_dining_outlined,
      MealSlot.snack => Icons.cookie_outlined,
      MealSlot.dinner => Icons.dinner_dining_outlined,
    };
    return [
      PlateHead(
        slotName(slot),
        trailing: slotKcal > 0
            ? Text(
                '${slotKcal.round()} kcal',
                style: LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
              )
            : null,
      ),
      for (final e in lines)
        InkIn(
          key: ValueKey('meal-ink-m${e.mealId}-k${e.markId}'),
          play: fresh.contains('m${e.mealId}-k${e.markId}'),
          child: PlateRow(
            key: ValueKey('meal-m${e.mealId}-k${e.markId}'),
            leading: Medallion(
              icon: slotIcon,
              ink: e.measured ? slotInk : c.inkFaint,
              size: 34,
              iconSize: 16,
            ),
            title: e.measured ? '${e.name} · ${_servingsLabel(e)}' : e.name,
            sub: e.measured
                ? '${_hhmm(e.at)} · ${e.facts!.protein.round()} g protein'
                : '${_hhmm(e.at)} · unweighed, tap to weigh',
            amount: e.measured ? '${e.facts!.kcal.round()} kcal' : null,
            amountColor: e.measured ? c.ink : null,
            dense: true,
            onTap: e.measured
                ? () => _resize(e)
                : () => _write(legacy: e.legacy ? e : null, query: e.name, slot: e.slot),
            onLongPress: () => _strike(e),
          ),
        ),
      if (lines.isEmpty)
        if (skipped)
          Row(
            children: [
              Text('skipped, on purpose', style: faint),
              const Spacer(),
              Pressable(
                haptic: false,
                onTap: () {
                  final row = entries.firstWhere(
                    (e) => e.slot == slot && e.skipped,
                  );
                  _strike(row);
                },
                child: Text(
                  'undo',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 12,
                    color: c.quill,
                  ),
                ),
              ),
            ],
          )
        else if (cue != null)
          Pressable(
            key: ValueKey('cue-${slot.name}'),
            haptic: false,
            onTap: () => _write(slot: slot),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${Inr.format(cue.amountPaise)} at ${cue.title}, '
                        '${_hhmm(cue.at)} — nothing written. ',
                    style: faint,
                  ),
                  TextSpan(
                    text: 'what was it?',
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 12,
                      color: c.quill,
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (past && mainSlots.contains(slot))
          Row(
            children: [
              Text('nothing written', style: faint),
              const Spacer(),
              Pressable(
                key: ValueKey('write-${slot.name}'),
                haptic: false,
                onTap: () => _write(slot: slot),
                child: Text(
                  'write it',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 12,
                    color: c.quill,
                  ),
                ),
              ),
              const SizedBox(width: Gap.x4),
              Pressable(
                key: ValueKey('skip-${slot.name}'),
                haptic: false,
                onTap: () => _skip(slot),
                child: Text(
                  'skipped it',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 12,
                    color: c.inkFaint,
                  ),
                ),
              ),
            ],
          )
        else
          Pressable(
            key: ValueKey('add-${slot.name}'),
            haptic: false,
            onTap: () => _write(slot: slot),
            child: Row(
              children: [
                PenPlus(size: 10, color: c.inkFaint),
                const SizedBox(width: 6),
                Text('add ${slotName(slot)}', style: faint),
              ],
            ),
          ),
    ];
  }

  Future<void> _resize(MealEntry e) async {
    final cat = _catalogue;
    final key = e.foodKey;
    if (cat == null || key == null) return;
    final food = cat.byKey(key);
    if (food == null) return;
    final pick = await showFoodSheet(
      context,
      catalogue: cat,
      day: _day,
      slot: e.slot,
      preselected: food,
      prefer: _profile?.kind,
    );
    if (pick == null || !mounted) return;
    await ref.read(dietRepoProvider).resize(e, pick.food, pick.servings);
  }

  /// What carried this nutrient over the week — his own dishes, ranked.
  Future<void> _contributors(NutrientReading r) async {
    final cat = _catalogue;
    if (cat == null) return;
    final by = <String, ({FoodItem food, double total, int times})>{};
    for (final e in _eaten) {
      final k = e.foodKey;
      final f = e.facts;
      if (k == null || f == null) continue;
      final food = cat.byKey(k);
      if (food == null) continue;
      final cur = by[k];
      by[k] = (
        food: food,
        total: (cur?.total ?? 0) + f[r.nutrient],
        times: (cur?.times ?? 0) + 1,
      );
    }
    final ranked = by.values.toList()..sort((a, b) => b.total.compareTo(a.total));
    HapticFeedback.selectionClick();
    await showLedgerSheet<void>(
      context,
      scrollControlled: false,
      builder: (context) {
        final c = LedgerColors.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.x2),
              Text(
                r.nutrient.label,
                style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
              ),
              const SizedBox(height: 2),
              Text(
                r.target.isCeiling
                    ? '${_fmt(r.mean, r.nutrient)} a day against a ceiling of '
                          '${_fmt(r.target.max!, r.nutrient)}'
                    : '${_fmt(r.mean, r.nutrient)} a day · '
                          '${_fmt(r.target.ear, r.nutrient)} is enough, '
                          '${_fmt(r.target.rda, r.nutrient)} is comfortable',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
              const SectionHead('where it came from'),
              if (ranked.isEmpty)
                Text(
                  'nothing measured carries it yet',
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 13,
                    color: c.inkFaint,
                  ),
                )
              else
                for (final e in ranked.take(5))
                  LeaderRow(
                    label: e.food.name,
                    detail: e.times == 1 ? 'once' : '${e.times} times',
                    amount: _fmt(e.total, r.nutrient),
                    amountColor: c.ink,
                  ),
            ],
          ),
        );
      },
    );
  }

  static String _fmt(double v, Nutrient n) {
    if (n == Nutrient.kcal) return '${v.round()} kcal';
    final s = v >= 10 ? v.round().toString() : v.toStringAsFixed(1);
    return '$s ${n.unit}';
  }

  static String _servingsLabel(MealEntry e) {
    if (e.grams case final g?) return '${g.round()} g';
    final s = e.servings;
    if (s == 1) return '1';
    if (s == 0.5) return '½';
    if (s == 1.5) return '1½';
    if (s == s.roundToDouble()) return '×${s.round()}';
    return '×${s.toStringAsFixed(1)}';
  }

  static String _hhmm(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')}${t.hour < 12 ? 'a' : 'p'}';
  }

  static String _group(int n) => Inr.format(n * 100).substring(1);

  String _weekLine(List<DayTotals> week, double target) {
    final written = [for (final d in week) if (d.measured > 0) d];
    if (written.isEmpty) return 'no measured days this week yet';
    final mean = written.fold(0.0, (s, d) => s + d.nutrients.kcal) / written.length;
    final missed = week.fold(0, (s, d) => s + (d.isEmpty ? 0 : d.missing.length));
    final parts = [
      '${_group(mean.round())} kcal a day across ${written.length} '
          '${written.length == 1 ? 'measured day' : 'measured days'}',
      if (missed > 0) '$missed ${missed == 1 ? 'sitting' : 'sittings'} went unwritten',
    ];
    return parts.join(' · ');
  }
}

/// One macro beside the ring: its ink, its label, the figure against the
/// target, and a capped bar filling toward it.
class _Macro extends StatelessWidget {
  const _Macro({
    required this.label,
    required this.value,
    required this.target,
    required this.unit,
    required this.ink,
  });

  final String label;
  final double value;
  final double target;
  final String unit;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final f = target == 0 ? 0.0 : value / target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: LedgerType.label.copyWith(fontSize: 11, color: c.inkFaint),
            ),
            const Spacer(),
            CountUp(
              value: value.round(),
              format: (n) => '$n',
              style: LedgerType.amountTotal.copyWith(fontSize: 15, color: c.ink),
              duration: const Duration(milliseconds: 400),
            ),
            Text(
              ' / ${target.round()} $unit',
              style: LedgerType.amount.copyWith(fontSize: 10.5, color: c.inkFaint),
            ),
          ],
        ),
        const SizedBox(height: 5),
        RoundedBar(fraction: f.clamp(0.0, 1.0), ink: ink, height: 5),
      ],
    );
  }
}

/// Seven days as strokes against the target line: energy as the stroke's
/// height, a small tick at the top when protein was met, a gap where
/// nothing was written. To-day sits last, at full voice.
class _WeekStrokes extends StatelessWidget {
  const _WeekStrokes({
    super.key,
    required this.days,
    required this.target,
    required this.proteinTarget,
    required this.ink,
    required this.faint,
    required this.rule,
    required this.met,
    required this.labelStyle,
  });

  final List<DayTotals> days;
  final double target;
  final double proteinTarget;
  final Color ink;
  final Color faint;
  final Color rule;
  final Color met;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      width: double.infinity,
      child: DrawIn(
        duration: const Duration(milliseconds: 600),
        builder: (context, t) => CustomPaint(
          painter: _WeekPainter(
            days: days,
            target: target,
            proteinTarget: proteinTarget,
            ink: ink,
            faint: faint,
            rule: rule,
            met: met,
            labelStyle: labelStyle,
            progress: t,
          ),
        ),
      ),
    );
  }
}

class _WeekPainter extends CustomPainter {
  _WeekPainter({
    required this.days,
    required this.target,
    required this.proteinTarget,
    required this.ink,
    required this.faint,
    required this.rule,
    required this.met,
    required this.labelStyle,
    required this.progress,
  });

  final List<DayTotals> days;
  final double target;
  final double proteinTarget;
  final Color ink;
  final Color faint;
  final Color rule;
  final Color met;
  final TextStyle labelStyle;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    const labelH = 14.0;
    final base = size.height - labelH;
    final top = math.max(target * 1.3, days.fold(0.0, (m, d) => math.max(m, d.nutrients.kcal)));
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = rule
        ..strokeWidth = 1,
    );
    // The target, ruled faintly across the week.
    final ty = base - (base - 6) * (target / top);
    var x = 0.0;
    final dash = Paint()
      ..color = faint.withValues(alpha: 0.45 * progress)
      ..strokeWidth = 1;
    while (x < size.width) {
      canvas.drawLine(Offset(x, ty), Offset(math.min(x + 3, size.width), ty), dash);
      x += 7;
    }
    final slot = size.width / days.length;
    final stroke = math.min(10.0, slot * 0.3);
    for (final (i, d) in days.indexed) {
      final local = ((progress * days.length) - i).clamp(0.0, 1.0);
      final rise = Curves.easeOutCubic.transform(local);
      final cx = slot * i + slot / 2;
      final last = i == days.length - 1;
      if (d.measured > 0) {
        final h = (base - 6) * (d.nutrients.kcal / top) * rise;
        canvas.drawLine(
          Offset(cx, base),
          Offset(cx, base - math.max(h, 2)),
          Paint()
            ..color = last ? ink : ink.withValues(alpha: 0.55)
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round,
        );
        if (d.nutrients.protein >= proteinTarget && rise >= 1) {
          canvas.drawCircle(Offset(cx, base - h - 8), 2.2, Paint()..color = met);
        }
      } else if (!d.isEmpty) {
        // Written but unweighed: a hollow tick.
        canvas.drawCircle(
          Offset(cx, base - 5),
          2.5,
          Paint()
            ..color = faint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      } else {
        canvas.drawLine(
          Offset(cx - 3, base),
          Offset(cx + 3, base),
          Paint()
            ..color = rule
            ..strokeWidth = 2,
        );
      }
      final date = DateTime.parse(d.date);
      final tp = TextPainter(
        text: TextSpan(
          text: LedgerDates.weekdays[date.weekday - 1].substring(0, 1),
          style: last ? labelStyle.copyWith(color: ink) : labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, base + 3));
    }
  }

  @override
  bool shouldRepaint(_WeekPainter old) =>
      old.days != days || old.progress != progress;
}

/// One nutrient's week as a bar: grey while short of the floor, the credit
/// ink once the floor is reached, warning ink only past a ceiling. Never a
/// red bar for a floor — that reads as failure and gets ignored.
class _NutrientBar extends StatelessWidget {
  const _NutrientBar({
    super.key,
    required this.reading,
    required this.stagger,
    required this.onTap,
  });

  final NutrientReading reading;
  final int stagger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final r = reading;
    final color = switch (r.state) {
      ReadingState.over => c.warn,
      ReadingState.met || ReadingState.fine => c.jama,
      ReadingState.short => c.inkFaint,
      ReadingState.unknown => c.rule,
    };
    final line = r.target.isCeiling ? r.target.max! : r.target.rda;
    final said = r.target.isCeiling
        ? '${_DietPageState._fmt(r.mean, r.nutrient)} of ${_DietPageState._fmt(line, r.nutrient)} ceiling'
        : '${_DietPageState._fmt(r.mean, r.nutrient)} of ${_DietPageState._fmt(line, r.nutrient)}';
    final tail = switch (r.state) {
      ReadingState.short => r.daysShort == r.daysCounted
          ? ' · short every day'
          : ' · short ${r.daysShort} of ${r.daysCounted}',
      ReadingState.over => ' · over ${r.daysOver} of ${r.daysCounted}',
      _ => '',
    };
    return Pressable(
      key: ValueKey('nutrient-${r.nutrient.name}'),
      haptic: false,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: Gap.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  r.nutrient.label,
                  style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.ink),
                ),
                const Spacer(),
                Text(
                  '$said$tail',
                  style: LedgerType.amount.copyWith(fontSize: 11, color: c.inkFaint),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 4,
              width: double.infinity,
              child: DrawIn(
                duration: Duration(milliseconds: 450 + 40 * stagger),
                builder: (context, t) => CustomPaint(
                  painter: _BarPainter(
                    fraction: r.fraction * t,
                    ear: r.target.isCeiling ? null : r.target.ear / line,
                    color: color,
                    rule: c.rule,
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

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.fraction,
    required this.ear,
    required this.color,
    required this.rule,
  });

  final double fraction;

  /// Where the floor sits as a share of the comfortable line — a tick.
  final double? ear;
  final Color color;
  final Color rule;

  @override
  void paint(Canvas canvas, Size size) {
    const scale = 1.3;
    final y = size.height / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = rule
        ..strokeWidth = size.height,
    );
    final w = (size.width * (fraction / scale)).clamp(0.0, size.width);
    if (w > 0) {
      canvas.drawLine(
        Offset(0, y),
        Offset(w, y),
        Paint()
          ..color = color
          ..strokeWidth = size.height,
      );
    }
    final lineX = size.width / scale;
    canvas.drawLine(
      Offset(lineX, y - size.height),
      Offset(lineX, y + size.height),
      Paint()
        ..color = rule
        ..strokeWidth = 1.5,
    );
    if (ear case final e?) {
      final ex = size.width * (e / scale);
      canvas.drawLine(
        Offset(ex, y - size.height * 0.6),
        Offset(ex, y + size.height * 0.6),
        Paint()
          ..color = rule
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fraction != fraction || old.color != color;
}

/// One thing worth saying, and the dish that answers it.
class _SuggestionLine extends StatelessWidget {
  const _SuggestionLine({
    required this.suggestion,
    required this.last,
    this.onAdd,
  });

  final Suggestion suggestion;
  final bool last;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final s = suggestion;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Gap.x3),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.title,
            style: LedgerType.bodyStrong.copyWith(fontSize: 14, color: c.ink),
          ),
          const SizedBox(height: 2),
          Text(
            s.body,
            style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
          ),
          if (onAdd != null && s.food != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.x2),
              child: Pressable(
                key: ValueKey('say-add-${s.food!.key}'),
                onTap: onAdd,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'write ${s.food!.spokenServing(s.servings)}'
                      '${s.slot == null ? '' : ' at ${slotName(s.slot!)}'}',
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 13,
                        color: c.quill,
                      ),
                    ),
                    const SizedBox(width: 4),
                    PenChevron(size: 11, color: c.quill),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
