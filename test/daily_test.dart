import 'package:budgetbox/core/feel.dart';
import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/focus_repo.dart';
import 'package:budgetbox/data/repos/habit_repo.dart';
import 'package:budgetbox/data/repos/marks_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/daily/daily_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the checklist', () {
    late LedgerDb db;
    late HabitRepo repo;

    setUp(() {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      repo = HabitRepo(db);
    });
    tearDown(() => db.close());

    test('an untouched book reads back the starting habits', () async {
      expect(await repo.load(), startingHabits);
      // …without having written anything, so the default can still change.
      expect(await db.select(db.settings).get(), isEmpty);
    });

    test('a new habit gets a key from its name, never a reused one', () async {
      final reading = await repo.add(name: 'Reading');
      expect(reading.kind, 'reading');
      final second = await repo.add(name: 'Reading');
      expect(second.kind, 'reading2');
      // Retiring the first still doesn't free its key — history keeps it.
      await repo.update('reading', archived: true);
      final third = await repo.add(name: 'reading');
      expect(third.kind, 'reading3');
    });

    test('a counted habit keeps its target and unit', () async {
      await repo.add(name: 'Water', target: 8, unit: 'glasses');
      final water = (await repo.load()).last;
      expect(water.counted, isTrue);
      expect(water.target, 8);
      expect(water.unit, 'glasses');

      // Turned back into a tick, the unit goes with it.
      await repo.update(water.kind, target: 1);
      final ticked = (await repo.load()).last;
      expect(ticked.counted, isFalse);
      expect(ticked.unit, isNull);
    });

    test('retiring a habit leaves the marks alone', () async {
      final marks = MarksRepo(db);
      final day = DateTime(2026, 8, 13);
      await repo.save(const [Habit(kind: 'bath', name: 'Bath')]);
      await marks.toggle(day, 'bath');
      await repo.update('bath', archived: true);

      expect((await repo.load()).single.archived, isTrue);
      expect((await marks.watchDay(day).first).single.kind, 'bath');
    });

    test('a corrupted row falls back rather than losing the list', () async {
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion(
              key: const Value('habits'),
              value: const Value('{ not json at all'),
            ),
          );
      expect(await repo.load(), startingHabits);
    });
  });

  group('DailyPage', () {
    late LedgerDb db;

    setUp(() => db = LedgerDb.forTesting(NativeDatabase.memory()));

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          // Reduced motion: the felt field's ambient drift never settles,
          // and these tests are about behaviour, not choreography.
          child: MaterialApp(
            theme: ledgerNightTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const DailyPage(),
          ),
        ),
      );
      // Drift delivers its first rows on a timer; settling alone never
      // fires it, so the page would still be reading its defaults.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    /// Brings a section into view — the page is long, and a ListView never
    /// builds what it hasn't reached.
    Future<void> scrollTo(WidgetTester tester, String header) async {
      await tester.scrollUntilVisible(
        find.text(header),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    /// Unmounts and drains drift's timers so the binding ends clean.
    Future<void> settle(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await db.close();
    }

    testWidgets('the day leads with the clean count and the checklist',
        (tester) async {
      await pump(tester);

      expect(find.text('clean streak'), findsOneWidget);
      expect(find.text('day 1'), findsOneWidget);
      for (final habit in ['Bath', 'Running', 'Water']) {
        expect(find.text(habit), findsOneWidget);
      }
      // Water is the counted one: it arrives at none of its eight.
      expect(find.text('0/8'), findsOneWidget);
      expect(find.text('0 of 6'), findsOneWidget);

      await settle(tester);
    });

    testWidgets('tapping a habit keeps it, and the day says so',
        (tester) async {
      await pump(tester);

      await tester.tap(find.text('Bath'));
      await tester.pumpAndSettle();

      // The count on the header and the hero's line both come back through
      // the database's stream, so seeing them is seeing the write land.
      expect(find.text('1 of 6'), findsOneWidget);
      expect(find.textContaining('1 of 6 kept to-day'), findsOneWidget);

      await settle(tester);
    });

    testWidgets('water opens the vessel and fills a glass at a time',
        (tester) async {
      await pump(tester);

      // Water gets its own room instead of a quick mark.
      await scrollTo(tester, 'Water');
      await tester.tap(find.text('Water'));
      await tester.pumpAndSettle();
      expect(find.text('add a glass'), findsOneWidget);
      // The goal reads in millilitres now, against the day's bottle.
      expect(find.text('of a 750ml bottle ›'), findsOneWidget);

      await tester.tap(find.text('add a glass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('add a glass'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget); // the big count
      expect(find.text('25%'), findsOneWidget); // 2 of 8
      expect(find.text('188ml'), findsOneWidget); // 2 × 750/8, rounded

      // One can always be taken back.
      await tester.tap(find.text('take one back'));
      await tester.pumpAndSettle();
      expect(find.text('13%'), findsOneWidget);

      // Closing the room, the day's row carries the count.
      await tester.tap(find.byKey(const ValueKey('water-close')));
      await tester.pumpAndSettle();
      expect(find.text('1/8'), findsOneWidget);

      await settle(tester);
    });

    testWidgets('the ninth glass tips the bottle onto the shelf',
        (tester) async {
      await pump(tester);

      await scrollTo(tester, 'Water');
      await tester.tap(find.text('Water'));
      await tester.pumpAndSettle();

      // Seven glasses in: still pouring.
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.text('add a glass'));
        await tester.pumpAndSettle();
      }
      expect(find.text('bottle down'), findsNothing);

      // The eighth fills the bottle — it stands full, not reset.
      await tester.tap(find.text('add a glass'));
      await tester.pumpAndSettle();
      expect(
        find.text('the bottle is full — the next glass tips it.'),
        findsOneWidget,
      );
      expect(find.text('bottle down'), findsNothing);

      // The ninth tips it: one finished bottle on the shelf, the vessel
      // holding one glass of the next, the day still counting all nine.
      await tester.tap(find.text('add a glass'));
      await tester.pumpAndSettle();
      expect(find.text('bottle down'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('844ml'), findsOneWidget); // 9 × 750/8, rounded

      // The day's row folds the count into bottles, never "9 of 8".
      await tester.tap(find.byKey(const ValueKey('water-close')));
      await tester.pumpAndSettle();
      expect(find.text('+1 · 1 of 8'), findsOneWidget);

      await settle(tester);
    });

    testWidgets('yesterday can be opened and filled in', (tester) async {
      await pump(tester);

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await tester.tap(find.text(yesterday.day.toString()).first);
      await tester.pumpAndSettle();

      // The hero steps aside for the day being looked at.
      expect(find.text('clean streak'), findsNothing);
      expect(find.textContaining('that day'), findsWidgets);

      await tester.tap(find.text('Bath'));
      await tester.pumpAndSettle();

      // Yesterday now carries a kept habit of its own.
      expect(find.text('1 of 6'), findsWidgets);
      // …and the timeline stamps it at midday, the hour the book won't
      // pretend to know. (See marks_test for the write itself.)
      expect(find.text('12:00'), findsWidgets);

      await settle(tester);
    });

    testWidgets('what the day contained is gathered from the other books',
        (tester) async {
      final account = await AccountRepo(db).create(
        name: 'Cash',
        kind: AccountKind.cash,
      );
      final now = DateTime.now();
      await TxnRepo(db).addExpense(
        amountPaise: 4000,
        accountId: account,
        title: 'chai at the corner',
        at: DateTime(now.year, now.month, now.day, 9, 30),
      );
      await FocusRepo(db).record(
        startedAt: DateTime(now.year, now.month, now.day, 10),
        minutes: 25,
        kind: FocusKind.work,
        completed: true,
        label: 'the backend',
      );
      await MarksRepo(db).addMeal(now, 'idli');

      await pump(tester);
      await scrollTo(tester, 'the day so far');

      // Thread rows carry their source word inside the same line — "chai at
      // the corner  spent" — so they read as one sentence, not a table.
      expect(find.text('the day so far'), findsOneWidget);
      expect(find.textContaining('chai at the corner  spent'), findsOneWidget);
      // The amount is on the thread line and, set big, on the day's numbers.
      expect(find.text('₹40'), findsWidgets);
      expect(find.textContaining('the backend  25m sat'), findsOneWidget);
      expect(find.textContaining('idli'), findsWidgets);
      expect(find.text('09:30'), findsOneWidget);

      await settle(tester);
    });

    testWidgets('the check-in ring opens the picker and marks the day',
        (tester) async {
      await pump(tester);

      // An unmarked to-day wears the ring in the page's top corner.
      await tester.tap(find.byKey(const ValueKey('felt-mark')));
      await tester.pumpAndSettle();
      expect(find.text('how did the day sit?'), findsOneWidget);

      // Press a word in the cloud; its meaning surfaces in the pill.
      await tester.tap(find.text('steady'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('holding a straight line'), findsOneWidget);

      // The arrow marks the day and turns the page to the second breath.
      await tester.tap(find.byKey(const ValueKey('feel-save')));
      await tester.pumpAndSettle();
      expect(find.text('what were you doing?'), findsOneWidget);

      // The word is already in the book before any of this is answered.
      var entry = await (db.select(db.journalEntries)).getSingle();
      expect(entry.feelWord, 'steady');
      expect(entry.mood, snap9(0.62));
      expect(entry.energy, snap9(0.50));

      // A couple of chips and one line of why, then complete.
      await tester.tap(find.text('building'));
      await tester.tap(find.text('alone'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'kept a straight line all day',
      );
      await tester.tap(find.byKey(const ValueKey('feel-complete')));
      await tester.pumpAndSettle();

      entry = await (db.select(db.journalEntries)).getSingle();
      expect(entry.feelTags, 'building,alone');
      expect(entry.feelWhy, 'kept a straight line all day');

      // The page section now wears the word and offers the way back in —
      // and says the rest of the check-in back instead of swallowing it.
      await scrollTo(tester, 'the page');
      expect(find.text('steady'), findsOneWidget);
      expect(find.text('re-mark'), findsOneWidget);
      expect(
        find.text('building · alone — kept a straight line all day'),
        findsOneWidget,
      );

      await settle(tester);
    });
  });
}
