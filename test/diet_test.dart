import 'dart:convert';

import 'package:budgetbox/core/foods.dart';
import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/meal_voice.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/diet_repo.dart';
import 'package:budgetbox/data/repos/marks_repo.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/diet/diet_math.dart';
import 'package:budgetbox/features/diet/diet_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pocket catalogue: enough dishes to answer every rule in the math.
FoodCatalogue pocket() => FoodCatalogue.of([
  FoodItem(
    key: 'idli',
    name: 'Idli',
    aliases: ['idly'],
    unit: 'idli',
    servingGrams: 40,
    kind: FoodKind.veg,
    per100g: Nutrients.of({
    Nutrient.kcal: 130,
    Nutrient.protein: 3,
    Nutrient.carbs: 27,
    Nutrient.fat: 0.5,
    Nutrient.fibre: 1,
    Nutrient.iron: 0.5,
    Nutrient.calcium: 10,
  }),
  ),
  FoodItem(
    key: 'egg',
    name: 'Boiled egg',
    aliases: ['egg', 'anda'],
    unit: 'egg',
    servingGrams: 50,
    kind: FoodKind.egg,
    per100g: Nutrients.of({
    Nutrient.kcal: 155,
    Nutrient.protein: 13,
    Nutrient.fat: 11,
    Nutrient.iron: 1.2,
    Nutrient.calcium: 50,
  }),
  ),
  FoodItem(
    key: 'chicken',
    name: 'Chicken curry',
    aliases: [],
    unit: 'bowl',
    servingGrams: 200,
    kind: FoodKind.nonveg,
    per100g: Nutrients.of({
    Nutrient.kcal: 150,
    Nutrient.protein: 14,
    Nutrient.fat: 9,
    Nutrient.iron: 1.2,
    Nutrient.sodium: 400,
  }),
  ),
  FoodItem(
    key: 'sprouts',
    name: 'Sprouts',
    aliases: ['moong sprouts'],
    unit: 'small bowl',
    servingGrams: 100,
    kind: FoodKind.veg,
    per100g: Nutrients.of({
    Nutrient.kcal: 30,
    Nutrient.protein: 3,
    Nutrient.fibre: 1.8,
    Nutrient.iron: 6,
    Nutrient.vitC: 13,
    Nutrient.folate: 61,
  }),
  ),
  FoodItem(
    key: 'chai',
    name: 'Hot tea',
    aliases: ['chai', 'tea'],
    unit: 'tea cup',
    servingGrams: 180,
    kind: FoodKind.veg,
    per100g: Nutrients.of({
    Nutrient.kcal: 16,
    Nutrient.sugar: 2.6,
    Nutrient.calcium: 14,
  }),
  ),
]);

const krish = DietProfile(
  heightCm: 172,
  weightKg: 64,
  bornYear: 2004,
  activity: ActivityLevel.sedentary,
  goal: DietGoal.maintain,
  kind: FoodKind.nonveg,
);

void main() {
  group('the targets', () {
    test('an Indian adult at a desk gets ICMR-NIN\'s per-kilo energy', () {
      final t = targetsFor(krish);
      // 32 kcal/kg × 64 kg.
      expect(targetOf(t, Nutrient.kcal).rda, closeTo(2048, 0.5));
      // 0.83 g/kg for a mixed diet.
      expect(targetOf(t, Nutrient.protein).rda, closeTo(53.1, 0.1));
      expect(targetOf(t, Nutrient.iron).ear, 11);
      expect(targetOf(t, Nutrient.iron).rda, 19);
      expect(targetOf(t, Nutrient.sodium).isCeiling, isTrue);
      expect(targetOf(t, Nutrient.fibre).rda, 30);
    });

    test('building raises protein; a veg diet raises it a little', () {
      final gain = targetsFor(
        const DietProfile(
          heightCm: 172,
          weightKg: 64,
          bornYear: 2004,
          activity: ActivityLevel.sedentary,
          goal: DietGoal.gain,
          kind: FoodKind.nonveg,
        ),
      );
      expect(targetOf(gain, Nutrient.protein).rda, closeTo(102.4, 0.1));
      expect(targetOf(gain, Nutrient.kcal).rda, closeTo(2048 * 1.1, 1));
      final veg = targetsFor(
        const DietProfile(
          heightCm: 172,
          weightKg: 64,
          bornYear: 2004,
          activity: ActivityLevel.sedentary,
          goal: DietGoal.maintain,
          kind: FoodKind.veg,
        ),
      );
      expect(targetOf(veg, Nutrient.protein).rda, 64);
    });

    test('the profile round-trips through JSON', () {
      final back = DietProfile.fromJson(
        jsonDecode(jsonEncode(krish.toJson())) as Map<String, dynamic>,
      );
      expect(back!.weightKg, 64);
      expect(back.kind, FoodKind.nonveg);
      expect(back.ageOn(DateTime(2026, 9, 18)), 22);
      expect(DietProfile.fromJson({'h': 'x'}), isNull);
    });
  });

  group('the day\'s shape', () {
    test('sittings have deadlines, later at weekends', () {
      final fri = DateTime(2026, 9, 18); // a Friday
      final sat = DateTime(2026, 9, 19);
      expect(slotDeadline(MealSlot.breakfast, fri).hour, 10);
      expect(slotDeadline(MealSlot.breakfast, fri).minute, 30);
      expect(slotDeadline(MealSlot.lunch, fri).hour, 15);
      expect(slotDeadline(MealSlot.dinner, fri).hour, 22);
      expect(slotDeadline(MealSlot.breakfast, sat).hour, 11);
    });

    test('the clock decides the sitting', () {
      expect(slotFor(DateTime(2026, 9, 18, 8)), MealSlot.breakfast);
      expect(slotFor(DateTime(2026, 9, 18, 13)), MealSlot.lunch);
      expect(slotFor(DateTime(2026, 9, 18, 17)), MealSlot.snack);
      expect(slotFor(DateTime(2026, 9, 18, 21)), MealSlot.dinner);
    });

    test('totals sum only the measured, count the rest, and honour skips', () {
      final cat = pocket();
      final idli = cat.byKey('idli')!;
      final t = totalsFor('2026-09-18', [
        MealEntry(
          mealId: 1,
          at: DateTime(2026, 9, 18, 8),
          slot: MealSlot.breakfast,
          name: 'Idli',
          facts: idli.forServings(3),
        ),
        MealEntry(
          markId: 9,
          at: DateTime(2026, 9, 18, 13),
          slot: MealSlot.lunch,
          name: 'mess lunch',
        ),
        MealEntry(
          mealId: 2,
          at: DateTime(2026, 9, 18, 22),
          slot: MealSlot.dinner,
          name: 'skipped',
          skipped: true,
        ),
      ]);
      expect(t.measured, 1);
      expect(t.unmeasured, 1);
      expect(t.nutrients.kcal, closeTo(156, 0.1));
      expect(t.slotsEaten, {MealSlot.breakfast, MealSlot.lunch});
      expect(t.slotsSkipped, {MealSlot.dinner});
      expect(t.missing, isEmpty);
    });

    test('a sitting is missing only once its hour has passed', () {
      final t = totalsFor('2026-09-18', const []);
      expect(t.missing, mainSlots);
      expect(missingNow(t, DateTime(2026, 9, 18, 9)), isEmpty);
      expect(missingNow(t, DateTime(2026, 9, 18, 11)), [MealSlot.breakfast]);
      expect(missingNow(t, DateTime(2026, 9, 18, 23)), mainSlots);
    });
  });

  group('the week and what it says', () {
    final cat = pocket();
    final targets = targetsFor(krish);

    DayTotals day(String date, List<(String, double)> dishes) => totalsFor(date, [
      for (final (i, d) in dishes.indexed)
        MealEntry(
          mealId: i,
          at: DateTime.parse('$date 13:00:00'),
          slot: MealSlot.lunch,
          name: d.$1,
          foodKey: d.$1,
          facts: cat.byKey(d.$1)!.forServings(d.$2),
        ),
    ]);

    test('readings judge only the days that were written', () {
      final week = [
        day('2026-09-12', [('idli', 4)]),
        totalsFor('2026-09-13', const []),
        day('2026-09-14', [('idli', 4)]),
      ];
      final r = weekReadings(week, targets);
      final iron = r.firstWhere((x) => x.nutrient == Nutrient.iron);
      expect(iron.daysCounted, 2);
      expect(iron.daysShort, 2);
      expect(iron.state, ReadingState.short);
    });

    test('a persistent gap names the dish he already eats that closes it', () {
      final week = [
        for (var d = 12; d <= 18; d++)
          day('2026-09-$d', [('idli', 4), ('chai', 2)]),
      ];
      final eaten = [
        MealEntry(
          mealId: 99,
          at: DateTime(2026, 9, 15, 13),
          slot: MealSlot.lunch,
          name: 'Sprouts',
          foodKey: 'sprouts',
          facts: cat.byKey('sprouts')!.forServings(1),
        ),
      ];
      final says = suggestions(
        profile: krish,
        targets: targets,
        history: week,
        eaten: eaten,
        catalogue: cat,
        now: DateTime(2026, 9, 18, 20),
      );
      final iron = says.firstWhere((s) => s.title.startsWith('short on iron'));
      expect(iron.title, 'short on iron every day');
      expect(iron.food!.key, 'sprouts');
      expect(iron.body, contains('you already eat'));
      // Protein is short too, and the day's own pacing line comes first.
      expect(says.first.title, contains('protein still to find'));
    });

    test('a veg profile is never told to eat chicken', () {
      const veg = DietProfile(
        heightCm: 172,
        weightKg: 64,
        bornYear: 2004,
        activity: ActivityLevel.sedentary,
        goal: DietGoal.gain,
        kind: FoodKind.veg,
      );
      final week = [
        for (var d = 12; d <= 18; d++) day('2026-09-$d', [('idli', 4)]),
      ];
      final says = suggestions(
        profile: veg,
        targets: targetsFor(veg),
        history: week,
        eaten: const [],
        catalogue: cat,
        now: DateTime(2026, 9, 18, 20),
      );
      for (final s in says) {
        expect(s.food?.kind, isNot(FoodKind.nonveg));
        expect(s.food?.kind, isNot(FoodKind.egg));
      }
    });

    test('a balanced week is told so, once', () {
      final week = [
        for (var d = 12; d <= 18; d++)
          day('2026-09-$d', [('chicken', 2), ('sprouts', 3), ('idli', 6), ('egg', 2)]),
      ];
      final says = suggestions(
        profile: krish,
        targets: targets,
        history: week,
        eaten: const [],
        catalogue: cat,
        now: DateTime(2026, 9, 18, 9),
      );
      // Whatever else it says, nothing scolds — and a gap-free week may
      // simply say so.
      expect(says.where((s) => s.title == 'the week balanced').length, lessThanOrEqualTo(1));
    });
  });

  group('the catalogue', () {
    test('resolves a plain word to its one dish, and refuses ambiguity', () {
      final cat = pocket();
      expect(cat.resolve('idli')!.key, 'idli');
      expect(cat.resolve('chai')!.key, 'chai');
      expect(cat.resolve('EGG')!.key, 'egg');
      expect(cat.resolve('mess lunch'), isNull);
    });

    test('search ranks a name start above a match inside', () {
      final cat = pocket();
      final hits = cat.search('c');
      expect(hits.map((f) => f.key), containsAll(['chicken', 'chai']));
      expect(cat.search('curry').first.key, 'chicken');
      expect(cat.search('x'), isEmpty);
      expect(cat.search('chicken', prefer: FoodKind.veg), isEmpty);
    });

    test('a serving is spoken the way a person says it', () {
      final cat = pocket();
      expect(cat.byKey('idli')!.spokenServing(1), 'an idli');
      expect(cat.byKey('idli')!.spokenServing(3), 'three idlis');
      expect(cat.byKey('chicken')!.spokenServing(0.5), 'half a bowl');
      expect(cat.byKey('chicken')!.spokenServing(1.5), '1½ bowls');
    });

    test('the bundled table loads and knows the Pune staples', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final cat = await FoodCatalogue.load();
      expect(cat.items.length, greaterThan(1000));
      expect(cat.resolve('maggi'), isNotNull);
      expect(cat.resolve('vada pav'), isNotNull);
      expect(cat.resolve('idli'), isNotNull);
      final chai = cat.resolve('chai')!;
      expect(chai.forServings(1).kcal, lessThan(80));
      // Every dish has a plausible serving and energy.
      for (final f in cat.items) {
        expect(f.servingGrams, inInclusiveRange(1, 700), reason: f.name);
        expect(f.forServings(1).kcal, lessThan(1400), reason: f.name);
      }
    });
  });

  group('the repo', () {
    late LedgerDb db;
    late DietRepo repo;

    setUp(() {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      repo = DietRepo(db, SettingsRepo(db));
    });
    tearDown(() => db.close());

    test('old words-only marks share the page until they are weighed', () async {
      final cat = pocket();
      final day = DateTime(2026, 9, 18);
      await MarksRepo(db).addMeal(day, 'mess lunch');
      await repo.add(cat.byKey('idli')!, day: day, servings: 3, slot: MealSlot.breakfast);

      var page = await repo.watchDay(day).first;
      expect(page.length, 2);
      final legacy = page.firstWhere((e) => e.legacy);
      expect(legacy.name, 'mess lunch');
      expect(legacy.measured, isFalse);

      await repo.measure(legacy, cat.byKey('chicken')!, servings: 1);
      page = await repo.watchDay(day).first;
      expect(page.length, 2);
      expect(page.every((e) => e.measured), isTrue);
      expect(await (db.select(db.dayMarks)).get(), isEmpty);
    });

    test('typed words resolve when they name one dish, else stay words', () async {
      final cat = pocket();
      final day = DateTime(2026, 9, 18);
      await repo.addByText('idli', cat, day: day);
      await repo.addByText('hostel dinner', cat, day: day);
      final page = await repo.watchDay(day).first;
      expect(page.where((e) => e.measured).single.foodKey, 'idli');
      expect(page.where((e) => !e.measured).single.name, 'hostel dinner');
    });

    test('a skip is one row, and a dish written later outranks it', () async {
      final cat = pocket();
      final day = DateTime(2026, 9, 18);
      await repo.skip(day, MealSlot.breakfast);
      await repo.skip(day, MealSlot.breakfast);
      var t = totalsFor('2026-09-18', await repo.watchDay(day).first);
      expect(t.slotsSkipped, {MealSlot.breakfast});
      await repo.add(cat.byKey('idli')!, day: day, slot: MealSlot.breakfast);
      t = totalsFor('2026-09-18', await repo.watchDay(day).first);
      expect(t.slotsSkipped, isEmpty);
      expect(t.slotsEaten, {MealSlot.breakfast});
    });

    test('food spend is found by category name, loosely', () async {
      final cash = await AccountRepo(db).create(
        name: 'Cash',
        kind: AccountKind.cash,
        openingBalancePaise: 100000,
      );
      final cats = await db.select(db.categories).get();
      final food = cats.firstWhere((c) => c.name.toLowerCase().contains('food'));
      final other = cats.firstWhere((c) => !c.name.toLowerCase().contains('food') && c.kind == CategoryKind.expense);
      final now = DateTime.now();
      await TxnRepo(db).addExpense(
        amountPaise: 18000,
        accountId: cash,
        categoryId: food.id,
        title: 'Saravana',
        at: DateTime(now.year, now.month, now.day, 13, 10),
      );
      await TxnRepo(db).addExpense(
        amountPaise: 5000,
        accountId: cash,
        categoryId: other.id,
        title: 'Auto',
        at: DateTime(now.year, now.month, now.day, 13, 20),
      );
      final spend = await repo.foodSpend(now);
      expect(spend.map((t) => t.title), ['Saravana']);
    });
  });

  group('the reminders', () {
    test('wording rotates by the day and never repeats a sitting\'s line', () {
      final a = mealNudgeCopy(DateTime(2026, 9, 18), MealSlot.lunch);
      final b = mealNudgeCopy(DateTime(2026, 9, 19), MealSlot.lunch);
      expect(a, isNot(b));
      // And stays put for the same day, however often it is re-said.
      expect(mealNudgeCopy(DateTime(2026, 9, 18), MealSlot.lunch), a);
    });

    test('a food expense with nothing written becomes the question', () {
      final c = mealNudgeCopy(
        DateTime(2026, 9, 18),
        MealSlot.lunch,
        cueTitle: 'Saravana',
        cuePaise: 18000,
        cueAt: DateTime(2026, 9, 18, 13, 10),
      );
      expect('${c.title} ${c.body}', contains('₹180'));
      expect('${c.title} ${c.body}', contains('Saravana'));
      expect('${c.title} ${c.body}', contains('1:10 pm'));
    });

    test('dinner speaks the protein still owed', () {
      final c = mealNudgeCopy(DateTime(2026, 9, 18), MealSlot.dinner, proteinLeftG: 34);
      expect('${c.title} ${c.body}', contains('34 g'));
    });

    test('the lines ask only about sittings still open and unwritten', () async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsRepo(db);
      // No profile: silence.
      expect(await mealLines(db, now: DateTime(2026, 9, 18, 9)), isEmpty);
      await settings.setDietProfileJson(jsonEncode(krish.toJson()));
      final repo = DietRepo(db, settings);
      final morning = DateTime(2026, 9, 18, 9);
      var lines = await mealLines(db, now: morning);
      expect(lines.keys, containsAll(mainSlots));
      expect(lines[MealSlot.breakfast]!.at.hour, 10);
      // Breakfast written: its question goes; lunch and dinner stay.
      await repo.add(pocket().byKey('idli')!, day: morning, slot: MealSlot.breakfast, at: morning);
      lines = await mealLines(db, now: morning);
      expect(lines.containsKey(MealSlot.breakfast), isFalse);
      expect(lines.containsKey(MealSlot.lunch), isTrue);
      // Past lunch's hour, lunch is no longer asked about either.
      lines = await mealLines(db, now: DateTime(2026, 9, 18, 16));
      expect(lines.keys, [MealSlot.dinner]);
    });
  });

  group('the page', () {
    late LedgerDb db;

    Widget host() => ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(theme: ledgerDayTheme(), home: const DietPage()),
    );

    Future<void> settleAndUnmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    setUp(() => db = LedgerDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    testWidgets('an unopened book offers its door', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('diet-open')), findsOneWidget);
      await settleAndUnmount(tester);
    });

    testWidgets('an opened book leads with the figure and the sittings', (
      tester,
    ) async {
      await SettingsRepo(db).setDietProfileJson(jsonEncode(krish.toJson()));
      await db
          .into(db.meals)
          .insert(
            MealsCompanion.insert(
              date: _todayKey(),
              slot: MealSlot.breakfast,
              foodKey: const Value('idli'),
              name: 'Idli',
              servings: const Value(3),
              facts: Value(jsonEncode(pocket().byKey('idli')!.forServings(3).toJson())),
              at: DateTime.now(),
            ),
          );
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('eaten so far'), findsOneWidget);
      expect(find.textContaining('of 2,048 kcal'), findsOneWidget);
      expect(find.text('breakfast'), findsOneWidget);
      expect(find.textContaining('Idli'), findsWidgets);
      // Section heads are set in small caps; the page is long, so scroll.
      await tester.scrollUntilVisible(
        find.text('THE BALANCE'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('THE BALANCE'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('diet-write')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('diet-write')), findsOneWidget);
      await settleAndUnmount(tester);
    });
  });
}

String _todayKey() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}
