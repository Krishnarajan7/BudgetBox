import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../db.dart';

/// The habit kinds the Daily page offers, in checklist order. Plain words on
/// purpose — a habit named cleverly is a habit skipped.
const habitKinds = [
  ('bath', 'Bath'),
  ('run', 'Running'),
  ('push', 'Push-ups'),
  ('pull', 'Pull-ups'),
  ('squat', 'Squats'),
];

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
          .insert(DayMarksCompanion.insert(date: key, kind: kind));
    }
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
          ),
        );
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
