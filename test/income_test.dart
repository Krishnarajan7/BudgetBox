import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/income/income_page.dart';
import 'package:budgetbox/features/today/widgets/digit_roll.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the income arithmetic', () {
    final flows = [
      for (var i = 0; i < 6; i++)
        MonthFlow(
          month: DateTime(2026, 4 + i, 1),
          inPaise: 5000000 + i * 100000,
          outPaise: 3000000,
        ),
    ];

    test('a one-month window compares against the month before', () {
      final w = incomeWindow(flows, DateTime(2026, 9, 1), 1);
      expect(w.now, 5500000);
      expect(w.before, 5400000);
      expect(w.spent, 3000000);
    });

    test('a three-month window compares against the three before it', () {
      final w = incomeWindow(flows, DateTime(2026, 7, 1), 3);
      expect(w.now, 5300000 + 5400000 + 5500000);
      expect(w.before, 5000000 + 5100000 + 5200000);
    });

    test('months outside the flows count as nothing, not as an error', () {
      final w = incomeWindow(flows, DateTime(2026, 1, 1), 2);
      expect(w.now, 0);
      expect(w.before, 0);
    });

    test('sources fold by title, case-blind, heaviest first', () {
      final rows = [
        _income('Salary', 5000000, 1),
        _income('salary', 5000000, 2),
        _income('Freelance', 200000, 3),
        _expense('Chai', 2000, 4),
      ];
      final s = incomeSources(rows);
      expect(s.length, 2);
      expect(s.first.name, 'Salary');
      expect(s.first.paise, 10000000);
      expect(s.first.count, 2);
      expect(s.last.name, 'Freelance');
    });

    test('the kept share is a whole percent, and silent on nothing', () {
      expect(keptShare(100000, 65000), 35);
      expect(keptShare(100000, 120000), -20);
      expect(keptShare(0, 5000), isNull);
    });

    test('ranges know how many months they hold', () {
      final sep = DateTime(2026, 9, 1);
      expect(IncomeRange.month.months(sep), 1);
      expect(IncomeRange.quarter.months(sep), 3);
      expect(IncomeRange.year.months(sep), 12);
      // September sits six months into an April financial year.
      expect(IncomeRange.fy.months(sep), 6);
    });
  });

  group('the income page', () {
    late LedgerDb db;

    Widget host() => ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(theme: ledgerDayTheme(), home: const IncomePage()),
    );

    Future<void> settleAndUnmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    setUp(() async {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      final bank = await AccountRepo(db).create(
        name: 'HDFC',
        kind: AccountKind.bank,
        openingBalancePaise: 1000000,
      );
      final now = DateTime.now();
      await TxnRepo(db).addIncome(
        amountPaise: 5000000,
        accountId: bank,
        title: 'Salary',
        at: DateTime(now.year, now.month, 1, 9),
      );
      await TxnRepo(db).addExpense(
        amountPaise: 1500000,
        accountId: bank,
        title: 'Rent',
        at: DateTime(now.year, now.month, 2, 9),
      );
    });

    tearDown(() => db.close());

    testWidgets('leads with the month\'s figure and what was kept', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final roll = tester.widget<DigitRoll>(find.byType(DigitRoll));
      expect(roll.paise, 5000000);
      expect(find.textContaining('70%'), findsOneWidget);
      expect(find.text('Salary'), findsWidgets);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('income-write')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('income-write')), findsOneWidget);
      await settleAndUnmount(tester);
    });

    testWidgets('the range chips turn the window', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('12M'));
      await tester.pumpAndSettle();
      expect(find.text('vs prior 12M'), findsOneWidget);
      await settleAndUnmount(tester);
    });
  });
}

Txn _income(String title, int paise, int id) => Txn(
  id: id,
  amountPaise: paise,
  type: TxnType.income,
  accountId: 1,
  title: title,
  at: DateTime(2026, 9, 1),
  createdAt: DateTime(2026, 9, 1),
);

Txn _expense(String title, int paise, int id) => Txn(
  id: id,
  amountPaise: paise,
  type: TxnType.expense,
  accountId: 1,
  title: title,
  at: DateTime(2026, 9, 1),
  createdAt: DateTime(2026, 9, 1),
);
