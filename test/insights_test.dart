import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/insights/insights_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page that says where the money went — and, more usefully, where it
/// *moved*.
void main() {
  group('categoryShifts — the arithmetic', () {
    test('sorts by the size of the movement, both directions', () {
      final shifts = categoryShifts(
        [(1, 10000), (2, 50000)], // this month
        [(1, 40000), (2, 45000)], // last month
      );
      // Food fell ₹300, chai rose ₹50: the fall leads.
      expect(shifts.first.categoryId, 1);
      expect(shifts.first.deltaPaise, -30000);
      expect(shifts.last.categoryId, 2);
      expect(shifts.last.deltaPaise, 5000);
    });

    test('names arrivals and departures', () {
      final shifts = categoryShifts(
        [(1, 20000)],
        [(2, 15000)],
      );
      expect(shifts.firstWhere((s) => s.categoryId == 1).isNew, isTrue);
      expect(shifts.firstWhere((s) => s.categoryId == 2).wentQuiet, isTrue);
    });

    test('a category that did not move says nothing', () {
      final shifts = categoryShifts([(1, 5000)], [(1, 5000)]);
      expect(shifts, isEmpty);
    });
  });

  group('InsightsPage', () {
    testWidgets('two months of entries become totals, bars and shifts',
        (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final accountId = await AccountRepo(db)
          .create(name: 'Cash', kind: AccountKind.cash);
      final cats = await db.select(db.categories).get();
      final food = cats.firstWhere((c) => c.name == 'Food & chai').id;

      final now = DateTime.now();
      final txns = TxnRepo(db);
      await txns.addExpense(
          amountPaise: 30000,
          accountId: accountId,
          categoryId: food,
          title: 'mess bill',
          at: now);
      await txns.addExpense(
          amountPaise: 12000,
          accountId: accountId,
          title: 'unfiled thing',
          at: now);
      // Last month: food cost more.
      await txns.addExpense(
          amountPaise: 50000,
          accountId: accountId,
          categoryId: food,
          title: 'mess bill',
          at: DateTime(now.year, now.month - 1, 15));

      await tester.pumpWidget(ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(
            theme: ledgerDayTheme(), home: const InsightsPage()),
      ));
      await tester.pumpAndSettle();

      // The month's figure and its verdict against last month.
      expect(find.text('₹420'), findsOneWidget);
      expect(find.textContaining('lighter than last month'), findsOneWidget);

      // Where it went: food leads the bars.
      expect(find.text('where it went'), findsOneWidget);
      expect(find.text('Food & chai'), findsWidgets);

      // The movement, named and signed.
      expect(find.text('versus last month'), findsOneWidget);
      expect(find.text('−₹200'), findsOneWidget);
      expect(find.textContaining('new this month'), findsOneWidget);

      // The heaviest single line — below the wheel, so scroll to it.
      await tester.scrollUntilVisible(find.text('heaviest lines'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('heaviest lines'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a book with nothing written says so', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(
            theme: ledgerDayTheme(), home: const InsightsPage()),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('a quiet page has nothing to explain'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('erasing the book', () {
    test('every table empties, the categories come back seeded', () async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final accountId = await AccountRepo(db)
          .create(name: 'Cash', kind: AccountKind.cash);
      await TxnRepo(db).addExpense(
          amountPaise: 2000,
          accountId: accountId,
          title: 'chai',
          at: DateTime.now());

      await db.eraseBook();

      expect(await db.select(db.txns).get(), isEmpty);
      expect(await db.select(db.accounts).get(), isEmpty);
      expect(await db.select(db.settings).get(), isEmpty);
      expect(await db.select(db.outbox).get(), isEmpty);
      // An empty book still needs words for money.
      final cats = await db.select(db.categories).get();
      expect(cats.map((c) => c.name), contains('Food & chai'));
      expect(cats.length, greaterThanOrEqualTo(8));
    });
  });
}
