import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shelf opens a dialog route and then pushes a module route from the
/// same (just-popped) context. Nothing covered that path before.
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> openBook(WidgetTester tester, LedgerDb db) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const BudgetBoxApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // No PIN, no cover: the book opens itself straight onto the shell.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  for (final spine in ['Calendar', 'Notes', 'Focus', 'Journal', 'Vault']) {
    testWidgets('the shelf opens $spine and comes back', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await SettingsRepo(db).markSetupDone();
      await openBook(tester, db);

      // Tap the wordmark: the box opens.
      await tester.tap(find.text('Krish Space'));
      await tester.pumpAndSettle();
      expect(find.text('the box'), findsOneWidget);

      await tester.tap(find.text(spine));
      await tester.pumpAndSettle();

      // Back out to the shell again.
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.pop();
      await tester.pumpAndSettle();

      await drain(tester);
    });
  }

  testWidgets('tapping a spine before its ink has settled', (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await SettingsRepo(db).markSetupDone();
    await openBook(tester, db);

    await tester.tap(find.text('Krish Space'));
    // Deliberately do NOT settle — the spines stagger in over ~180ms and the
    // last one is still fading when a fast hand reaches it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    await tester.tap(find.text('Vault'), warnIfMissed: false);
    await tester.pumpAndSettle();

    await drain(tester);
  });

  testWidgets('the Money spine pops back to the root shell', (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await SettingsRepo(db).markSetupDone();
    await openBook(tester, db);

    // Open a book first so there is something to pop back through.
    await tester.tap(find.text('Krish Space'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Journal'));
    await tester.pumpAndSettle();

    // Module pages carry their own bar, so reach the shelf from the shell:
    // pop back, then take the Money spine, which runs popUntil(isFirst).
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Krish Space'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Money'));
    await tester.pumpAndSettle();
    expect(find.text('today'), findsWidgets);

    await drain(tester);
  });
}
