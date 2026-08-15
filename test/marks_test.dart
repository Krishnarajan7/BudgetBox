import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/habit_repo.dart';
import 'package:budgetbox/data/repos/marks_repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the clean count', () {
    final today = DateTime(2026, 8, 13);

    test('no slips since tracking began counts every day, today included', () {
      expect(cleanStreak({}, '2026-08-10', today), 4);
      expect(bestCleanRun({}, '2026-08-10', today), 4);
    });

    test('day one of tracking is already day 1 clean', () {
      expect(cleanStreak({}, '2026-08-13', today), 1);
    });

    test('a slip to-day drops the streak to zero', () {
      expect(cleanStreak({'2026-08-13'}, '2026-08-01', today), 0);
    });

    test('the streak counts from the day after the last slip', () {
      expect(cleanStreak({'2026-08-10'}, '2026-08-01', today), 3);
    });

    test('the best run remembers an older, longer stretch', () {
      // Clean 1st–9th (9 days), slip on the 10th, clean 11th–13th (3 days).
      final slips = {'2026-08-10'};
      expect(cleanStreak(slips, '2026-08-01', today), 3);
      expect(bestCleanRun(slips, '2026-08-01', today), 9);
    });

    test('days before tracking began are never claimed', () {
      expect(cleanStreak({}, '2026-08-13', DateTime(2026, 8, 13)), 1);
      expect(bestCleanRun({'2026-08-12'}, '2026-08-12', today), 1);
    });
  });

  group('counted habits', () {
    const water = Habit(kind: 'water', name: 'Water', target: 8);
    final today = DateTime(2026, 8, 13);

    List<DayMark> marksFor(Map<String, int> byDate) => [
      for (final e in byDate.entries)
        for (var i = 0; i < e.value; i++)
          DayMark(id: 0, date: e.key, kind: 'water', at: DateTime(2026)),
    ];

    test('a day counts only once it reaches the target', () {
      final marks = marksFor({'2026-08-13': 7, '2026-08-12': 8});
      expect(countOn(marks, '2026-08-13', 'water'), 7);
      expect(daysKept(marks, water), {'2026-08-12'});
    });

    test('an open to-day does not break the run, and does not extend it', () {
      // Kept on the 11th and 12th; to-day is only part of the way there.
      final marks = marksFor({
        '2026-08-11': 8,
        '2026-08-12': 8,
        '2026-08-13': 3,
      });
      expect(keptRun(daysKept(marks, water), today), 2);
      // Finish to-day and the run counts it.
      final done = marksFor({
        '2026-08-11': 8,
        '2026-08-12': 8,
        '2026-08-13': 8,
      });
      expect(keptRun(daysKept(done, water), today), 3);
    });

    test('a missed yesterday ends the run at zero', () {
      final marks = marksFor({'2026-08-11': 8});
      expect(keptRun(daysKept(marks, water), today), 0);
    });

    test('the longest run is found anywhere in the window', () {
      final dates = {'2026-08-01', '2026-08-02', '2026-08-03', '2026-08-08'};
      expect(
        longestKeptRun(dates, DateTime(2026, 8), DateTime(2026, 8, 13)),
        3,
      );
    });

    test('a day weighs the share of the list it kept', () {
      const habits = [
        Habit(kind: 'bath', name: 'Bath'),
        Habit(kind: 'water', name: 'Water', target: 8),
      ];
      final marks = [
        DayMark(
          id: 0,
          date: '2026-08-13',
          kind: 'bath',
          at: DateTime(2026),
        ),
        ...marksFor({'2026-08-13': 8}),
      ];
      expect(dayWeight(marks, habits, '2026-08-13'), 1);
      expect(dayWeight(marks, habits, '2026-08-12'), 0);
      // An empty checklist is no day, not a failed one.
      expect(dayWeight(marks, const [], '2026-08-13'), 0);
    });
  });

  group('the repo', () {
    late LedgerDb db;

    setUp(() => db = LedgerDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('a habit toggles on and off, one row at most', () async {
      final repo = MarksRepo(db);
      final day = DateTime(2026, 8, 13);
      await repo.toggle(day, 'bath');
      await repo.toggle(day, 'run');
      expect((await repo.watchDay(day).first).length, 2);
      await repo.toggle(day, 'bath');
      final left = await repo.watchDay(day).first;
      expect(left.length, 1);
      expect(left.single.kind, 'run');
    });

    test('meals stack, and a wrong one can be struck', () async {
      final repo = MarksRepo(db);
      final day = DateTime(2026, 8, 13);
      await repo.addMeal(day, 'idli & chai');
      await repo.addMeal(day, 'lemon rice');
      await repo.addMeal(day, '   '); // whitespace writes nothing
      final meals = (await repo.watchDay(day).first)
          .where((m) => m.kind == 'meal')
          .toList();
      expect(meals.length, 2);
      await repo.removeMark(meals.first.id);
      expect(
        (await repo.watchDay(day).first).where((m) => m.kind == 'meal').length,
        1,
      );
    });

    test('a slip is idempotent and can be taken back', () async {
      final repo = MarksRepo(db);
      final day = DateTime(2026, 8, 13);
      await repo.setSlipped(day, true);
      await repo.setSlipped(day, true);
      var (slips, _) = await repo.slipRecord();
      expect(slips, {'2026-08-13'});
      await repo.setSlipped(day, false);
      (slips, _) = await repo.slipRecord();
      expect(slips, isEmpty);
    });

    test('a counted habit stacks marks and gives them back one at a time',
        () async {
      final repo = MarksRepo(db);
      final day = DateTime(2026, 8, 13);
      await repo.bump(day, 'water');
      await repo.bump(day, 'water');
      await repo.bump(day, 'water');
      expect(countOn(await repo.watchDay(day).first, '2026-08-13', 'water'), 3);
      await repo.unbump(day, 'water');
      expect(countOn(await repo.watchDay(day).first, '2026-08-13', 'water'), 2);
      // Taking back what isn't there is a no-op, not an error.
      await repo.unbump(day, 'chapati');
      expect(countOn(await repo.watchDay(day).first, '2026-08-13', 'water'), 2);
    });

    test('a day filled in later is stamped at midday, not at the clock',
        () async {
      final repo = MarksRepo(db);
      final past = DateTime(2026, 8, 1);
      await repo.addMeal(past, 'idli');
      final mark = (await repo.watchDay(past).first).single;
      expect(mark.at, DateTime(2026, 8, 1, 12));
    });

    test('the usual foods come back most-written first', () async {
      final repo = MarksRepo(db);
      final day = DateTime(2026, 8, 13);
      for (var i = 0; i < 3; i++) {
        await repo.addMeal(day, 'Chai');
      }
      await repo.addMeal(day, 'chai'); // same food, written smaller
      await repo.addMeal(day, 'idli');
      final usual = await repo.frequentMeals();
      expect(usual.first, 'Chai');
      expect(usual, contains('idli'));
      expect(usual.where((f) => f.toLowerCase() == 'chai').length, 1);
    });

    test('tracking start is stamped once and holds', () async {
      final repo = MarksRepo(db);
      final (_, since) = await repo.slipRecord();
      final (_, again) = await repo.slipRecord();
      expect(again, since);
    });
  });
}
