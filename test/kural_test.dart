import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/features/kural/kural_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a seeded cycle is shuffled, deterministic, and has no repeats', () {
    final first = shuffledKuralOrder(kuralCount, 424242);
    final again = shuffledKuralOrder(kuralCount, 424242);
    final another = shuffledKuralOrder(kuralCount, 99);

    expect(first, again);
    expect(first.toSet(), hasLength(kuralCount));
    expect(first.toSet(), equals({for (var i = 0; i < kuralCount; i++) i}));
    expect(first, isNot(equals(List<int>.generate(kuralCount, (i) => i))));
    expect(another, isNot(equals(first)));
  });

  test(
    'the reading streak counts consecutive days and resets on a gap',
    () async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final s = SettingsRepo(db);

      expect(await s.bumpKuralStreak('2026-08-12', null), 1);
      expect(await s.bumpKuralStreak('2026-08-13', '2026-08-12'), 2);
      // A missed day starts over — quietly, no shaming copy anywhere.
      expect(await s.bumpKuralStreak('2026-08-16', '2026-08-13'), 1);
    },
  );

  test(
    'progress advances only on completion and completion is idempotent',
    () async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final s = SettingsRepo(db);
      expect(await s.kuralIndex(), 0);

      expect(await s.previewKuralStreak('2026-08-12', null), 1);
      expect(await s.kuralDay(), isNull, reason: 'a preview earns nothing');
      expect(await s.kuralIndex(), 0);

      await s.completeDailyKural(
        '2026-08-12',
        expectedPosition: 0,
        total: kuralCount,
      );
      expect(await s.kuralDay(), '2026-08-12');
      expect(await s.kuralIndex(), 1);

      await s.completeDailyKural(
        '2026-08-12',
        expectedPosition: 0,
        total: kuralCount,
      );
      expect(await s.kuralIndex(), 1, reason: 'a double tap cannot skip one');
    },
  );

  test('the owner\'s day steps outside the shuffle and costs it nothing',
      () async {
    // Only the one morning, and never the same page two years running.
    expect(ownersDayKuralIndex(DateTime(2026, 8, 18)), isNotNull);
    expect(
      ownersDayKuralIndex(DateTime(2027, 8, 18)),
      isNot(ownersDayKuralIndex(DateTime(2026, 8, 18))),
    );
    expect(ownersDayKuralIndex(DateTime(2026, 8, 17)), isNull);
    expect(ownersDayKuralIndex(DateTime(2026, 8, 19)), isNull);
    expect(ownersDayKuralIndex(DateTime(2026, 9, 18)), isNull);

    // Completing without advancing: the day is read, the streak counts,
    // and the verse standing at to-day's position waits for to-morrow.
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final s = SettingsRepo(db);
    await s.completeDailyKural(
      '2026-08-17',
      expectedPosition: 0,
      total: kuralCount,
    );
    expect(await s.kuralPosition(), 1);

    final streak = await s.completeDailyKural(
      '2026-08-18',
      expectedPosition: 1,
      total: kuralCount,
      advance: false,
    );
    expect(streak, 2, reason: 'the special page still keeps the flame');
    expect(await s.kuralDay(), '2026-08-18');
    expect(await s.kuralPosition(), 1, reason: 'the cycle did not move');

    await s.completeDailyKural(
      '2026-08-19',
      expectedPosition: 1,
      total: kuralCount,
    );
    expect(await s.kuralPosition(), 2, reason: 'the shuffle resumes intact');
  });

  test('finishing a cycle resets its position and rotates its seed', () async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final s = SettingsRepo(db);
    final before = await s.kuralCycleSeed();

    await s.completeDailyKural('2026-08-12', expectedPosition: 0, total: 1);

    expect(await s.kuralPosition(), 0);
    expect(await s.kuralCycleSeed(), isNot(before));
  });

  testWidgets('the page carries the couplet, the urai, and the words', (
    tester,
  ) async {
    // Asset IO is real IO — run it outside the fake clock.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ledgerDayTheme(),
          home: const KuralPage(index: 0, streak: 3),
        ),
      );
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

  testWidgets('படித்தேன் plays the streak moment, then the page leaves', (
    tester,
  ) async {
    var completed = false;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ledgerDayTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => KuralPage(
                        index: 0,
                        streak: 2,
                        onRead: () async => completed = true,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    // The scripture loads over real IO — wait until the page has built.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (find.byType(Scrollable).evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('படித்தேன்'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(completed, isFalse, reason: 'opening the page is not reading it');
    await tester.tap(find.textContaining('படித்தேன்'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(completed, isTrue);

    // Mid-hold: the banner is down, the seal has bloomed.
    expect(find.text('day 2 of your reading streak'), findsOneWidget);

    // The moment finishes and closes the page itself.
    await tester.pumpAndSettle();
    expect(find.text('day 2 of your reading streak'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
