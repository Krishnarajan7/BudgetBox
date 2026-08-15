import 'package:budgetbox/core/occasions.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/event_repo.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The birthday written anywhere is the birthday written everywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings → calendar: one yearly event, moved not duplicated', () async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final bridge = Occasions(db);

    await bridge.birthdaySetInSettings(14, 7);
    var events = await db.select(db.events).get();
    expect(events, hasLength(1));
    expect(events.single.title, 'my birthday');
    expect(events.single.repeat, EventRepeat.yearly);
    expect(events.single.date.endsWith('-07-14'), isTrue);

    // Corrected date moves the same event; no twins.
    await bridge.birthdaySetInSettings(2, 11);
    events = await db.select(db.events).get();
    expect(events, hasLength(1));
    expect(events.single.date.endsWith('-11-02'), isTrue);
  });

  test(
    'calendar → settings: "my birthday" is understood, amma\'s is not',
    () async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final bridge = Occasions(db);
      final settings = SettingsRepo(db);

      await bridge.eventWritten("amma's birthday", DateTime(2026, 3, 9));
      expect(
        await settings.birthday(),
        isNull,
        reason: 'someone else\'s day must not become Krish\'s',
      );

      await bridge.eventWritten('My Birthday', DateTime(2026, 7, 14));
      expect(await settings.birthday(), (14, 7));

      await bridge.eventWritten('என் பிறந்தநாள்', DateTime(2026, 1, 2));
      expect(await settings.birthday(), (2, 1));
    },
  );

  test(
    'calendar and settings birthday rows are consolidated on launch',
    () async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final events = EventRepo(db);
      await events.create(
        title: 'my birthday',
        date: DateTime(2026, 8, 18),
        repeat: EventRepeat.yearly,
      );
      await events.create(
        title: 'My Bday',
        date: DateTime(2026, 8, 18),
        repeat: EventRepeat.yearly,
      );

      await Occasions(db).resyncNotifications();

      final active = await (db.select(
        db.events,
      )..where((e) => e.archived.equals(false))).get();
      expect(active, hasLength(1));
      expect(active.single.title, Occasions.ownBirthdayTitle);
    },
  );

  test('next occurrence: one-offs expire, yearly rolls forward', () {
    Event ev(String date, EventRepeat r) => Event(
      id: 1,
      title: 't',
      date: date,
      repeat: r,
      createdAt: DateTime(2026),
      archived: false,
    );
    final from = DateTime(2026, 8, 12);

    expect(
      Occasions.nextOccurrence(ev('2026-08-01', EventRepeat.none), from),
      isNull,
    );
    expect(
      Occasions.nextOccurrence(ev('2026-09-01', EventRepeat.none), from),
      DateTime(2026, 9, 1),
    );
    // Birthday earlier in the year → next year's date.
    expect(
      Occasions.nextOccurrence(ev('2000-07-14', EventRepeat.yearly), from),
      DateTime(2027, 7, 14),
    );
    expect(
      Occasions.nextOccurrence(ev('2000-12-25', EventRepeat.yearly), from),
      DateTime(2026, 12, 25),
    );
  });
}
