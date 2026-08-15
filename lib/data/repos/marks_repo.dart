import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../db.dart';
import 'habit_repo.dart';

/// The consecutive clean days ending at [today], given every slip date and
/// the day tracking began. A day is clean when it has no slip; to-day counts
/// as clean-so-far until a slip lands on it. Pure, so the arithmetic is
/// testable without a database in sight.
int cleanStreak(Set<String> slipDates, String since, DateTime today) {
  var day = DateTime(today.year, today.month, today.day);
  final start = DateTime.parse(since);
  var n = 0;
  while (!day.isBefore(start)) {
    if (slipDates.contains(LedgerDates.dayKey(day))) break;
    n++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return n;
}

/// The longest clean run anywhere in the record, the current one included.
int bestCleanRun(Set<String> slipDates, String since, DateTime today) {
  final start = DateTime.parse(since);
  var day = DateTime(today.year, today.month, today.day);
  var best = 0;
  var run = 0;
  while (!day.isBefore(start)) {
    if (slipDates.contains(LedgerDates.dayKey(day))) {
      run = 0;
    } else {
      run++;
      if (run > best) best = run;
    }
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return best;
}

/// How many marks a day carries for one habit — a tick reads 0 or 1, a
/// counted habit reads however many taps it got.
int countOn(List<DayMark> marks, String date, String kind) {
  var n = 0;
  for (final m in marks) {
    if (m.date == date && m.kind == kind) n++;
  }
  return n;
}

/// Every date in [marks] where [habit] reached its target. The one input the
/// runs, the week table and the record grid all agree on.
Set<String> daysKept(List<DayMark> marks, Habit habit) {
  final counts = <String, int>{};
  for (final m in marks) {
    if (m.kind != habit.kind) continue;
    counts[m.date] = (counts[m.date] ?? 0) + 1;
  }
  return {
    for (final e in counts.entries)
      if (e.value >= habit.target) e.key,
  };
}

/// The run of days ending at [today] — how many days in a row it was kept.
///
/// To-day is a grace day: a habit not done *yet* at 9 a.m. hasn't been
/// missed, so an open day never breaks the run, it just doesn't extend it.
/// (The clean count is the opposite by nature — see [cleanStreak] — because
/// there the absence of a mark is the achievement.)
int keptRun(Set<String> dates, DateTime today) {
  var day = DateTime(today.year, today.month, today.day);
  if (!dates.contains(LedgerDates.dayKey(day))) {
    day = DateTime(day.year, day.month, day.day - 1);
  }
  var n = 0;
  while (dates.contains(LedgerDates.dayKey(day))) {
    n++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return n;
}

/// The longest run of kept days inside the window [from]..[to], inclusive.
int longestKeptRun(Set<String> dates, DateTime from, DateTime to) {
  var day = DateTime(from.year, from.month, from.day);
  final last = DateTime(to.year, to.month, to.day);
  var best = 0;
  var run = 0;
  while (!day.isAfter(last)) {
    if (dates.contains(LedgerDates.dayKey(day))) {
      run++;
      if (run > best) best = run;
    } else {
      run = 0;
    }
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return best;
}

/// The share of [habits] kept on [date], 0..1 — what shades one square of
/// the record grid. An empty checklist is not a failed day, it's no day.
double dayWeight(List<DayMark> marks, List<Habit> habits, String date) {
  final live = [for (final h in habits) if (!h.archived) h];
  if (live.isEmpty) return 0;
  var kept = 0;
  for (final h in live) {
    if (countOn(marks, date, h.kind) >= h.target) kept++;
  }
  return kept / live.length;
}

/// The Daily page's book-keeper: habit ticks, meals, and the slip record.
class MarksRepo {
  MarksRepo(this._db);

  final LedgerDb _db;

  Stream<List<DayMark>> watchDay(DateTime day) {
    final key = LedgerDates.dayKey(day);
    return (_db.select(_db.dayMarks)
          ..where((m) => m.date.equals(key))
          ..orderBy([(m) => OrderingTerm.asc(m.at)]))
        .watch();
  }

  /// Every mark from [from] onward — the week strip and the streak both
  /// read from this one stream.
  Stream<List<DayMark>> watchSince(DateTime from) {
    return (_db.select(_db.dayMarks)
          ..where((m) => m.date.isBiggerOrEqualValue(LedgerDates.dayKey(from)))
          ..orderBy([(m) => OrderingTerm.asc(m.date)]))
        .watch();
  }

  /// Every slip row, live — the streak recomputes the moment one lands or
  /// is taken back. Slips are rare rows; watching them all is cheap.
  Stream<List<DayMark>> watchSlips() =>
      (_db.select(_db.dayMarks)..where((m) => m.kind.equals('slip'))).watch();

  /// Every slip ever, plus the day tracking started — the streak's inputs.
  Future<(Set<String> slips, String since)> slipRecord() async {
    final slips = await (_db.select(
      _db.dayMarks,
    )..where((m) => m.kind.equals('slip'))).get();
    final since = await _since();
    return ({for (final s in slips) s.date}, since);
  }

  /// The day the Daily page first opened — stored once, in the settings
  /// table, so a streak never claims days the book wasn't watching.
  Future<String> _since() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals('marksSince'))).getSingleOrNull();
    if (row != null) return row.value;
    final today = LedgerDates.dayKey(DateTime.now());
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion(
            key: const Value('marksSince'),
            value: Value(today),
          ),
        );
    return today;
  }

  /// Tick or untick a habit for a day: at most one row per (day, kind).
  Future<void> toggle(DateTime day, String kind) async {
    final key = LedgerDates.dayKey(day);
    final existing = await (_db.select(
      _db.dayMarks,
    )..where((m) => m.date.equals(key) & m.kind.equals(kind))).get();
    if (existing.isNotEmpty) {
      await (_db.delete(
        _db.dayMarks,
      )..where((m) => m.date.equals(key) & m.kind.equals(kind))).go();
    } else {
      await _db
          .into(_db.dayMarks)
          .insert(
            DayMarksCompanion.insert(
              date: key,
              kind: kind,
              at: Value(stampFor(day)),
            ),
          );
    }
  }

  /// One more toward a counted habit — a glass of water, a set. Counted
  /// habits stack rows instead of flipping one, so the day remembers when
  /// each came in and the history stays a record rather than a total.
  Future<void> bump(DateTime day, String kind) async {
    await _db
        .into(_db.dayMarks)
        .insert(
          DayMarksCompanion.insert(
            date: LedgerDates.dayKey(day),
            kind: kind,
            at: Value(stampFor(day)),
          ),
        );
  }

  /// Takes back the last one — the undo for a tap too many.
  Future<void> unbump(DateTime day, String kind) async {
    final key = LedgerDates.dayKey(day);
    final rows =
        await (_db.select(_db.dayMarks)
              ..where((m) => m.date.equals(key) & m.kind.equals(kind))
              ..orderBy([(m) => OrderingTerm.desc(m.at)])
              ..limit(1))
            .get();
    if (rows.isEmpty) return;
    await removeMark(rows.first.id);
  }

  Future<void> addMeal(DateTime day, String food) async {
    final text = food.trim();
    if (text.isEmpty) return;
    await _db
        .into(_db.dayMarks)
        .insert(
          DayMarksCompanion.insert(
            date: LedgerDates.dayKey(day),
            kind: 'meal',
            note: Value(text),
            at: Value(stampFor(day)),
          ),
        );
  }

  /// The foods that come back most often, newest-first among ties — the
  /// quick row on the meal card, so writing "chai" for the 200th time is
  /// one tap instead of five letters.
  Future<List<String>> frequentMeals({int limit = 6}) async {
    final rows =
        await (_db.select(_db.dayMarks)
              ..where((m) => m.kind.equals('meal'))
              ..orderBy([(m) => OrderingTerm.desc(m.at)])
              ..limit(400))
            .get();
    final seen = <String, ({int count, int rank})>{};
    for (final (i, r) in rows.indexed) {
      final text = (r.note ?? '').trim();
      if (text.isEmpty) continue;
      final key = text.toLowerCase();
      final prior = seen[key];
      seen[key] = (count: (prior?.count ?? 0) + 1, rank: prior?.rank ?? i);
    }
    final byUse = seen.entries.toList()
      ..sort((a, b) {
        final c = b.value.count.compareTo(a.value.count);
        return c != 0 ? c : a.value.rank.compareTo(b.value.rank);
      });
    // Written back in the hand they were first written in, not lowercased.
    final original = <String, String>{};
    for (final r in rows) {
      final text = (r.note ?? '').trim();
      if (text.isEmpty) continue;
      original.putIfAbsent(text.toLowerCase(), () => text);
    }
    return [for (final e in byUse.take(limit)) original[e.key] ?? e.key];
  }

  /// When a mark on [day] happened. To-day is stamped with the clock; a day
  /// being filled in after the fact is stamped at midday, because the book
  /// would rather admit it doesn't know the hour than invent one.
  static DateTime stampFor(DateTime day) {
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    return isToday ? now : DateTime(day.year, day.month, day.day, 12);
  }

  Future<void> removeMark(int id) =>
      (_db.delete(_db.dayMarks)..where((m) => m.id.equals(id))).go();

  /// Marks to-day as slipped (idempotent), or takes it back — a wrong tap
  /// must never cost a real streak.
  Future<void> setSlipped(DateTime day, bool slipped) async {
    final key = LedgerDates.dayKey(day);
    if (slipped) {
      final existing = await (_db.select(
        _db.dayMarks,
      )..where((m) => m.date.equals(key) & m.kind.equals('slip'))).get();
      if (existing.isEmpty) {
        await _db
            .into(_db.dayMarks)
            .insert(DayMarksCompanion.insert(date: key, kind: 'slip'));
      }
    } else {
      await (_db.delete(
        _db.dayMarks,
      )..where((m) => m.date.equals(key) & m.kind.equals('slip'))).go();
    }
  }
}
