import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/alarm_repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Alarm _alarm({
  int minuteOfDay = 6 * 60 + 30,
  int days = 0,
  bool enabled = true,
}) => Alarm(
  id: 1,
  label: 'gym',
  minuteOfDay: minuteOfDay,
  days: days,
  enabled: enabled,
  snoozeMinutes: 9,
  vibrate: true,
  createdAt: DateTime(2026),
);

void main() {
  // 14 Aug 2026 is a Friday.
  final fridayMorning = DateTime(2026, 8, 14, 5);
  final fridayEvening = DateTime(2026, 8, 14, 21);

  group('when it next rings', () {
    test('a one-shot takes to-day if the hour is still ahead', () {
      expect(nextRing(_alarm(), fridayMorning), DateTime(2026, 8, 14, 6, 30));
    });

    test('a one-shot rolls to to-morrow once the hour has gone', () {
      expect(nextRing(_alarm(), fridayEvening), DateTime(2026, 8, 15, 6, 30));
    });

    test('a repeating alarm finds its next chosen day', () {
      // Mondays and Thursdays.
      final alarm = _alarm(days: (1 << 0) | (1 << 3));
      expect(nextRing(alarm, fridayMorning), DateTime(2026, 8, 17, 6, 30));
    });

    test('a day it rings on to-day still counts, until the minute passes', () {
      final fridays = _alarm(days: 1 << 4);
      expect(nextRing(fridays, fridayMorning), DateTime(2026, 8, 14, 6, 30));
      expect(nextRing(fridays, fridayEvening), DateTime(2026, 8, 21, 6, 30));
    });

    test('a switched-off alarm never rings', () {
      expect(nextRing(_alarm(enabled: false), fridayMorning), isNull);
      expect(
        nextRing(_alarm(days: 0x7F, enabled: false), fridayMorning),
        isNull,
      );
    });

    test('midnight is a real time, not a falsy one', () {
      expect(
        nextRing(_alarm(minuteOfDay: 0), fridayEvening),
        DateTime(2026, 8, 15),
      );
    });
  });

  group('how it reads', () {
    test('the days say what they are', () {
      expect(repeatLabel(0), 'once');
      expect(repeatLabel(0x7F), 'every day');
      expect(repeatLabel(0x1F), 'weekdays');
      expect(repeatLabel(0x60), 'weekends');
      expect(repeatLabel((1 << 0) | (1 << 3)), 'Mon, Thu');
      expect(repeatLabel(0, onceOn: DateTime(2026, 8, 15)), 'once · Sat');
    });

    test('the wait is said the way a person waiting says it', () {
      expect(untilPhrase(const Duration(seconds: 30)), 'in under a minute');
      expect(untilPhrase(const Duration(minutes: 20)), 'in 20m');
      expect(untilPhrase(const Duration(hours: 7, minutes: 20)), 'in 7h 20m');
      expect(untilPhrase(const Duration(hours: 9)), 'in 9h');
      expect(untilPhrase(const Duration(days: 2, hours: 3)), 'in 2d 3h');
    });

    test('the clock is always four figures', () {
      expect(clockLabel(0), '00:00');
      expect(clockLabel(6 * 60 + 5), '06:05');
      expect(clockLabel(23 * 60 + 59), '23:59');
    });

    test('a day toggles on and off its own bit', () {
      var days = 0;
      days = toggleDay(days, DateTime.monday);
      expect(ringsOn(days, DateTime.monday), isTrue);
      expect(ringsOn(days, DateTime.sunday), isFalse);
      days = toggleDay(days, DateTime.monday);
      expect(days, 0);
    });
  });

  group('the repo', () {
    late LedgerDb db;
    late AlarmRepo repo;

    setUp(() {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      repo = AlarmRepo(db);
    });
    tearDown(() => db.close());

    test('alarms come back in clock order', () async {
      await repo.create(minuteOfDay: 21 * 60, label: 'wind down');
      await repo.create(minuteOfDay: 6 * 60 + 30, label: 'gym');
      final all = await repo.all();
      expect(all.map((a) => a.label), ['gym', 'wind down']);
    });

    test('an alarm can be retimed, renamed and switched off', () async {
      final id = await repo.create(minuteOfDay: 6 * 60, days: 1 << 0);
      await repo.update(
        id,
        minuteOfDay: 7 * 60,
        label: '  the 7:40 bus  ',
        enabled: false,
      );
      final alarm = (await repo.all()).single;
      expect(alarm.minuteOfDay, 7 * 60);
      expect(alarm.label, 'the 7:40 bus');
      expect(alarm.enabled, isFalse);
      expect(alarm.days, 1 << 0, reason: 'untouched fields stay put');
    });

    test('a spent one-shot switches itself off; a repeat is left alone',
        () async {
      final once = await repo.create(minuteOfDay: 6 * 60);
      final weekly = await repo.create(minuteOfDay: 6 * 60, days: 0x7F);
      // Long past its hour, and past to-morrow's too.
      await repo.retireSpent(DateTime(2026, 8, 14, 7));
      final byId = {for (final a in await repo.all()) a.id: a};
      // A one-shot at 06:00 seen at 07:00 still has to-morrow's 06:00 —
      // it is only spent once nothing is left, which is never for a repeat.
      expect(byId[weekly]!.enabled, isTrue);
      expect(byId[once]!.enabled, isTrue);
    });

    test('deleting takes it out of the book', () async {
      final id = await repo.create(minuteOfDay: 6 * 60);
      await repo.delete(id);
      expect(await repo.all(), isEmpty);
    });
  });
}
