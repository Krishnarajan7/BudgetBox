/// The arithmetic behind the diet book — pure, no widgets, testable.
///
/// Targets come from ICMR-NIN 2020 (*Nutrient Requirements for Indians*),
/// which is explicit that an individual should be planned against the EAR,
/// with the RDA as the comfortably-met line; energy uses their per-kilogram
/// figures (32 kcal/kg sedentary, 42 moderate, 53 heavy) rather than a
/// Western BMR equation the same committee found overstates Indian adults
/// by about a tenth. Protein follows their 0.83 g/kg RDA, 1 g/kg for a
/// cereal-based diet, and climbs when the goal is to build.
///
/// The intelligence rule, same as the money side: every judgement is
/// against *his own* week and *his own* foods. "Short on iron" alone is a
/// pamphlet; "short on iron four days of seven, and the sprouts you had on
/// Tuesday carry most of it" is something he can act on at lunch.
library;

import '../../core/foods.dart';
import '../../data/db.dart';

// ————— the person —————

enum ActivityLevel { sedentary, moderate, heavy }

enum DietGoal { maintain, lose, gain }

/// What the setup sheet asks, once. Everything else is derived.
class DietProfile {
  const DietProfile({
    required this.heightCm,
    required this.weightKg,
    required this.bornYear,
    required this.activity,
    required this.goal,
    required this.kind,
  });

  final int heightCm;
  final double weightKg;
  final int bornYear;
  final ActivityLevel activity;
  final DietGoal goal;

  /// What he eats: veg only, veg + egg, or everything.
  final FoodKind kind;

  int ageOn(DateTime now) => now.year - bornYear;

  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));

  Map<String, dynamic> toJson() => {
    'h': heightCm,
    'w': weightKg,
    'y': bornYear,
    'a': activity.name,
    'g': goal.name,
    'k': kind.name,
  };

  static DietProfile? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    try {
      return DietProfile(
        heightCm: (j['h'] as num).toInt(),
        weightKg: (j['w'] as num).toDouble(),
        bornYear: (j['y'] as num).toInt(),
        activity: ActivityLevel.values.byName('${j['a']}'),
        goal: DietGoal.values.byName('${j['g']}'),
        kind: FoodKind.values.byName('${j['k']}'),
      );
    } on Object {
      return null;
    }
  }
}

// ————— targets —————

/// One nutrient's lines: the floor to reach ([ear]), the line that means
/// comfortably met ([rda]), and for the few that harm in excess, the
/// ceiling ([max]). A nutrient with only a ceiling (free sugar, sodium) has
/// zero floors.
class Target {
  const Target(this.nutrient, {this.ear = 0, this.rda = 0, this.max});

  final Nutrient nutrient;
  final double ear;
  final double rda;
  final double? max;

  bool get isCeiling => ear == 0 && max != null;
}

/// The day's lines for [p]. Energy and protein move with the goal; the
/// micronutrients are the adult-male ICMR-NIN 2020 figures.
List<Target> targetsFor(DietProfile p) {
  final perKg = switch (p.activity) {
    ActivityLevel.sedentary => 32.0,
    ActivityLevel.moderate => 42.0,
    ActivityLevel.heavy => 53.0,
  };
  var kcal = perKg * p.weightKg;
  kcal *= switch (p.goal) {
    DietGoal.maintain => 1.0,
    DietGoal.lose => 0.85,
    DietGoal.gain => 1.10,
  };
  kcal = kcal.clamp(1500, 4000);
  final proteinPerKg = switch (p.goal) {
    DietGoal.gain => 1.6,
    DietGoal.lose => 1.2,
    DietGoal.maintain => p.kind == FoodKind.veg ? 1.0 : 0.83,
  };
  final protein = proteinPerKg * p.weightKg;
  final fibre = p.activity == ActivityLevel.sedentary ? 30.0 : 40.0;
  return [
    Target(Nutrient.kcal, ear: kcal * 0.9, rda: kcal, max: kcal * 1.15),
    Target(Nutrient.protein, ear: protein * 0.85, rda: protein),
    Target(
      Nutrient.carbs,
      ear: kcal * 0.45 / 4,
      rda: kcal * 0.55 / 4,
      max: kcal * 0.65 / 4,
    ),
    Target(
      Nutrient.fat,
      ear: kcal * 0.15 / 9,
      rda: kcal * 0.25 / 9,
      max: kcal * 0.30 / 9,
    ),
    Target(Nutrient.fibre, ear: fibre * 0.8, rda: fibre),
    Target(Nutrient.sugar, max: kcal * 0.10 / 4),
    Target(Nutrient.satFat, max: kcal * 0.10 / 9),
    Target(Nutrient.sodium, max: 2000),
    Target(Nutrient.potassium, ear: 3000, rda: 3500),
    Target(Nutrient.calcium, ear: 800, rda: 1000),
    Target(Nutrient.iron, ear: 11, rda: 19),
    Target(Nutrient.zinc, ear: 14, rda: 17),
    Target(Nutrient.magnesium, ear: 370, rda: 440),
    Target(Nutrient.vitA, ear: 460, rda: 1000),
    Target(Nutrient.vitC, ear: 65, rda: 80),
    Target(Nutrient.folate, ear: 250, rda: 300),
    Target(Nutrient.b1, ear: 1.5, rda: 1.8),
    Target(Nutrient.b2, ear: 2.1, rda: 2.5),
    Target(Nutrient.b3, ear: 15, rda: 18),
  ];
}

Target targetOf(List<Target> targets, Nutrient n) =>
    targets.firstWhere((t) => t.nutrient == n);

/// The nutrients worth a bar on the page, in the order they are drawn:
/// the ones a Pune office diet actually misses, and the two it overshoots.
const highlighted = [
  Nutrient.protein,
  Nutrient.fibre,
  Nutrient.iron,
  Nutrient.calcium,
  Nutrient.vitC,
  Nutrient.folate,
  Nutrient.sugar,
  Nutrient.sodium,
];

// ————— the day's shape —————

/// When each sitting is expected to have happened by. Past this hour with
/// nothing written, the sitting is missing; the book asks, once.
///
/// Weekends run an hour later — the body does, on days with no office.
DateTime slotDeadline(MealSlot slot, DateTime day) {
  final weekend = day.weekday >= DateTime.saturday;
  final (h, m) = switch (slot) {
    MealSlot.breakfast => (10, 30),
    MealSlot.lunch => (15, 0),
    MealSlot.snack => (18, 30),
    MealSlot.dinner => (22, 0),
  };
  return DateTime(day.year, day.month, day.day, h + (weekend ? 1 : 0), m);
}

/// Which sitting a dish eaten at [at] belongs to, by the clock.
MealSlot slotFor(DateTime at) {
  final h = at.hour;
  if (h < 11) return MealSlot.breakfast;
  if (h < 16) return MealSlot.lunch;
  if (h < 19) return MealSlot.snack;
  return MealSlot.dinner;
}

String slotName(MealSlot s) => switch (s) {
  MealSlot.breakfast => 'breakfast',
  MealSlot.lunch => 'lunch',
  MealSlot.snack => 'snack',
  MealSlot.dinner => 'dinner',
};

/// The sittings that count against a day: breakfast, lunch and dinner. A
/// snack is never missing — nobody owes the book a snack.
const mainSlots = [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner];

/// One line on the day's page — a measured dish, an unmeasured one, or a
/// deliberate skip. Wraps either a [Meal] row or a legacy free-text mark.
class MealEntry {
  const MealEntry({
    this.mealId,
    this.markId,
    required this.at,
    required this.slot,
    required this.name,
    this.foodKey,
    this.servings = 1,
    this.grams,
    this.facts,
    this.skipped = false,
  });

  final int? mealId;

  /// Set when this line is still an old 'meal' day-mark — words only.
  final int? markId;
  final DateTime at;
  final MealSlot slot;
  final String name;
  final String? foodKey;
  final double servings;
  final double? grams;
  final Nutrients? facts;
  final bool skipped;

  bool get measured => facts != null;
  bool get legacy => markId != null;
}

/// Everything eaten on one day, summed. Unmeasured lines add nothing to
/// the figures but are counted, so the page can say "and two more lines
/// the book couldn't weigh".
class DayTotals {
  const DayTotals({
    required this.date,
    required this.nutrients,
    required this.measured,
    required this.unmeasured,
    required this.slotsEaten,
    required this.slotsSkipped,
  });

  final String date;
  final Nutrients nutrients;
  final int measured;
  final int unmeasured;
  final Set<MealSlot> slotsEaten;
  final Set<MealSlot> slotsSkipped;

  bool get isEmpty => measured == 0 && unmeasured == 0 && slotsSkipped.isEmpty;

  /// Sittings the day neither ate nor skipped.
  List<MealSlot> get missing => [
    for (final s in mainSlots)
      if (!slotsEaten.contains(s) && !slotsSkipped.contains(s)) s,
  ];
}

DayTotals totalsFor(String date, Iterable<MealEntry> entries) {
  var sum = Nutrients.zero();
  var measured = 0;
  var unmeasured = 0;
  final eaten = <MealSlot>{};
  final skipped = <MealSlot>{};
  for (final e in entries) {
    if (e.skipped) {
      skipped.add(e.slot);
      continue;
    }
    eaten.add(e.slot);
    final f = e.facts;
    if (f == null) {
      unmeasured++;
    } else {
      measured++;
      sum = sum + f;
    }
  }
  // A sitting both eaten and skipped was eaten — the skip was a change of
  // mind the dish overrode.
  skipped.removeAll(eaten);
  return DayTotals(
    date: date,
    nutrients: sum,
    measured: measured,
    unmeasured: unmeasured,
    slotsEaten: eaten,
    slotsSkipped: skipped,
  );
}

/// The sittings that are missing *right now*: their deadline has passed
/// to-day with nothing written and no skip. What the reminders ask about.
List<MealSlot> missingNow(DayTotals today, DateTime now) => [
  for (final s in today.missing)
    if (now.isAfter(slotDeadline(s, now))) s,
];

// ————— the week —————

/// How a nutrient sat across the days that were actually written — a day
/// with nothing measured tells the book nothing and is left out.
class NutrientReading {
  const NutrientReading({
    required this.nutrient,
    required this.target,
    required this.mean,
    required this.daysCounted,
    required this.daysShort,
    required this.daysOver,
  });

  final Nutrient nutrient;
  final Target target;

  /// Mean daily intake over the counted days.
  final double mean;
  final int daysCounted;

  /// Days under the EAR (floor nutrients only).
  final int daysShort;

  /// Days over the ceiling (ceiling nutrients only).
  final int daysOver;

  /// 0..1 of the floor reached, or of the ceiling used.
  double get fraction {
    final line = target.isCeiling ? target.max! : target.rda;
    if (line <= 0) return 0;
    return (mean / line).clamp(0.0, 1.5);
  }

  /// Where it stands, in one word the bar can wear.
  ReadingState get state {
    if (daysCounted == 0) return ReadingState.unknown;
    if (target.isCeiling) {
      return mean > target.max! ? ReadingState.over : ReadingState.fine;
    }
    if (mean >= target.rda) return ReadingState.met;
    if (mean >= target.ear) return ReadingState.fine;
    return ReadingState.short;
  }
}

enum ReadingState { unknown, short, fine, met, over }

/// One reading per highlighted nutrient over [days]. Only days with at
/// least one measured dish count — the book judges what it saw.
List<NutrientReading> weekReadings(
  List<DayTotals> days,
  List<Target> targets, {
  List<Nutrient> nutrients = highlighted,
}) {
  final counted = [for (final d in days) if (d.measured > 0) d];
  return [
    for (final n in nutrients)
      () {
        final t = targetOf(targets, n);
        var sum = 0.0;
        var short = 0;
        var over = 0;
        for (final d in counted) {
          final v = d.nutrients[n];
          sum += v;
          if (!t.isCeiling && v < t.ear) short++;
          if (t.max != null && v > t.max!) over++;
        }
        return NutrientReading(
          nutrient: n,
          target: t,
          mean: counted.isEmpty ? 0 : sum / counted.length,
          daysCounted: counted.length,
          daysShort: short,
          daysOver: over,
        );
      }(),
  ];
}

// ————— the suggestions —————

/// One thing worth saying, and the dish that answers it when there is one.
class Suggestion {
  const Suggestion({
    required this.title,
    required this.body,
    this.food,
    this.servings = 1,
    this.slot,
    this.weight = 0,
  });

  final String title;
  final String body;

  /// A dish that closes the gap, ready to add with one tap.
  final FoodItem? food;
  final double servings;

  /// The sitting the dish belongs to, when the advice is about to-day.
  final MealSlot? slot;

  /// Heavier means said first.
  final int weight;
}

/// What the page should say, heaviest first. Everything here is computed
/// from what he wrote and what he eats; nothing is generic advice.
///
/// [history] is the last week of totals, oldest first, to-day last.
/// [eaten] is every measured entry over the same window — the pool the
/// suggestions pick dishes from, because a food he already eats is one he
/// will actually eat again. [catalogue] fills in only when his own foods
/// can't answer.
List<Suggestion> suggestions({
  required DietProfile profile,
  required List<Target> targets,
  required List<DayTotals> history,
  required List<MealEntry> eaten,
  required FoodCatalogue catalogue,
  required DateTime now,
}) {
  final out = <Suggestion>[];
  if (history.isEmpty) return out;
  final today = history.last;
  final readings = weekReadings(history, targets);
  final kcalT = targetOf(targets, Nutrient.kcal);
  final proT = targetOf(targets, Nutrient.protein);
  final counted = readings.first.daysCounted;

  // The pool of his own dishes, best per nutrient.
  FoodItem? own(Nutrient n, {double minPerServing = 0}) {
    FoodItem? best;
    var bestV = minPerServing;
    final seen = <String>{};
    for (final e in eaten) {
      final k = e.foodKey;
      if (k == null || !seen.add(k)) continue;
      final f = catalogue.byKey(k);
      if (f == null) continue;
      final v = f.forServings(1)[n];
      if (v > bestV) {
        bestV = v;
        best = f;
      }
    }
    return best;
  }

  FoodItem? fromCatalogue(Nutrient n, {double minPerServing = 0}) {
    FoodItem? best;
    var bestV = minPerServing;
    for (final f in catalogue.items) {
      if (profile.kind == FoodKind.veg && f.kind != FoodKind.veg) continue;
      if (profile.kind == FoodKind.egg && f.kind == FoodKind.nonveg) continue;
      // Per serving, but a serving must be a plausible thing to eat.
      final v = f.forServings(1)[n];
      final kcal = f.forServings(1).kcal;
      if (kcal > 700) continue;
      if (v > bestV) {
        bestV = v;
        best = f;
      }
    }
    return best;
  }

  String fmt(double v, Nutrient n) {
    if (n == Nutrient.kcal) return '${v.round()} kcal';
    final s = v >= 10 ? v.round().toString() : v.toStringAsFixed(1);
    return '$s ${n.unit}';
  }

  // 1. To-day's protein, paced. The one figure that matters by afternoon.
  final proSoFar = today.nutrients.protein;
  if (now.hour >= 14 && today.measured > 0 && proSoFar < proT.rda * 0.6) {
    final left = proT.rda - proSoFar;
    final slot = now.hour < 19 ? MealSlot.dinner : MealSlot.dinner;
    final pick =
        own(Nutrient.protein, minPerServing: 8) ??
        fromCatalogue(Nutrient.protein, minPerServing: 12);
    final gets = pick?.forServings(1).protein;
    out.add(
      Suggestion(
        title: '${left.round()} g of protein still to find to-day',
        body: pick == null
            ? 'dinner is where it lands — put the protein first on the plate'
            : '${pick.name.toLowerCase()} at dinner gets you '
                  '${gets!.round()} g of it',
        food: pick,
        slot: slot,
        weight: 90,
      ),
    );
  }

  // 2. Persistent gaps across the week, his own foods first.
  if (counted >= 3) {
    for (final r in readings) {
      if (r.target.isCeiling) continue;
      if (r.daysShort * 2 < r.daysCounted) continue;
      final gap = r.target.ear - r.mean;
      if (gap <= 0) continue;
      final ownPick = own(r.nutrient);
      final pick =
          (ownPick != null && ownPick.forServings(1)[r.nutrient] >= gap * 0.5)
          ? ownPick
          : fromCatalogue(r.nutrient, minPerServing: gap * 0.5) ?? ownPick;
      if (pick == null) continue;
      final per = pick.forServings(1)[r.nutrient];
      final servingsNeeded = (gap / per).clamp(0.5, 3.0);
      final rounded = (servingsNeeded * 2).ceil() / 2;
      final mine = ownPick != null && pick.key == ownPick.key;
      out.add(
        Suggestion(
          title:
              'short on ${r.nutrient.label} '
              '${r.daysShort == r.daysCounted ? 'every day' : '${r.daysShort} of ${r.daysCounted} days'}',
          body:
              '${fmt(r.mean, r.nutrient)} a day against '
              '${fmt(r.target.ear, r.nutrient)} — '
              '${mine ? 'the ${pick.name.toLowerCase()} you already eat carries' : '${pick.name.toLowerCase()} carries'} '
              '${fmt(per, r.nutrient)} a serving; '
              '${pick.spokenServing(rounded)} a day closes it',
          food: pick,
          servings: rounded,
          weight: 70 + (r.nutrient == Nutrient.protein ? 15 : 0),
        ),
      );
    }

    // 3. The ceilings he keeps crossing, and the dish that does it.
    for (final r in readings) {
      if (!r.target.isCeiling || r.daysOver < 2) continue;
      // Which of his own dishes carries the most of it, per serving.
      final culprit = own(r.nutrient);
      final per = culprit?.forServings(1)[r.nutrient];
      out.add(
        Suggestion(
          title:
              '${r.nutrient.label} past its line on ${r.daysOver} of '
              '${r.daysCounted} days',
          body: culprit == null
              ? '${fmt(r.mean, r.nutrient)} a day against a ceiling of '
                    '${fmt(r.target.max!, r.nutrient)}'
              : '${fmt(r.mean, r.nutrient)} a day against '
                    '${fmt(r.target.max!, r.nutrient)} — '
                    '${culprit.name.toLowerCase()} is where most of it lands, '
                    '${fmt(per!, r.nutrient)} a serving',
          weight: 60,
        ),
      );
    }

    // 4. Energy, against the goal — said as a pace, not a scolding.
    final kcalR = readings.firstWhere(
      (r) => r.nutrient == Nutrient.kcal,
      orElse: () => weekReadings(history, targets, nutrients: [Nutrient.kcal]).first,
    );
    if (kcalR.daysCounted >= 4) {
      final diff = kcalR.mean - kcalT.rda;
      if (diff.abs() > kcalT.rda * 0.12) {
        final kgMonth = (diff * 30 / 7700).abs();
        final verb = switch (profile.goal) {
          DietGoal.lose => diff > 0 ? 'above' : 'under',
          DietGoal.gain => diff > 0 ? 'above' : 'under',
          DietGoal.maintain => diff > 0 ? 'above' : 'under',
        };
        final fits = switch (profile.goal) {
          DietGoal.lose => diff < 0,
          DietGoal.gain => diff > 0,
          DietGoal.maintain => false,
        };
        out.add(
          Suggestion(
            title:
                '${diff.abs().round()} kcal a day $verb the target, on average',
            body: fits
                ? 'that pace is the goal working — about '
                      '${kgMonth.toStringAsFixed(1)} kg a month'
                : 'at that pace, about ${kgMonth.toStringAsFixed(1)} kg '
                      '${diff > 0 ? 'on' : 'off'} in a month — '
                      '${diff > 0 ? 'not what the goal asked for' : 'more than the goal asked for'}',
            weight: 50,
          ),
        );
      }
    }
  }

  // 5. The rhythm: breakfasts going missing, and what it costs.
  final past = history.length > 1 ? history.sublist(0, history.length - 1) : const <DayTotals>[];
  final written = [for (final d in past) if (!d.isEmpty) d];
  if (written.length >= 4) {
    final noBreakfast = [
      for (final d in written)
        if (!d.slotsEaten.contains(MealSlot.breakfast)) d,
    ];
    final withBreakfast = [
      for (final d in written)
        if (d.slotsEaten.contains(MealSlot.breakfast) && d.measured > 0) d,
    ];
    if (noBreakfast.length >= 3) {
      String tail = '';
      final withM = [for (final d in withBreakfast) if (d.measured > 0) d];
      final noM = [for (final d in noBreakfast) if (d.measured > 0) d];
      if (withM.length >= 2 && noM.length >= 2) {
        final a = withM.fold(0.0, (s, d) => s + d.nutrients.protein) / withM.length;
        final b = noM.fold(0.0, (s, d) => s + d.nutrients.protein) / noM.length;
        if (a - b > 8) {
          tail =
              ' — the mornings you ate ended ${(a - b).round()} g of protein ahead';
        }
      }
      final pick = own(Nutrient.protein, minPerServing: 5);
      out.add(
        Suggestion(
          title:
              'breakfast went missing ${noBreakfast.length} of '
              '${written.length} days',
          body: pick == null
              ? 'the fastest fix is something already in the kitchen$tail'
              : '${pick.name.toLowerCase()} is the quickest one you already '
                    'eat$tail',
          food: pick,
          slot: MealSlot.breakfast,
          weight: 65,
        ),
      );
    }
  }

  // 6. When there is nothing to fix, say so — once, plainly.
  if (out.isEmpty && counted >= 3) {
    final met = [
      for (final r in readings)
        if (r.state == ReadingState.met || r.state == ReadingState.fine)
          r.nutrient.label,
    ];
    if (met.length >= readings.length - 1) {
      out.add(
        const Suggestion(
          title: 'the week balanced',
          body: 'every line the book watches was met — nothing to change',
          weight: 10,
        ),
      );
    }
  }

  out.sort((a, b) => b.weight.compareTo(a.weight));
  return out;
}
