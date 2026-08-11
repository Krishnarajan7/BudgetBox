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

  group('focus arithmetic', () {
    test('weekWorkMinutes buckets Mon–Sun and ignores other weeks', () {
      final anchor = DateTime(2026, 7, 31); // a Friday
      final bars = weekWorkMinutes([
        (DateTime(2026, 7, 27, 9), 25), // Mon
        (DateTime(2026, 7, 27, 15), 20), // Mon again — sums
        (DateTime(2026, 7, 31, 10), 45), // Fri
        (DateTime(2026, 8, 2, 10), 15), // Sun, same week
        (DateTime(2026, 7, 26, 10), 60), // previous Sunday — out
        (DateTime(2026, 8, 3, 10), 30), // next Monday — out
      ], anchor);
      expect(bars, [45, 0, 0, 0, 45, 0, 15]);
    });

    test('an empty week is seven zeroes', () {
      expect(
          weekWorkMinutes(const [], DateTime(2026, 7, 31)), List.filled(7, 0));
    });

    test('a gap breaks the streak', () {
      expect(
        focusStreakDays([
          DateTime(2026, 7, 31),
          DateTime(2026, 7, 30),
          DateTime(2026, 7, 28), // gap on the 29th
        ], DateTime(2026, 7, 31)),
        2,
      );
    });

    test('a run ending yesterday still counts', () {
      expect(
        focusStreakDays([DateTime(2026, 7, 30), DateTime(2026, 7, 29)],
            DateTime(2026, 7, 31)),
        2,
      );
    });

    test('today alone is a one-day run; colder runs are none', () {
      expect(
          focusStreakDays([DateTime(2026, 7, 31)], DateTime(2026, 7, 31)), 1);
      expect(
        focusStreakDays([DateTime(2026, 7, 28), DateTime(2026, 7, 27)],
            DateTime(2026, 7, 31)),
        0,
      );
      expect(focusStreakDays(const <DateTime>[], DateTime(2026, 7, 31)), 0);
    });

    test('the streak reads across a month boundary', () {
      expect(
        focusStreakDays(
            [DateTime(2026, 8, 1), DateTime(2026, 7, 31)], DateTime(2026, 8, 1)),
        2,
      );
    });

    test('focusRecord folds totals, longest, best day, and streak', () {
      final r = focusRecord([
        (DateTime(2026, 7, 30, 9), 25),
        (DateTime(2026, 7, 30, 11), 47),
        (DateTime(2026, 7, 31, 9), 30),
        (DateTime(2026, 6, 12, 9), 47), // ties the longest — earlier wins
      ], DateTime(2026, 7, 31));
      expect(r.totalMinutes, 149);
      expect(r.sessions, 4);
      expect(r.longestMinutes, 47);
      expect(r.longestAt, DateTime(2026, 6, 12, 9));
      expect(r.bestDay, DateTime(2026, 7, 30));
      expect(r.bestDayMinutes, 72);
      expect(r.streakDays, 2);
    });

    test('an empty record is all zeroes and no dates', () {
      final r = focusRecord(const [], DateTime(2026, 7, 31));
      expect(r.totalMinutes, 0);
      expect(r.sessions, 0);
      expect(r.longestMinutes, 0);
      expect(r.longestAt, isNull);
      expect(r.bestDay, isNull);
      expect(r.streakDays, 0);
    });

    test('presets read from settings, defaulting per key', () {
      expect(focusPresetsFromSettings(const {}), [15, 25, 45]);
      expect(
        focusPresetsFromSettings(
            const {'focusPreset1': '20', 'focusPreset3': '90'}),
        [20, 25, 90],
      );
      expect(
          focusPresetsFromSettings(const {'focusPreset2': 'junk'}), [15, 25, 45]);
      expect(focusPresetsFromSettings(const {'focusPreset2': '0'}), [15, 25, 45]);
    });
  });

  group('FocusPage sections', () {
    Widget host(LedgerDb db) => ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(theme: ledgerDayTheme(), home: const FocusPage()),
        );

    Future<void> drain(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('the week bars and the record read from the book',
        (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FocusRepo(db);
      final now = DateTime.now();
      await repo.record(
        startedAt: DateTime(now.year, now.month, now.day, 9),
        minutes: 25,
        kind: FocusKind.work,
        completed: true,
      );
      await repo.record(
        startedAt: DateTime(now.year, now.month, now.day - 1, 10),
        minutes: 47,
        kind: FocusKind.work,
        completed: true,
      );

      await tester.pumpWidget(host(db));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('this week'), findsOneWidget);
      expect(find.text('the record'), findsOneWidget);
      expect(find.text('focused, all-time'), findsOneWidget);
      expect(find.text('sittings'), findsOneWidget);
      expect(find.text('longest sitting'), findsOneWidget);
      expect(find.text('best day'), findsOneWidget);
      expect(find.text('the streak'), findsOneWidget);
      expect(find.text('1h 12m'), findsOneWidget); // 72 minutes, all-time
      expect(find.text('2 days running'), findsOneWidget);
      // The idle line under the timer keeps the thread in sight.
      expect(find.text('2 days running — keep the thread.'), findsOneWidget);

      await drain(tester);
    });

    testWidgets('an untouched book keeps the record quiet', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(host(db));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('nothing on the record yet.'), findsOneWidget);
      expect(find.textContaining('keep the thread'), findsNothing);

      await drain(tester);
    });

    testWidgets('long-press edits a preset chip and persists it',
        (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(host(db));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.longPress(find.text('25 min'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('preset-minutes')), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('preset-minutes')), '30');
      await tester.tap(find.text('Keep'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('25 min'), findsNothing);
      expect(find.text('30:00'), findsOneWidget);

      final row = await (db.select(db.settings)
            ..where((s) => s.key.equals('focusPreset2')))
          .getSingleOrNull();
      expect(row?.value, '30');

      await drain(tester);
    });

    testWidgets('edited presets come back on the next open', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: 'focusPreset1', value: '20'));

      await tester.pumpWidget(host(db));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('20 min'), findsOneWidget);
      expect(find.text('15 min'), findsNothing);

      await drain(tester);
    });
  });
}
