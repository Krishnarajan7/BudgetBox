import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;

import '../../core/notifications.dart';
import '../db.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';
import '../providers.dart';

final alarmRepoProvider = Provider<AlarmRepo>(
  (ref) => AlarmRepo(ref.watch(dbProvider)),
);

/// Monday-first, matching [DateTime.weekday] (1 = Monday … 7 = Sunday).
const weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Does this alarm ring on [weekday] (1 = Monday … 7 = Sunday)?
bool ringsOn(int days, int weekday) => days & (1 << (weekday - 1)) != 0;

/// The bitmask with [weekday] flipped.
int toggleDay(int days, int weekday) => days ^ (1 << (weekday - 1));

const _everyDay = 0x7F;
const _weekdays = 0x1F;

/// How the repeat reads on the row: "every day", "weekdays", "Mon, Thu", or
/// the date it will ring once and then be done.
String repeatLabel(int days, {DateTime? onceOn}) {
  if (days == 0) return onceOn == null ? 'once' : 'once · ${_dayWord(onceOn)}';
  if (days == _everyDay) return 'every day';
  if (days == _weekdays) return 'weekdays';
  if (days == _everyDay ^ _weekdays) return 'weekends';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return [
    for (var d = 1; d <= 7; d++)
      if (ringsOn(days, d)) names[d - 1],
  ].join(', ');
}

String _dayWord(DateTime d) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names[d.weekday - 1];
}

/// When this alarm next goes off, counting from [from]. A repeating alarm
/// walks forward to its next chosen weekday; a one-shot takes the next
/// occurrence of its time, to-day or to-morrow. Null when it's switched off.
DateTime? nextRing(Alarm alarm, DateTime from) {
  if (!alarm.enabled) return null;
  final today = DateTime(from.year, from.month, from.day);
  final at = today.add(Duration(minutes: alarm.minuteOfDay));
  if (alarm.days == 0) {
    return at.isAfter(from) ? at : at.add(const Duration(days: 1));
  }
  for (var i = 0; i < 8; i++) {
    final day = today.add(Duration(days: i));
    final ring = day.add(Duration(minutes: alarm.minuteOfDay));
    if (!ring.isAfter(from)) continue;
    if (ringsOn(alarm.days, ring.weekday)) return ring;
  }
  return null;
}

/// "in 7h 20m" — how long until it rings, said the way a person waiting
/// would say it. Under a minute is "in under a minute", never "in 0m".
String untilPhrase(Duration d) {
  if (d.inMinutes < 1) return 'in under a minute';
  if (d.inMinutes < 60) return 'in ${d.inMinutes}m';
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours < 24) {
    return minutes == 0 ? 'in ${hours}h' : 'in ${hours}h ${minutes}m';
  }
  final days = d.inDays;
  final restHours = hours % 24;
  return restHours == 0
      ? 'in ${days}d'
      : 'in ${days}d ${restHours}h';
}

/// Wall-clock text for a minute of the day: '06:30'.
String clockLabel(int minuteOfDay) {
  final h = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
  final m = (minuteOfDay % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// The alarms, and the promise that the operating system agrees with them.
///
/// Every write re-lays that alarm's schedule, and [resync] re-lays all of
/// them — called at launch, because a reboot or an app upgrade clears the
/// system's copy and an alarm that quietly stopped ringing is worse than no
/// alarm at all.
class AlarmRepo {
  AlarmRepo(this._db);

  final LedgerDb _db;

  Stream<List<Alarm>> watchAll() =>
      (_db.select(_db.alarms)..orderBy([
            (a) => OrderingTerm.asc(a.minuteOfDay),
            (a) => OrderingTerm.asc(a.id),
          ]))
          .watch();

  Future<List<Alarm>> all() =>
      (_db.select(_db.alarms)
            ..orderBy([(a) => OrderingTerm.asc(a.minuteOfDay)]))
          .get();

  Future<int> create({
    required int minuteOfDay,
    String label = '',
    int days = 0,
    int snoozeMinutes = 9,
    bool vibrate = true,
  }) async {
    final id = await _db.transaction(() async {
      final id = await _db
          .into(_db.alarms)
          .insert(
            AlarmsCompanion.insert(
              minuteOfDay: minuteOfDay,
              label: Value(label.trim()),
              days: Value(days),
              snoozeMinutes: Value(snoozeMinutes),
              vibrate: Value(vibrate),
            ),
          );
      await bbxSync.upsert(SyncKinds.alarm, id);
      return id;
    });
    await _reschedule(id);
    return id;
  }

  Future<void> update(
    int id, {
    int? minuteOfDay,
    String? label,
    int? days,
    bool? enabled,
    int? snoozeMinutes,
    bool? vibrate,
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.alarms)..where((a) => a.id.equals(id))).write(
        AlarmsCompanion(
          minuteOfDay:
              minuteOfDay == null ? const Value.absent() : Value(minuteOfDay),
          label: label == null ? const Value.absent() : Value(label.trim()),
          days: days == null ? const Value.absent() : Value(days),
          enabled: enabled == null ? const Value.absent() : Value(enabled),
          snoozeMinutes: snoozeMinutes == null
              ? const Value.absent()
              : Value(snoozeMinutes),
          vibrate: vibrate == null ? const Value.absent() : Value(vibrate),
        ),
      );
      await bbxSync.upsert(SyncKinds.alarm, id);
    });
    await _reschedule(id);
  }

  Future<void> delete(int id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.alarms)..where((a) => a.id.equals(id))).go();
      await bbxSync.remove(SyncKinds.alarm, id);
    });
    await LedgerReminders.cancelAlarm(id);
  }

  /// A one-shot that has rung switches itself off rather than lingering as
  /// a lie about to-morrow. Called when the page notices its time has gone.
  Future<void> retireSpent(DateTime now) async {
    for (final alarm in await all()) {
      if (alarm.days != 0 || !alarm.enabled) continue;
      if (nextRing(alarm, now) == null) {
        await update(alarm.id, enabled: false);
      }
    }
  }

  /// Re-lays every alarm with the system. Cheap, idempotent, and the only
  /// thing standing between a reboot and a missed morning.
  Future<void> resync() async {
    for (final alarm in await all()) {
      await _schedule(alarm);
    }
  }

  Future<void> _reschedule(int id) async {
    final alarm = await (_db.select(
      _db.alarms,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    if (alarm == null) {
      await LedgerReminders.cancelAlarm(id);
      return;
    }
    await _schedule(alarm);
  }

  Future<void> _schedule(Alarm alarm) => LedgerReminders.scheduleAlarm(
    id: alarm.id,
    label: alarm.label,
    minuteOfDay: alarm.minuteOfDay,
    days: alarm.days,
    enabled: alarm.enabled,
    snoozeMinutes: alarm.snoozeMinutes,
    vibrate: alarm.vibrate,
    from: DateTime.now(),
  );
}
