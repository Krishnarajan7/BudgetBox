import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/foods.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/sheets.dart';
import '../../data/providers.dart';
import '../../data/repos/diet_repo.dart';
import '../today/widgets/ledger_rows.dart';
import 'diet_math.dart';

/// The diet book's one setup: six plain answers, and the targets fall out
/// of them. Opens pre-filled when there is a profile to edit.
Future<DietProfile?> showDietSetup(BuildContext context, {DietProfile? existing}) {
  return showLedgerSheet<DietProfile>(
    context,
    builder: (_) => _SetupSheet(existing: existing),
  );
}

class _SetupSheet extends ConsumerStatefulWidget {
  const _SetupSheet({this.existing});

  final DietProfile? existing;

  @override
  ConsumerState<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends ConsumerState<_SetupSheet> {
  late final _height = TextEditingController(
    text: widget.existing == null ? '' : '${widget.existing!.heightCm}',
  );
  late final _weight = TextEditingController(
    text: widget.existing == null ? '' : _trim(widget.existing!.weightKg),
  );
  late final _age = TextEditingController(
    text: widget.existing == null
        ? ''
        : '${widget.existing!.ageOn(DateTime.now())}',
  );
  late ActivityLevel _activity = widget.existing?.activity ?? ActivityLevel.sedentary;
  late DietGoal _goal = widget.existing?.goal ?? DietGoal.maintain;
  late FoodKind _kind = widget.existing?.kind ?? FoodKind.nonveg;

  static String _trim(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _age.dispose();
    super.dispose();
  }

  DietProfile? get _draft {
    final h = int.tryParse(_height.text.trim());
    final w = double.tryParse(_weight.text.trim());
    final a = int.tryParse(_age.text.trim());
    if (h == null || w == null || a == null) return null;
    if (h < 120 || h > 230 || w < 30 || w > 250 || a < 10 || a > 100) {
      return null;
    }
    return DietProfile(
      heightCm: h,
      weightKg: w,
      bornYear: DateTime.now().year - a,
      activity: _activity,
      goal: _goal,
      kind: _kind,
    );
  }

  Future<void> _save() async {
    final p = _draft;
    if (p == null) return;
    HapticFeedback.mediumImpact();
    await ref.read(dietRepoProvider).setProfile(p);
    if (!mounted) return;
    // The reminders exist only once there are targets to speak about.
    await ref.read(nudgesProvider).resync();
    if (!mounted) return;
    Navigator.of(context).pop(p);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final draft = _draft;
    final targets = draft == null ? null : targetsFor(draft);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.page,
        0,
        Gap.page,
        MediaQuery.viewInsetsOf(context).bottom + Gap.x6,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x2),
            Text(
              widget.existing == null ? 'the plate, measured' : 'the plate, re-measured',
              style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
            ),
            const SizedBox(height: 4),
            Text(
              'six answers; the targets follow from them (ICMR-NIN 2020, '
              'for an Indian adult). Rough is fine — everything here can '
              'be corrected.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
            const SizedBox(height: Gap.x4),
            Row(
              children: [
                Expanded(child: _field(c, 'height', 'cm', _height)),
                const SizedBox(width: Gap.x4),
                Expanded(child: _field(c, 'weight', 'kg', _weight)),
                const SizedBox(width: Gap.x4),
                Expanded(child: _field(c, 'age', 'years', _age)),
              ],
            ),
            const SizedBox(height: Gap.x4),
            _row(c, 'a day is mostly', [
              for (final a in ActivityLevel.values)
                QuillTab(
                  switch (a) {
                    ActivityLevel.sedentary => 'at a desk',
                    ActivityLevel.moderate => 'on my feet',
                    ActivityLevel.heavy => 'hard work',
                  },
                  selected: _activity == a,
                  onTap: () => setState(() => _activity = a),
                ),
            ]),
            _row(c, 'the goal', [
              for (final g in DietGoal.values)
                QuillTab(
                  switch (g) {
                    DietGoal.maintain => 'hold steady',
                    DietGoal.lose => 'lose some',
                    DietGoal.gain => 'build',
                  },
                  selected: _goal == g,
                  onTap: () => setState(() => _goal = g),
                ),
            ]),
            _row(c, 'I eat', [
              for (final k in FoodKind.values)
                QuillTab(
                  switch (k) {
                    FoodKind.veg => 'veg',
                    FoodKind.egg => 'veg + egg',
                    FoodKind.nonveg => 'everything',
                  },
                  selected: _kind == k,
                  onTap: () => setState(() => _kind = k),
                ),
            ]),
            const SizedBox(height: Gap.x4),
            // The answer back, as the numbers settle: what a day should hold.
            AnimatedSize(
              duration: Motion.spring,
              curve: Motion.curve,
              alignment: Alignment.topLeft,
              child: targets == null
                  ? const SizedBox(width: double.infinity)
                  : Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'a day for you holds about ',
                            style: LedgerType.bodyText.copyWith(
                              fontSize: 13,
                              color: c.inkFaint,
                            ),
                          ),
                          TextSpan(
                            text:
                                '${targetOf(targets, Nutrient.kcal).rda.round()} kcal',
                            style: LedgerType.amount.copyWith(
                              fontSize: 13,
                              color: c.ink,
                            ),
                          ),
                          TextSpan(
                            text: ' and ',
                            style: LedgerType.bodyText.copyWith(
                              fontSize: 13,
                              color: c.inkFaint,
                            ),
                          ),
                          TextSpan(
                            text:
                                '${targetOf(targets, Nutrient.protein).rda.round()} g of protein',
                            style: LedgerType.amount.copyWith(
                              fontSize: 13,
                              color: c.ink,
                            ),
                          ),
                          TextSpan(
                            text: draft!.bmi < 18.5
                                ? ' · you are under the weight range for your height'
                                : draft.bmi > 25
                                ? ' · you sit above the weight range for your height'
                                : '',
                            style: LedgerType.bodyText.copyWith(
                              fontSize: 13,
                              color: c.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: Gap.x4),
            Pressable(
              key: const ValueKey('diet-setup-save'),
              onTap: draft == null ? null : _save,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: draft == null ? c.rule : c.quill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.existing == null ? 'open the diet book' : 'keep',
                  textAlign: TextAlign.center,
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 15,
                    color: draft == null ? c.inkFaint : c.paper,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    LedgerColors c,
    String label,
    String unit,
    TextEditingController ctl,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: LedgerType.label.copyWith(fontSize: 11, color: c.inkFaint),
        ),
        TextField(
          key: ValueKey('diet-$label'),
          controller: ctl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          style: LedgerType.amount.copyWith(fontSize: 20, color: c.ink),
          cursorColor: c.quill,
          decoration: InputDecoration(
            suffixText: unit,
            suffixStyle: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
            isDense: true,
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.rule),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.quill, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(LedgerColors c, String label, List<Widget> tabs) {
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: LedgerType.label.copyWith(fontSize: 11, color: c.inkFaint),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              for (final t in tabs) ...[t, const SizedBox(width: Gap.x4)],
            ],
          ),
        ],
      ),
    );
  }
}
