import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/insights/insight_math.dart';
import 'package:budgetbox/features/today/widgets/sections.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the book notices about how it is written — drawn from the real
/// shape of the first month: rapido five times by hand, PG rent typed out,
/// a Spotify year, a flight and a deposit inflating "the month".
void main() {
  group('pin offers', () {
    test('a title written three times at a steady price is a habit', () {
      final rows = [
        ('Rapido', 5000, 2, 1),
        ('rapido', 6000, 2, 1),
        ('Rapido', 5000, 2, 1),
        ('Rapido', 7000, 2, 1),
        ('Rapido', 5000, 2, 1),
        ('shawarma', 21000, 3, 1),
        ('shawarma', 20000, 3, 1),
      ];
      final out = pinCandidates(rows);
      expect(out.length, 1);
      expect(out.first.title, 'Rapido');
      expect(out.first.amountPaise, 5000);
      expect(out.first.count, 5);
    });

    test('blanks that took the category name are not habits, nor are '
        'multiplied lines or ones already pinned', () {
      final rows = [
        ('Food & chai', 40000, 3, 1),
        ('Food & chai', 30000, 3, 1),
        ('Food & chai', 50000, 3, 1),
        ('rapido * 2', 10000, 2, 1),
        ('rapido * 2', 10000, 2, 1),
        ('rapido * 2', 10000, 2, 1),
        ('chai', 1500, 3, 1),
        ('chai', 1500, 3, 1),
        ('chai', 1500, 3, 1),
      ];
      expect(
        pinCandidates(rows, categoryNames: {'food & chai'}, taken: {'chai'}),
        isEmpty,
      );
      expect(
        pinCandidates(rows, categoryNames: {'food & chai'}).single.title,
        'chai',
      );
    });
  });

  group('recurring offers', () {
    final sept6 = DateTime(2026, 9, 6);
    test('rent by hand, a yearly premium, and nothing else', () {
      final rows = [
        ('PG rent', 850000, 1, 'Rent', 1, sept6),
        ('advance for PG', 300000, 1, 'Rent', 1, sept6),
        ('Spotify premium for 1 yr', 80000, 2, 'Bills & recharge', 1, DateTime(2026, 8, 24)),
        ('recharge for mom', 20000, 2, 'Bills & recharge', 1, DateTime(2026, 9, 13)),
        ('shawarma', 21000, 3, 'Food & chai', 1, DateTime(2026, 9, 12)),
      ];
      final out = recurringCandidates(rows);
      expect(out.map((c) => c.title), ['PG rent', 'Spotify premium for 1 yr']);
      expect(out.first.day, 6);
      expect(out.first.everyMonths, 1);
      expect(out.last.everyMonths, 12);
    });

    test('what is already on the shelf is not offered again', () {
      final rows = [('PG rent', 850000, 1, 'Rent', 1, sept6)];
      expect(recurringCandidates(rows, existing: {'pg rent'}), isEmpty);
    });
  });

  group('the budget, judged against its month', () {
    test('a line the month has outrun is raised to the truth', () {
      final fits = budgetFits(
        lines: [
          (budgetId: 1, categoryId: 10, name: 'Food & chai', limitPaise: 70000, spentPaise: 301500, count: 15),
          (budgetId: 2, categoryId: 11, name: 'Rent', limitPaise: 1500000, spentPaise: 850000, count: 1),
          (budgetId: 3, categoryId: 12, name: 'Grooming & care', limitPaise: 80000, spentPaise: 0, count: 0),
        ],
        unbudgeted: {13: ('Snacks & treats', 114900), 14: ('Bike & fuel', 22700)},
        elapsedDays: 18,
        daysInMonth: 30,
      );
      final byName = {for (final f in fits) f.name: f};
      expect(byName['Food & chai']!.kind, BudgetFitKind.raise);
      // ₹3,015 by the 18th projects past ₹5,000; rounded to ₹500.
      expect(byName['Food & chai']!.suggestedPaise % 50000, 0);
      expect(byName['Food & chai']!.suggestedPaise, greaterThan(400000));
      // Rent set at 15k against an 8.5k PG, paid once: a lump, not a pace —
      // read as it stands and lowered, not scolded.
      expect(byName['Rent']!.kind, BudgetFitKind.lower);
      expect(byName['Rent']!.suggestedPaise, 1000000);
      // Snacks have no line and real money; fuel is too small to bother.
      expect(byName['Snacks & treats']!.kind, BudgetFitKind.missing);
      expect(byName.containsKey('Bike & fuel'), isFalse);
      // Grooming untouched on the 18th is not yet "unused".
      expect(byName.containsKey('Grooming & care'), isFalse);
    });

    test('an untouched line late in the month is offered up', () {
      final fits = budgetFits(
        lines: [
          (budgetId: 3, categoryId: 12, name: 'Grooming & care', limitPaise: 80000, spentPaise: 0, count: 0),
        ],
        unbudgeted: const {},
        elapsedDays: 24,
        daysInMonth: 30,
      );
      expect(fits.single.kind, BudgetFitKind.unused);
    });

    test('nothing is projected before a week has passed', () {
      expect(
        budgetFits(
          lines: [
            (budgetId: 1, categoryId: 10, name: 'Food', limitPaise: 70000, spentPaise: 200000, count: 9),
          ],
          unbudgeted: const {},
          elapsedDays: 4,
          daysInMonth: 30,
        ),
        isEmpty,
      );
    });

    test('budgets round the way a person sets them', () {
      expect(roundBudget(312300), 310000);
      expect(roundBudget(812300), 800000);
      expect(roundBudget(1234500), 1250000);
    });

    test('a title filed two ways is offered to its majority, never guessed', () {
      final splits = splitTitles([
        (1, 'Rapido', 20, 'Getting around'),
        (2, 'rapido', 20, 'Getting around'),
        (3, 'Rapido', 20, 'Getting around'),
        (4, 'rapido', 21, 'Tickets & travel'),
        (5, 'rapido', 21, 'Tickets & travel'),
        (6, 'chai', 10, 'Food & chai'),
        (7, 'chai', 13, 'Snacks & treats'),
      ]);
      expect(splits.length, 1);
      expect(splits.single.title, 'rapido');
      expect(splits.single.toCategoryId, 20);
      expect(splits.single.minorityIds, [4, 5]);
      expect(splits.single.fromNames, ['Tickets & travel']);
    });
  });

  group('the running month', () {
    test('one-offs are split out by category and by the words', () {
      final r = runningMonth([
        ('PG rent', 850000, 'Rent'),
        ('advance for PG', 300000, 'Rent'),
        ('flight ticket for Pune', 542900, 'Getting around'),
        ('Rapido', 5000, 'Getting around'),
        ('pant from soulded store', 188900, 'Clothes & shoes'),
        ('biriyani', 28000, 'Food & chai'),
      ]);
      expect(r.runningPaise, 850000 + 5000 + 28000);
      expect(r.oneOffPaise, 300000 + 542900 + 188900);
      expect(r.oneOffs.first.$1, 'flight ticket for Pune');
    });
  });

  group('the pin offer on Today', () {
    late LedgerDb db;

    Widget host() => ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ledgerDayTheme(),
        home: const Scaffold(body: PinStrip()),
      ),
    );

    Future<void> settleAndUnmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    setUp(() async {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      final cash = await AccountRepo(db).create(
        name: 'Cash',
        kind: AccountKind.cash,
        openingBalancePaise: 500000,
      );
      final cats = await db.select(db.categories).get();
      final around = cats.firstWhere((c) => c.name.contains('around')).id;
      for (var d = 1; d <= 4; d++) {
        await TxnRepo(db).addExpense(
          amountPaise: 5000,
          accountId: cash,
          categoryId: around,
          title: 'Rapido',
          at: DateTime.now().subtract(Duration(days: d)),
        );
      }
    });
    tearDown(() => db.close());

    testWidgets('offers the line once, pins it on yes, forgets it on no', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.textContaining('rapido, four times'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pin-offer-yes')));
      await tester.pumpAndSettle();
      final pins = await db.select(db.pinneds).get();
      expect(pins.single.title, 'Rapido');
      expect(pins.single.amountPaise, 5000);
      expect(find.byKey(const ValueKey('pin-offer-yes')), findsNothing);
      await settleAndUnmount(tester);
    });

    testWidgets('"not this" is remembered', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pin-offer-no')));
      await tester.pumpAndSettle();
      expect(await SettingsRepo(db).pinPassed(), {'rapido'});
      expect(find.byKey(const ValueKey('pin-offer-yes')), findsNothing);
      await settleAndUnmount(tester);
    });
  });
}
