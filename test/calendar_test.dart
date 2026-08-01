import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/event_repo.dart';
import 'package:budgetbox/features/calendar/calendar_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Event _ev({
  int id = 1,
  String title = 'entry',
  required String date,
  int? timeMinutes,
  EventRepeat repeat = EventRepeat.none,
}) {
  return Event(
    id: id,
    title: title,
    date: date,
    timeMinutes: timeMinutes,
    repeat: repeat,
    createdAt: DateTime(2026, 1, 1),
    archived: false,
  );
}

void main() {
  group('EventRepo', () {
    late LedgerDb db;
    late EventRepo repo;

    setUp(() {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      repo = EventRepo(db);
    });

    tearDown(() => db.close());

    test('create writes the entry as anchored, watchAll sees it', () async {
      final id = await repo.create(
        title: 'Chai with Amma',
        date: DateTime(2026, 8, 14),
        timeMinutes: 9 * 60 + 30,
        repeat: EventRepeat.yearly,
        note: 'bring jaggery',
      );

      final rows = await repo.watchAll().first;
      expect(rows, hasLength(1));
      final e = rows.single;
      expect(e.id, id);
      expect(e.title, 'Chai with Amma');
      expect(e.date, '2026-08-14');
      expect(e.timeMinutes, 570);
      expect(e.repeat, EventRepeat.yearly);
      expect(e.note, 'bring jaggery');
      expect(e.archived, isFalse);
    });

    test('all-day is the default: no time, no repeat', () async {
      await repo.create(title: 'Quiet day', date: DateTime(2026, 8, 1));
      final e = (await repo.watchAll().first).single;
      expect(e.timeMinutes, isNull);
      expect(e.repeat, EventRepeat.none);
    });

    test('archive strikes the entry off the page', () async {
      final keep = await repo.create(title: 'keep', date: DateTime(2026, 8, 1));
      final gone = await repo.create(title: 'gone', date: DateTime(2026, 8, 2));

      await repo.archive(gone);

      final rows = await repo.watchAll().first;
      expect(rows.map((e) => e.id), [keep]);
    });
  });

  group('occurrencesInMonth', () {
    test('a yearly anchor from 2001 lands in august 2026', () {
      final birthday = _ev(
          date: '2001-08-14', repeat: EventRepeat.yearly, title: 'birthday');
      final occ =
          EventRepo.occurrencesInMonth([birthday], DateTime(2026, 8));
      expect(occ, hasLength(1));
      expect(occ.single.on, DateTime(2026, 8, 14));
      expect(occ.single.event.title, 'birthday');
    });

    test('a none event outside the month stays off its pages', () {
      final e = _ev(date: '2026-07-20');
      expect(EventRepo.occurrencesInMonth([e], DateTime(2026, 8)), isEmpty);
      expect(
          EventRepo.occurrencesInMonth([e], DateTime(2026, 7)), hasLength(1));
      expect(EventRepo.occurrencesInMonth([e], DateTime(2026, 7)).single.on,
          DateTime(2026, 7, 20));
    });

    test('a none event does not repeat across years', () {
      final e = _ev(date: '2025-08-14');
      expect(EventRepo.occurrencesInMonth([e], DateTime(2026, 8)), isEmpty);
    });

    test('feb-29 anchor lands on feb-28 when the year is not leap', () {
      final leapling = _ev(date: '2000-02-29', repeat: EventRepeat.yearly);
      final nonLeap =
          EventRepo.occurrencesInMonth([leapling], DateTime(2027, 2));
      expect(nonLeap.single.on, DateTime(2027, 2, 28));

      final leap = EventRepo.occurrencesInMonth([leapling], DateTime(2028, 2));
      expect(leap.single.on, DateTime(2028, 2, 29));
    });
  });

  group('upcoming', () {
    test('respects the 60-day horizon', () {
      final near = _ev(id: 1, title: 'near', date: '2026-09-20');
      final far = _ev(id: 2, title: 'far', date: '2026-10-05');
      final up = EventRepo.upcoming([near, far], DateTime(2026, 7, 31));
      // 2026-09-20 is day 51; 2026-10-05 is day 66 — past the horizon.
      expect(up.map((o) => o.event.title), ['near']);
    });

    test('resolves yearly repeats across a year boundary', () {
      final newYear = _ev(
          id: 1, title: 'new year', date: '2000-01-05',
          repeat: EventRepeat.yearly);
      final up = EventRepo.upcoming([newYear], DateTime(2026, 12, 20));
      expect(up, hasLength(1));
      expect(up.single.on, DateTime(2027, 1, 5));
    });

    test('caps the list at the limit, earliest first', () {
      final events = [
        for (var d = 1; d <= 7; d++)
          _ev(id: d, title: 'e$d', date: '2026-08-0$d'),
      ];
      final up = EventRepo.upcoming(events, DateTime(2026, 8, 1));
      expect(up, hasLength(5));
      expect(up.map((o) => o.event.title), ['e1', 'e2', 'e3', 'e4', 'e5']);
    });

    test('sorts by date, then time with all-day first', () {
      final evening = _ev(
          id: 1, title: 'evening', date: '2026-08-14', timeMinutes: 18 * 60);
      final morning = _ev(
          id: 2, title: 'morning', date: '2026-08-14', timeMinutes: 60);
      final allDay = _ev(id: 3, title: 'all day', date: '2026-08-14');
      final earlier = _ev(id: 4, title: 'earlier date', date: '2026-08-13');

      final up = EventRepo.upcoming(
          [evening, morning, allDay, earlier], DateTime(2026, 8, 10));
      expect(up.map((o) => o.event.title),
          ['earlier date', 'all day', 'morning', 'evening']);
    });
  });

  group('CalendarPage', () {
    testWidgets('renders the month and shows the written day', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      final repo = EventRepo(db);
      final now = DateTime.now();
      await repo.create(
        title: 'Chai with Amma',
        date: DateTime(now.year, now.month, now.day),
        timeMinutes: 9 * 60 + 30,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const CalendarPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The agenda spine shows the month sideways, to-day's number sits on
      // its paper chip, and the entry rides beside it with its hour.
      const months = [
        'january', 'february', 'march', 'april', 'may', 'june',
        'july', 'august', 'september', 'october', 'november', 'december',
      ];
      expect(find.text('${months[now.month - 1]} ${now.year}'),
          findsOneWidget);
      expect(find.text('${now.day}'), findsWidgets);
      expect(find.text('Chai with Amma'), findsOneWidget);
      expect(find.text('09:30'), findsOneWidget);

      // Drain drift's stream machinery so the binding sees no leaked timers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await db.close();
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
