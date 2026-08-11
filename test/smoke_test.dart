import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> drain(WidgetTester tester) async {
    // Drift schedules a zero-duration cleanup timer when query streams are
    // cancelled; unmount the tree and elapse the fake clock so the test
    // binding doesn't flag it as leaked.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a truly blank book opens into the setup ritual',
      (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const BudgetBoxApp(),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('This book belongs to…'), findsOneWidget);
    expect(find.text('Write it in'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('splash → lock → shell with all four pages', (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // A book that's been through the ritual already.
    await SettingsRepo(db).markSetupDone();

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const BudgetBoxApp(),
    ));
    expect(find.text('BudgetBox'), findsOneWidget);

    // The opening plays out and hands off to the cover page. No PIN is set,
    // so the cover offers a plain open.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Tap to open the book'), findsOneWidget);

    await tester.tap(find.text('Tap to open the book'));
    // The unlock is a choreography: stamp animation (380ms), a beat (260ms),
    // then the shell fades up. Each pump advances the fake clock even when
    // no frame is scheduled, so the beat's timer actually fires.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('today'), findsWidgets);
    expect(find.byIcon(Icons.add), findsOneWidget);

    // Walk the spine: Book, Plans, Worth all render.
    await tester.tap(find.text('book'));
    await tester.pumpAndSettle();
    expect(find.textContaining('heat'), findsOneWidget);

    await tester.tap(find.text('plans'));
    await tester.pumpAndSettle();
    expect(find.text('budgets'), findsOneWidget);

    await tester.tap(find.text('worth'));
    await tester.pumpAndSettle();
    // This book has no accounts, so Worth shows its blank page rather than a
    // hero of nothing. Either way the book's own title is on it.
    expect(find.text('Worth'), findsOneWidget);
    expect(find.textContaining('Nothing on the shelf'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('the ritual persists a real book and lands on the lock',
      (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const BudgetBoxApp(),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Walk the eight pages with the defaults.
    for (final cta in [
      'Write it in', 'Next', 'Next', 'Next',
      'Looks about right', 'Keep this goal', 'Lock it down',
    ]) {
      await tester.tap(find.text(cta));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Open the book'));
    await tester.pumpAndSettle();

    // Landed on the cover; the book behind it is real.
    expect(find.text('Tap to open the book'), findsOneWidget);
    expect(await db.select(db.accounts).get(), isNotEmpty);
    expect(await db.select(db.budgets).get(), hasLength(6));
    expect(await db.select(db.goals).get(), hasLength(1));
    expect(await SettingsRepo(db).setupDone(), isTrue);

    await drain(tester);
  });
}
