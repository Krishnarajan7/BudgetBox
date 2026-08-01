import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/focus_repo.dart';
import 'package:budgetbox/features/focus/focus_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FocusRepo', () {
    late LedgerDb db;
    late FocusRepo repo;

    setUp(() {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      repo = FocusRepo(db);
    });

    tearDown(() => db.close());

    test('record writes a line and watchDay keeps to its date', () async {
      final id = await repo.record(
        startedAt: DateTime(2026, 7, 15, 9, 30),
        minutes: 25,
        kind: FocusKind.work,
        completed: true,
        label: 'ledger polish',
      );
      expect(id, greaterThan(0));

      // Neighbouring days must not leak onto the page.
      await repo.record(
        startedAt: DateTime(2026, 7, 14, 23, 50),
        minutes: 45,
        kind: FocusKind.work,
        completed: true,
      );
      await repo.record(
        startedAt: DateTime(2026, 7, 16, 0, 5),
        minutes: 15,
        kind: FocusKind.work,
        completed: true,
      );
      await repo.record(
        startedAt: DateTime(2026, 7, 15, 14, 0),
        minutes: 12,
        kind: FocusKind.work,
        completed: false,
      );

      final day = await repo.watchDay(DateTime(2026, 7, 15, 18, 42)).first;
      expect(day.length, 2);
      expect(day.first.label, 'ledger polish');
      expect(day.first.completed, isTrue);
      expect(day.last.minutes, 12);
      expect(day.last.completed, isFalse);
      // Earliest first — the page reads like the day did.
      expect(day.first.startedAt.isBefore(day.last.startedAt), isTrue);
    });

    test('monthStats counts only completed work sessions', () async {
      // Completed work: 25 + 45 on the 5th, 25 on the 9th.
      await repo.record(
        startedAt: DateTime(2026, 7, 5, 9),
        minutes: 25,
        kind: FocusKind.work,
        completed: true,
      );
      await repo.record(
        startedAt: DateTime(2026, 7, 5, 16),
        minutes: 45,
        kind: FocusKind.work,
        completed: true,
      );
      await repo.record(
        startedAt: DateTime(2026, 7, 9, 11),
        minutes: 25,
        kind: FocusKind.work,
        completed: true,
      );
      // Noise that must not count: abandoned work, completed rest, next month.
      await repo.record(
        startedAt: DateTime(2026, 7, 9, 15),
        minutes: 40,
        kind: FocusKind.work,
        completed: false,
      );
      await repo.record(
        startedAt: DateTime(2026, 7, 5, 10),
        minutes: 5,
        kind: FocusKind.rest,
        completed: true,
      );
      await repo.record(
        startedAt: DateTime(2026, 8, 1, 9),
        minutes: 60,
        kind: FocusKind.work,
        completed: true,
      );

      final stats = await repo.monthStats(DateTime(2026, 7, 20));
      expect(stats.totalMinutes, 95);
      expect(stats.sessions, 3);
      expect(stats.bestDay, DateTime(2026, 7, 5));
      expect(stats.bestDayMinutes, 70);
    });

    test('monthStats on an empty month is all zeroes', () async {
      final stats = await repo.monthStats(DateTime(2026, 6));
      expect(stats.totalMinutes, 0);
      expect(stats.sessions, 0);
      expect(stats.bestDay, isNull);
      expect(stats.bestDayMinutes, 0);
    });
  });

  group('FocusPage', () {
    testWidgets('idle state renders and preset chips move the hero',
        (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const FocusPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Idle: the hero shows the default preset and the Begin button waits.
      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('Begin'), findsOneWidget);
      expect(find.text('one thing at a time'), findsOneWidget);

      // A different preset moves the hero.
      await tester.tap(find.text('15 min'));
      await tester.pump();
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('25:00'), findsNothing);

      await tester.tap(find.text('45 min'));
      await tester.pump();
      expect(find.text('45:00'), findsOneWidget);

      // Let drift's stream machinery wind down before the binding checks
      // for leaked timers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
