import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dates.dart';

/// Loaded once per session and shared by every page that names a day.
final holidayBookProvider = FutureProvider<HolidayBook>(
  (ref) => HolidayBook.load(),
);

/// What a marked day is: a day off, a festival that is celebrated without
/// closing anything, or a day the country simply names.
enum HolidayKind { holiday, festival, observance }

/// A day the calendar has a name for.
class Holiday {
  const Holiday({
    required this.date,
    required this.name,
    required this.kind,
    required this.tamilNadu,
  });

  final DateTime date;
  final String name;
  final HolidayKind kind;

  /// True for the state's own days — Pongal, Thiruvalluvar Day — as opposed
  /// to the ones the whole country keeps.
  final bool tamilNadu;

  bool get isDayOff => kind == HolidayKind.holiday;

  /// "a holiday" / "a festival" — the phrase the pages put after the name.
  String get phrase => switch (kind) {
    HolidayKind.holiday => tamilNadu ? 'a state holiday' : 'a holiday',
    HolidayKind.festival => 'a festival',
    HolidayKind.observance => 'a marked day',
  };
}

/// The days India names, loaded once and answered from memory.
///
/// Two sources, deliberately: the six days that never move are *computed*,
/// so the book can always tell you about Independence Day in 2043; the days
/// that follow the moon are read from `assets/calendar/holidays.json`, which
/// runs out and says so rather than guessing. A calendar that invents
/// Deepavali is worse than one that admits it doesn't know yet.
class HolidayBook {
  const HolidayBook._(this._moveable, this.coversThrough);

  /// Keyed by 'yyyy-MM-dd'.
  final Map<String, List<Holiday>> _moveable;

  /// The last year the bundled table has real dates for.
  final int coversThrough;

  static HolidayBook? _cached;

  /// The days that are the same date every year, forever.
  static const _fixed = <(int month, int day, String name, HolidayKind kind)>[
    (1, 1, 'New Year\'s Day', HolidayKind.observance),
    (1, 26, 'Republic Day', HolidayKind.holiday),
    (5, 1, 'May Day', HolidayKind.holiday),
    (8, 15, 'Independence Day', HolidayKind.holiday),
    (10, 2, 'Gandhi Jayanti', HolidayKind.holiday),
    (12, 25, 'Christmas', HolidayKind.holiday),
  ];

  static Future<HolidayBook> load() async {
    if (_cached case final book?) return book;
    final raw = await rootBundle.loadString('assets/calendar/holidays.json');
    final book = parse(raw);
    _cached = book;
    return book;
  }

  /// Parsing kept separate from loading so the table can be tested without
  /// a bundle, and so a malformed line loses one day rather than the file.
  static HolidayBook parse(String raw) {
    final decoded = jsonDecode(raw);
    final days = <String, List<Holiday>>{};
    var through = 0;
    if (decoded is Map) {
      for (final year in (decoded['covers'] as List? ?? const [])) {
        if (year is int && year > through) through = year;
      }
      for (final entry in (decoded['days'] as List? ?? const [])) {
        if (entry is! Map) continue;
        final on = entry['on'];
        final name = entry['name'];
        if (on is! String || name is! String) continue;
        final date = DateTime.tryParse(on);
        if (date == null) continue;
        days.putIfAbsent(on, () => []).add(
          Holiday(
            date: date,
            name: name,
            kind: switch (entry['kind']) {
              'festival' => HolidayKind.festival,
              'observance' => HolidayKind.observance,
              _ => HolidayKind.holiday,
            },
            tamilNadu: entry['where'] == 'tn',
          ),
        );
      }
    }
    return HolidayBook._(days, through);
  }

  /// Every name this day carries — usually none, sometimes two (14 April is
  /// Tamil New Year and Ambedkar Jayanti at once).
  List<Holiday> on(DateTime day) {
    final out = <Holiday>[
      for (final (month, dayOfMonth, name, kind) in _fixed)
        if (day.month == month && day.day == dayOfMonth)
          Holiday(
            date: DateTime(day.year, month, dayOfMonth),
            name: name,
            kind: kind,
            tamilNadu: false,
          ),
      ...?_moveable[LedgerDates.dayKey(day)],
    ];
    // A day off outranks a festival when a page has room for one line.
    out.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return out;
  }

  /// The next named day at or after [from], within [within] days — what the
  /// Today page uses to say "to-morrow is Independence Day".
  ({Holiday holiday, int inDays})? next(DateTime from, {int within = 45}) {
    final start = DateTime(from.year, from.month, from.day);
    for (var i = 0; i <= within; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      final names = on(day);
      if (names.isEmpty) continue;
      return (holiday: names.first, inDays: i);
    }
    return null;
  }

  /// True once the moveable table has run out for [day]'s year — the pages
  /// use this to stay quiet instead of implying nothing is coming.
  bool isBeyondTable(DateTime day) => day.year > coversThrough;

  /// Test seam: drops the parsed table so a test can load its own.
  static void resetForTesting() => _cached = null;
}

/// How a day is introduced when it has a name: "To-morrow is Independence
/// Day — a holiday." Returns null when there is nothing to say, which is
/// most days, and the page should then say nothing at all.
String? dayLine(HolidayBook book, DateTime today) {
  final next = book.next(today, within: 14);
  if (next == null) return null;
  final (:holiday, :inDays) = next;
  final when = switch (inDays) {
    0 => 'To-day is',
    1 => 'To-morrow is',
    _ => '${LedgerDates.weekdaysFull[holiday.date.weekday - 1]} is',
  };
  return '$when ${holiday.name} — ${holiday.phrase}.';
}
