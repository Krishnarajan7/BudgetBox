import 'package:drift/drift.dart';

import '../core/rain_watch.dart';
import 'db.dart';
import 'repos/alarm_repo.dart';

/// The ride lines: what a commute looks like when it is written down.
final _rideWords = RegExp(
  r'rapido|ola\b|uber|auto\b|\bbus\b|metro|cab\b|rickshaw|bike taxi|shuttle',
  caseSensitive: false,
);

/// When he usually leaves, from the book's own evidence: the first ride
/// line on each weekday over the last six weeks, and the middle of those
/// times. Three mornings is the least that counts as a habit; fewer and
/// the answer is null rather than a guess.
///
/// Pure over rows of (at) so it can be proved without a database.
DateTime? usualLeaving(Iterable<DateTime> rideTimes, DateTime today) {
  final firstByDay = <String, DateTime>{};
  for (final t in rideTimes) {
    if (t.weekday >= DateTime.saturday) continue;
    // Mornings only: a ride home says nothing about leaving.
    if (t.hour < 5 || t.hour >= 12) continue;
    final key = '${t.year}-${t.month}-${t.day}';
    final cur = firstByDay[key];
    if (cur == null || t.isBefore(cur)) firstByDay[key] = t;
  }
  if (firstByDay.length < 3) return null;
  final minutes = [for (final t in firstByDay.values) t.hour * 60 + t.minute]
    ..sort();
  final mid = minutes[minutes.length ~/ 2];
  return DateTime(today.year, today.month, today.day, mid ~/ 60, mid % 60);
}

/// Reads what the rain line needs from the book: the usual leaving time and
/// the next alarm. Cheap — two small reads — and never throws.
Future<RainContext> readRainContext(LedgerDb db, DateTime now) async {
  try {
    final since = now.subtract(const Duration(days: 42));
    final rows =
        await (db.select(db.txns)..where(
              (t) =>
                  t.type.equalsValue(TxnType.expense) &
                  t.at.isBiggerOrEqualValue(since),
            ))
            .get();
    final rides = [
      for (final t in rows)
        if (_rideWords.hasMatch(t.title)) t.at,
    ];
    final leaves = usualLeaving(rides, now);

    DateTime? wake;
    for (final a in await db.select(db.alarms).get()) {
      final at = nextRing(a, now);
      if (at == null) continue;
      if (wake == null || at.isBefore(wake)) wake = at;
    }
    return RainContext(leavesAt: leaves, wakeAt: wake);
  } on Object {
    return const RainContext();
  }
}
