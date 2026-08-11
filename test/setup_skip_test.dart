import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/features/setup/setup_flow.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nothing the ritual asks is load-bearing — every answer has a default and
/// lives in Settings afterwards. Someone who does not yet have an opinion
/// should be able to say so.
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<LedgerDb> openRitual(WidgetTester tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ledgerDayTheme(),
        home: const SetupFlow(real: true),
      ),
    ));
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('every question offers a way past it', (tester) async {
    await openRitual(tester);

    // Seven questions, then the closing page — which has nothing past it.
    for (var i = 0; i < 7; i++) {
      expect(find.text('skip — you can change this later in Settings'),
          findsOneWidget,
          reason: 'page $i should be skippable');
      await tester.tap(find.text('skip — you can change this later in Settings'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Open the book'), findsOneWidget);
    expect(find.text('skip — you can change this later in Settings'),
        findsNothing);
    await drain(tester);
  });

  testWidgets('skip all jumps straight to the closing page', (tester) async {
    await openRitual(tester);

    expect(find.text('skip all'), findsOneWidget);
    await tester.tap(find.text('skip all'));
    await tester.pumpAndSettle();

    expect(find.text('Open the book'), findsOneWidget);
    // Nothing left to skip past.
    expect(find.text('skip all'), findsNothing);
    await drain(tester);
  });

  testWidgets('skipping everything still writes a usable book',
      (tester) async {
    final db = await openRitual(tester);

    await tester.tap(find.text('skip all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the book'));
    await tester.pumpAndSettle();

    // The defaults are real: an account to write against, budgets to spend
    // from, and a book that knows its ritual is done.
    expect(await db.select(db.accounts).get(), isNotEmpty);
    expect(await db.select(db.budgets).get(), isNotEmpty);
    expect(await SettingsRepo(db).setupDone(), isTrue);

    // Skipped the lock, so the cover opens on a tap rather than a PIN.
    expect(await SettingsRepo(db).hasPin(), isFalse);
    await drain(tester);
  });

  testWidgets('the lock page no longer promises there is no server',
      (tester) async {
    await openRitual(tester);

    // Six skips lands on 'lock it down', the page that used to claim nothing
    // ever left the phone.
    for (var i = 0; i < 6; i++) {
      await tester
          .tap(find.text('skip — you can change this later in Settings'));
      await tester.pumpAndSettle();
    }
    expect(find.text('This book locks.'), findsOneWidget);

    expect(find.textContaining('there is no cloud to leak from'), findsNothing,
        reason: 'the book has a server now; that promise was a lie');
    expect(find.textContaining('never sent to your server'), findsOneWidget);
    await drain(tester);
  });
}
