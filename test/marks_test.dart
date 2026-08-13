import 'package:budgetbox/data/db.dart';
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

    test('tracking start is stamped once and holds', () async {
      final repo = MarksRepo(db);
      final (_, since) = await repo.slipRecord();
      final (_, again) = await repo.slipRecord();
      expect(again, since);
    });
  });
}
