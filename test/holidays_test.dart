import 'package:budgetbox/core/holidays.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the bundled table', () {
    late HolidayBook book;

    setUpAll(() async {
      HolidayBook.resetForTesting();
      book = HolidayBook.parse(
        await rootBundle.loadString('assets/calendar/holidays.json'),
      );
    });

    test('knows the day this whole feature started with', () {
      final names = book.on(DateTime(2026, 8, 15));
      expect(names.single.name, 'Independence Day');
      expect(names.single.isDayOff, isTrue);
    });

    test('the fixed days are computed, not listed — any year, forever', () {
      for (final year in [2026, 2031, 2043]) {
        expect(
          book.on(DateTime(year, 1, 26)).map((h) => h.name),
          contains('Republic Day'),
        );
        expect(
          book.on(DateTime(year, 10, 2)).map((h) => h.name),
          contains('Gandhi Jayanti'),
        );
      }
    });

    test('Pongal and Deepavali come from the table, in TN\'s own dates', () {
      expect(book.on(DateTime(2026, 1, 15)).single.name, 'Pongal');
      expect(book.on(DateTime(2026, 1, 15)).single.tamilNadu, isTrue);
      // TN keeps Deepavali a day earlier than Delhi in 2027 — the state's
      // date is the one that ships.
      expect(book.on(DateTime(2027, 10, 28)).single.name, 'Deepavali');
      expect(book.on(DateTime(2027, 10, 29)), isEmpty);
    });

    test('a day can carry two names', () {
      final april14 = book.on(DateTime(2026, 4, 14));
      expect(april14.single.name, 'Tamil New Year & Ambedkar Jayanti');
    });

    test('an ordinary day carries none', () {
      expect(book.on(DateTime(2026, 8, 14)), isEmpty);
      expect(book.on(DateTime(2026, 6, 3)), isEmpty);
    });

    test('a day off outranks a festival on the same date', () {
      // 2027-08-15 is Independence Day (fixed) and Milad-un-Nabi (table).
      final names = book.on(DateTime(2027, 8, 15));
      expect(names.length, 2);
      expect(names.first.isDayOff, isTrue);
    });

    test('the next named day is found, with how far off it is', () {
      final next = book.next(DateTime(2026, 8, 14));
      expect(next!.holiday.name, 'Independence Day');
      expect(next.inDays, 1);
      // Nothing within a short horizon reads as nothing.
      expect(book.next(DateTime(2026, 6, 1), within: 3), isNull);
    });

    test('the table admits where it ends', () {
      expect(book.coversThrough, 2027);
      expect(book.isBeyondTable(DateTime(2027, 12, 31)), isFalse);
      expect(book.isBeyondTable(DateTime(2028, 1, 1)), isTrue);
      // …and the fixed days still hold out there.
      expect(book.on(DateTime(2028, 8, 15)).single.name, 'Independence Day');
    });
  });

  group('the line the page says', () {
    final book = HolidayBook.parse('''
    { "covers": [2026],
      "days": [
        {"on": "2026-11-08", "name": "Deepavali", "kind": "holiday", "where": "tn"},
        {"on": "2026-03-04", "name": "Holi", "kind": "festival", "where": "in"}
      ] }
    ''');

    test('to-morrow is named as to-morrow', () {
      expect(
        dayLine(book, DateTime(2026, 11, 7)),
        'To-morrow is Deepavali — a state holiday.',
      );
    });

    test('to-day is named as to-day', () {
      expect(
        dayLine(book, DateTime(2026, 11, 8)),
        'To-day is Deepavali — a state holiday.',
      );
    });

    test('further out, the weekday carries it', () {
      expect(dayLine(book, DateTime(2026, 3, 1)), contains('Wednesday is Holi'));
      expect(dayLine(book, DateTime(2026, 3, 1)), endsWith('a festival.'));
    });

    test('an ordinary stretch says nothing at all', () {
      expect(dayLine(book, DateTime(2026, 6, 1)), isNull);
    });

    test('a broken line loses that day, not the file', () {
      final patchy = HolidayBook.parse('''
      { "covers": [2026],
        "days": [
          {"on": "not-a-date", "name": "Nonsense"},
          {"name": "No date at all"},
          {"on": "2026-11-08", "name": "Deepavali", "kind": "holiday"}
        ] }
      ''');
      expect(patchy.on(DateTime(2026, 11, 8)).single.name, 'Deepavali');
    });
  });
}
