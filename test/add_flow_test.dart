import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/features/add/add_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:budgetbox/core/theme.dart';

void main() {
  late LedgerDb db;

  Widget host() {
    return ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ledgerDayTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showAddSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  setUp(() async {
    db = LedgerDb.forTesting(NativeDatabase.memory());
    await AccountRepo(db).create(name: 'Cash', kind: AccountKind.cash);
  });

  tearDown(() => db.close());

  testWidgets('novel entry: amount + category + stamp = a saved transaction',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Keypad is visible on open — no keyboard summon.
    expect(find.text('stamp'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.tap(find.text('8'));
    await tester.tap(find.text('0'));
    await tester.pump();
    expect(find.text('₹180'), findsOneWidget);

    // One chip tap for the category…
    await tester.tap(find.textContaining('Food & chai'));
    await tester.pump();

    // …and the stamp. Five interactions total for a novel entry.
    await tester.tap(find.text('stamp'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.txns).get();
    expect(rows, hasLength(1));
    expect(rows.single.amountPaise, 18000);
    expect(rows.single.type, TxnType.expense);

    // Sheet closed itself; the ledger line is the confirmation.
    expect(find.text('stamp'), findsNothing);
  });

  testWidgets('the running expression: 120 + 60 stamps as ₹180',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final k in ['1', '2', '0', '＋', '6', '0']) {
      await tester.tap(find.text(k));
    }
    await tester.pump();
    expect(find.text('₹180'), findsOneWidget);
    expect(find.text('120 + 60'), findsOneWidget);

    await tester.tap(find.text('stamp'));
    await tester.pumpAndSettle();
    final rows = await db.select(db.txns).get();
    expect(rows.single.amountPaise, 18000);
  });

  testWidgets('stamp is disabled at ₹0 — garbage cannot enter the book',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('stamp'));
    await tester.pumpAndSettle();
    expect(await db.select(db.txns).get(), isEmpty);
    // Sheet stays open, waiting for a real amount.
    expect(find.text('stamp'), findsOneWidget);
  });

  testWidgets('long-press stamps and stays open for the next entry',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2'));
    await tester.tap(find.text('0'));
    await tester.tap(find.textContaining('Food & chai'));
    await tester.pump();
    await tester.longPress(find.text('stamp'));
    await tester.pumpAndSettle();

    expect(await db.select(db.txns).get(), hasLength(1));
    // Still open, amount cleared, category kept for the catch-up session.
    expect(find.text('stamp'), findsOneWidget);
    expect(find.text('₹0'), findsOneWidget);
  });
}
