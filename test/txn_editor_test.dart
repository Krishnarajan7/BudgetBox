import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/book/txn_editor.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LedgerDb db;
  late Txn txn;

  Widget host() {
    return ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ledgerDayTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showTxnEditor(context, txn),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<int> balance() async =>
      (await db.select(db.accounts).get()).single.balancePaise;

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  setUp(() async {
    db = LedgerDb.forTesting(NativeDatabase.memory());
    final accountId = await AccountRepo(db).create(
      name: 'Cash',
      kind: AccountKind.cash,
      openingBalancePaise: 100000, // ₹1,000
    );
    final cats = await db.select(db.categories).get();
    final food = cats.firstWhere((c) => c.kind == CategoryKind.expense);
    final txnId = await TxnRepo(db).addExpense(
      amountPaise: 18000, // ₹180
      accountId: accountId,
      categoryId: food.id,
      title: 'Chai',
    );
    txn = (await db.select(db.txns).get())
        .firstWhere((t) => t.id == txnId);
  });

  tearDown(() => db.close());

  testWidgets('rewriting the title stamps it again and moves no money',
      (tester) async {
    expect(await balance(), 82000); // ₹1,000 − ₹180

    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The sheet opens on the entry as it stands.
    expect(find.text('₹180'), findsOneWidget);
    expect(find.text('Chai'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('title-field')), 'Filter coffee');
    await tester.tap(find.text('Stamp it again'));
    await tester.pumpAndSettle();

    // Sheet closed itself; the corrected line is the confirmation.
    expect(find.text('Stamp it again'), findsNothing);

    final rows = await db.select(db.txns).get();
    expect(rows, hasLength(1));
    expect(rows.single.title, 'Filter coffee');
    expect(rows.single.amountPaise, 18000);
    expect(rows.single.categoryId, txn.categoryId);

    // Same amount, same account — the balance must not move.
    expect(await balance(), 82000);

    await drain(tester);
  });

  testWidgets('rewriting the amount adjusts the account balance',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tap the hero amount to edit it inline.
    await tester.tap(find.text('₹180'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('amount-field')), '250');
    await tester.tap(find.text('Stamp it again'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.txns).get();
    expect(rows.single.amountPaise, 25000);

    // Old stroke reversed, new one applied: ₹1,000 − ₹250.
    expect(await balance(), 75000);

    await drain(tester);
  });

  testWidgets('strike it out deletes the entry and restores the balance',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('strike it out'));
    await tester.pumpAndSettle();

    expect(find.text('Stamp it again'), findsNothing);
    expect(await db.select(db.txns).get(), isEmpty);
    expect(await balance(), 100000);

    await drain(tester);
  });
}
