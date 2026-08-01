import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/features/add/money_moves.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LedgerDb db;
  late int cashId;
  late int hdfcId;

  setUp(() async {
    db = LedgerDb.forTesting(NativeDatabase.memory());
    final accounts = AccountRepo(db);
    cashId = await accounts.create(name: 'Cash', kind: AccountKind.cash);
    hdfcId = await accounts.create(
      name: 'HDFC',
      kind: AccountKind.bank,
      openingBalancePaise: 100000, // ₹1,000
    );
  });

  tearDown(() => db.close());

  Widget host(Future<void> Function(BuildContext) open) {
    return ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ledgerDayTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<Account> account(int id) =>
      (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingle();

  // Lets the db streams and sheet timers wind down before the test ends.
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('income: amount + Salary + Write it in credits the account',
      (tester) async {
    await tester.pumpWidget(host(showIncomeSheet));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('income-amount')), '500');
    await tester.pump();
    await tester.tap(find.text('Salary'));
    await tester.pump();
    await tester.tap(find.text('Write it in'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.txns).get();
    expect(rows, hasLength(1));
    expect(rows.single.type, TxnType.income);
    expect(rows.single.amountPaise, 50000);
    // Blank title falls back to the category's name.
    expect(rows.single.title, 'Salary');
    expect(rows.single.accountId, cashId);
    expect((await account(cashId)).balancePaise, 50000);

    // The sheet closed itself; the ledger line is the confirmation.
    expect(find.text('Write it in'), findsNothing);
    await drain(tester);
  });

  testWidgets('transfer: same account both sides is dead, then money moves',
      (tester) async {
    await tester.pumpWidget(host(showTransferSheet));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('transfer-amount')), '200');
    await tester.tap(find.byKey(Key('from-$cashId')));
    await tester.tap(find.byKey(Key('to-$cashId')));
    await tester.pump();

    // Cash → Cash goes nowhere; the button refuses.
    await tester.tap(find.text('Move it'));
    await tester.pumpAndSettle();
    expect(await db.select(db.txns).get(), isEmpty);

    await tester.tap(find.byKey(Key('to-$hdfcId')));
    await tester.pump();
    expect(find.textContaining('Cash − ₹200'), findsOneWidget);
    expect(find.textContaining('HDFC + ₹200'), findsOneWidget);

    await tester.tap(find.text('Move it'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.txns).get();
    expect(rows, hasLength(1));
    expect(rows.single.type, TxnType.transfer);
    expect(rows.single.accountId, cashId);
    expect(rows.single.toAccountId, hdfcId);
    expect(rows.single.amountPaise, 20000);
    expect((await account(cashId)).balancePaise, -20000);
    expect((await account(hdfcId)).balancePaise, 120000);
    await drain(tester);
  });

  testWidgets('fix balance: writes the true number and a fresh asOf',
      (tester) async {
    // Age the reading so freshness is observable.
    await (db.update(db.accounts)..where((a) => a.id.equals(hdfcId)))
        .write(AccountsCompanion(asOf: Value(DateTime(2020))));

    await tester.pumpWidget(host(showFixBalanceSheet));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('fix-$hdfcId')));
    await tester.pump();
    expect(find.text('the book says ₹1,000'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('fix-amount')), '2500');
    await tester.pump();
    await tester.tap(find.text("That's the number"));
    await tester.pumpAndSettle();

    final a = await account(hdfcId);
    expect(a.balancePaise, 250000);
    expect(a.asOf.isAfter(DateTime(2025)), isTrue);
    // No transaction was written — a correction, not an entry.
    expect(await db.select(db.txns).get(), isEmpty);
    await drain(tester);
  });

  group('quietDays', () {
    Txn txn(DateTime at, {TxnType type = TxnType.expense}) => Txn(
          id: 0,
          amountPaise: 100,
          type: type,
          accountId: 1,
          title: 'x',
          at: at,
          createdAt: at,
        );

    test('skips written days and today, most recent first', () {
      final now = DateTime(2026, 7, 31, 14, 30);
      final txns = [
        txn(DateTime(2026, 7, 31, 9)), // today never appears anyway
        txn(DateTime(2026, 7, 30, 23, 59)), // written, late at night
        txn(DateTime(2026, 7, 27, 8)), // written
        // Income keeps a day quiet — only expenses write it.
        txn(DateTime(2026, 7, 28, 10), type: TxnType.income),
      ];
      expect(quietDays(txns, now), [
        DateTime(2026, 7, 29),
        DateTime(2026, 7, 28),
        DateTime(2026, 7, 26),
        DateTime(2026, 7, 25),
        DateTime(2026, 7, 24),
      ]);
    });

    test('caps at lookback and walks across a month boundary', () {
      final now = DateTime(2026, 8, 3);
      final days = quietDays(const [], now);
      expect(days, hasLength(7));
      expect(days.first, DateTime(2026, 8, 2));
      expect(days.last, DateTime(2026, 7, 27));
      expect(days, isNot(contains(DateTime(2026, 8, 3))));

      expect(quietDays(const [], now, lookback: 3), [
        DateTime(2026, 8, 2),
        DateTime(2026, 8, 1),
        DateTime(2026, 7, 31),
      ]);
    });

    test('a fully written week has no quiet days', () {
      final now = DateTime(2026, 7, 31, 12);
      final txns = [
        for (var i = 1; i <= 7; i++) txn(DateTime(2026, 7, 31 - i, 18)),
      ];
      expect(quietDays(txns, now), isEmpty);
    });
  });
}
