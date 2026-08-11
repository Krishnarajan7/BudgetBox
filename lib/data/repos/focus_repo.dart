import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db.dart';
import '../providers.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';

final focusRepoProvider =
    Provider<FocusRepo>((ref) => FocusRepo(ref.watch(dbProvider)));

/// The focus ledger: every sitting — finished or abandoned — gets a line.
/// Minutes are written as they were actually spent; the book never rounds up.
class FocusRepo {
  FocusRepo(this._db);

  final LedgerDb _db;

  /// Writes one session line. [minutes] is what was truly sat, not the
  /// preset — a 25 left after 12 is recorded as 12, incomplete, no verdict.
  Future<int> record({
    required DateTime startedAt,
    required int minutes,
    required FocusKind kind,
    required bool completed,
    String? label,
  }) {
    return _db.transaction(() async {
      final id = await _db.into(_db.focusSessions).insert(
            FocusSessionsCompanion.insert(
              startedAt: startedAt,
              minutes: minutes,
              kind: kind,
              completed: Value(completed),
              label: Value(label),
            ),
          );
      await bbxSync.upsert(SyncKinds.focus, id);
      return id;
    });
  }

  /// Every session started on [day]'s local date, earliest first — the page
  /// reads top to bottom like the day did.
  Stream<List<FocusSession>> watchDay(DateTime day) {
    final from = DateTime(day.year, day.month, day.day);
    final to = DateTime(day.year, day.month, day.day + 1);
    final q = _db.select(_db.focusSessions)
      ..where((s) =>
          s.startedAt.isBiggerOrEqualValue(from) &
          s.startedAt.isSmallerThanValue(to))
      ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]);
    return q.watch();
  }

  /// The month's totals — completed work sessions only. Rest doesn't count
  /// toward the tally, and neither does a session he walked away from.
  Future<({int totalMinutes, int sessions, DateTime? bestDay, int bestDayMinutes})>
      monthStats(DateTime month) async {
    final from = DateTime(month.year, month.month);
    final to = DateTime(month.year, month.month + 1);
    final rows = await (_db.select(_db.focusSessions)
          ..where((s) =>
              s.kind.equalsValue(FocusKind.work) &
              s.completed.equals(true) &
              s.startedAt.isBiggerOrEqualValue(from) &
              s.startedAt.isSmallerThanValue(to)))
        .get();

    var totalMinutes = 0;
    final byDay = <int, int>{}; // day-of-month -> minutes
    for (final r in rows) {
      totalMinutes += r.minutes;
      byDay.update(r.startedAt.day, (m) => m + r.minutes,
          ifAbsent: () => r.minutes);
    }

    DateTime? bestDay;
    var bestDayMinutes = 0;
    for (final e in byDay.entries) {
      // Ties go to the earlier day — the first time he did it counts.
      if (e.value > bestDayMinutes ||
          (e.value == bestDayMinutes && bestDay != null && e.key < bestDay.day)) {
        bestDay = DateTime(month.year, month.month, e.key);
        bestDayMinutes = e.value;
      }
    }

    return (
      totalMinutes: totalMinutes,
      sessions: rows.length,
      bestDay: bestDay,
      bestDayMinutes: bestDayMinutes,
    );
  }
}
