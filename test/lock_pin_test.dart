import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The PIN path was never covered: every existing test opens a book with no
/// lock set, so the pad — and the dots that animate as it fills — never ran.
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<LedgerDb> lockedBook() async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    final settings = SettingsRepo(db);
    await settings.markSetupDone();
    await settings.setPin('1234');
    return db;
  }

  testWidgets('the pad fills, the chop stamps, and the book opens',
      (tester) async {
    final db = await lockedBook();
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const BudgetBoxApp(),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The cover is showing its pad, not the tap-to-open handle.
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Tap to open the book'), findsNothing);

    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.text(d));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The way in is three beats now: wink, press, pause.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('today'), findsWidgets);
    await drain(tester);
  });

  testWidgets('a wrong PIN shakes, clears, and still takes the right one',
      (tester) async {
    final db = await lockedBook();
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const BudgetBoxApp(),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    for (final d in ['9', '9', '9', '9']) {
      await tester.tap(find.text(d));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();
    expect(find.text('Not it — try again'), findsOneWidget);

    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.text(d));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
    }
    // The way in is three beats now: wink, press, pause.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('today'), findsWidgets);
    await drain(tester);
  });
}
