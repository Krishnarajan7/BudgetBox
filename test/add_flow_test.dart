import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
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

  testWidgets('novel entry: amount + category + stamp = a saved transaction', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Keypad is visible on open — no keyboard summon.
    expect(find.text('stamp'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.tap(find.text('8'));
    await tester.tap(find.text('0'));
    await tester.pump();
    // Extra frames: the hero amount counts up over 160ms before it settles.
    await tester.pump(const Duration(milliseconds: 200));
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

  testWidgets('the running expression: 120 + 60 stamps as ₹180', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final k in ['1', '2', '0', '+', '6', '0']) {
      await tester.tap(find.text(k));
    }
    await tester.pump();
    // Extra frames: the hero amount counts up over 160ms before it settles.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('₹180'), findsOneWidget);
    expect(find.text('120 + 60'), findsOneWidget);

    await tester.tap(find.text('stamp'));
    await tester.pumpAndSettle();
    final rows = await db.select(db.txns).get();
    expect(rows.single.amountPaise, 18000);
  });

  testWidgets('stamp is disabled at ₹0 — garbage cannot enter the book', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('stamp'));
    await tester.pumpAndSettle();
    expect(await db.select(db.txns).get(), isEmpty);
    // Sheet stays open, waiting for a real amount.
    expect(find.text('stamp'), findsOneWidget);
  });

  testWidgets('details opens a note that rides along with the entry', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The note does not exist until asked for — the core path pays nothing.
    expect(find.byKey(const ValueKey('add-note-field')), findsNothing);

    await tester.tap(find.text('details ›'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-note-field')),
      'split with A',
    );

    await tester.tap(find.text('4'));
    await tester.tap(find.text('0'));
    await tester.pump();
    await tester.tap(find.text('stamp'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.txns).get();
    expect(rows.single.note, 'split with A');
  });

  testWidgets('the recents whisper writes a habitual amount in one tap', (
    tester,
  ) async {
    final food = await (db.select(
      db.categories,
    )..where((c) => c.name.equals('Food & chai'))).getSingle();
    final account = await (db.select(db.accounts)..limit(1)).getSingle();
    for (var i = 0; i < 2; i++) {
      await TxnRepo(db).addExpense(
        amountPaise: 12000,
        accountId: account.id,
        categoryId: food.id,
        title: 'Chai',
      );
    }

    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Food & chai'));
    await tester.pumpAndSettle();

    // A whisper, not a step: it offers the figure the category usually takes.
    expect(find.text('usually'), findsOneWidget);
    await tester.tap(find.text('₹120'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // Now in two places: the hero, and the whisper it came from.
    expect(find.text('₹120'), findsNWidgets(2));
  });

  testWidgets('long-press stamps and stays open for the next entry', (
    tester,
  ) async {
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

  testWidgets('the money-in flip writes income, and the balance rises', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // ₹600 in — flipped BEFORE stamping. This exact path once recorded a
    // deposit as spending, turning −₹500 into −₹1,100 instead of +₹100.
    await tester.tap(find.text('spent'));
    await tester.pump();
    expect(find.text('money in'), findsOneWidget);
    expect(find.text('what kind of income?'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Extra income'), findsOneWidget);
    expect(find.text('Food & chai'), findsNothing);
    expect(find.text('where did it come from? (optional)'), findsOneWidget);
    expect(find.text('into'), findsOneWidget);

    await tester.tap(find.text('6'));
    await tester.tap(find.text('0'));
    await tester.tap(find.text('0'));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('stamp'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final txns = await db.select(db.txns).get();
    expect(txns.single.type, TxnType.income);
    expect(txns.single.amountPaise, 60000);
    final acct = (await db.select(db.accounts).get()).single;
    expect(acct.balancePaise, 60000, reason: 'money in raises the pocket');
  });
}
