import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/features/kural/kural_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the reading streak counts consecutive days and resets on a gap',
      () async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final s = SettingsRepo(db);

    expect(await s.bumpKuralStreak('2026-08-12', null), 1);
    expect(await s.bumpKuralStreak('2026-08-13', '2026-08-12'), 2);
    // A missed day starts over — quietly, no shaming copy anywhere.
    expect(await s.bumpKuralStreak('2026-08-16', '2026-08-13'), 1);
  });

  test('the sequence walks forward and never repeats within a cycle',
      () async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final s = SettingsRepo(db);
    expect(await s.kuralIndex(), 0);
    await s.setKuralShown('2026-08-12', 1);
    expect(await s.kuralDay(), '2026-08-12');
    expect(await s.kuralIndex(), 1);
  });

  testWidgets('the page carries the couplet, the urai, and the words',
      (tester) async {
    // Asset IO is real IO — run it outside the fake clock.
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        theme: ledgerDayTheme(),
        home: const KuralPage(index: 0, streak: 3),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    // Kural 1, with its curated vocabulary.
    expect(find.textContaining('அகர முதல'), findsOneWidget);
    expect(find.text('திருக்குறள் 1'), findsOneWidget);
    expect(find.text('பொருள்'), findsOneWidget);
    expect(find.text('சொற்கள்'), findsOneWidget);
    expect(find.text('day 3 of reading'), findsOneWidget);
    expect(find.textContaining('1329 left in the book'), findsOneWidget);
  });

  testWidgets('படித்தேன் plays the streak moment, then the page leaves',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        theme: ledgerDayTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const KuralPage(index: 0, streak: 2)),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    // The scripture loads over real IO — wait until the page has built.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      if (find.byType(Scrollable).evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
        find.textContaining('படித்தேன்'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.textContaining('படித்தேன்'));
    await tester.pump(const Duration(milliseconds: 600));

    // Mid-hold: the banner is down, the seal has bloomed.
    expect(find.text('day 2 of your reading streak'), findsOneWidget);

    // The moment finishes and closes the page itself.
    await tester.pumpAndSettle();
    expect(find.text('day 2 of your reading streak'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
