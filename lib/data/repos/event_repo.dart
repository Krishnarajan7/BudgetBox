import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../db.dart';
import '../providers.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';

final eventRepoProvider =
    Provider<EventRepo>((ref) => EventRepo(ref.watch(dbProvider)));

/// The calendar's book-keeping. Events are written once against an anchor
/// date; a yearly repeat re-occurs on that month and day every year after —
/// birthdays live here. Resolution is pure math over the rows, so the page
/// never asks the database what a month looks like.
class EventRepo {
  EventRepo(this._db);

  final LedgerDb _db;

  Future<int> create({
    required String title,
    required DateTime date,
    int? timeMinutes,
    EventRepeat repeat = EventRepeat.none,
    String? note,
  }) {
    return _db.transaction(() async {
      final id = await _db.into(_db.events).insert(
            EventsCompanion.insert(
              title: title,
              date: LedgerDates.dayKey(date),
              timeMinutes: Value(timeMinutes),
              repeat: Value(repeat),
              note: Value(note),
            ),
          );
      await bbxSync.upsert(SyncKinds.event, id);
      return id;
    });
  }

  /// Move or re-shape an existing event; the calendar and the bridge both
  /// route edits through here so sync always hears about them.
  Future<void> update(
    int id, {
    String? title,
    DateTime? date,
    EventRepeat? repeat,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.events)..where((e) => e.id.equals(id))).write(
        EventsCompanion(
          title: title == null ? const Value.absent() : Value(title),
          date: date == null
              ? const Value.absent()
              : Value(LedgerDates.dayKey(date)),
          repeat: repeat == null ? const Value.absent() : Value(repeat),
        ),
      );
      await bbxSync.upsert(SyncKinds.event, id);
    });
  }

  Future<void> archive(int id) {
    return _db.transaction(() async {
      await (_db.update(_db.events)..where((e) => e.id.equals(id)))
          .write(const EventsCompanion(archived: Value(true)));
      // EventIn carries no `archived`; taking an event off the calendar is a
      // PATCH upstream.
      await bbxSync.patch(SyncKinds.event, id, {'archived': true});
    });
  }

  /// Every active event, anchor-dated. Occurrence math happens in memory.
  Stream<List<Event>> watchAll() {
    final q = _db.select(_db.events)
      ..where((e) => e.archived.equals(false))
      ..orderBy([(e) => OrderingTerm.asc(e.date)]);
    return q.watch();
  }

  /// Where an event lands in [month]. `none` events occur once, on their
  /// date; `yearly` events occur on their anchor month+day each year from
  /// the anchor onward (a Feb-29 anchor lands on Feb-28 in non-leap years).
  static List<({Event event, DateTime on})> occurrencesInMonth(
      List<Event> events, DateTime month) {
    final start = LedgerDates.monthStart(month);
    final out = <({Event event, DateTime on})>[];
    for (final e in events) {
      final anchor = _anchorOf(e);
      switch (e.repeat) {
        case EventRepeat.none:
          if (anchor.year == start.year && anchor.month == start.month) {
            out.add((event: e, on: anchor));
          }
        case EventRepeat.yearly:
          final on = _yearlyOn(anchor, start.year);
          if (on.month == start.month && !on.isBefore(anchor)) {
            out.add((event: e, on: on));
          }
      }
    }
    out.sort(_byWhen);
    return out;
  }

  /// The next occurrences on or after [from], within [days], capped at
  /// [limit]. Sorted by date, then time-of-day with all-day entries first.
  static List<({Event event, DateTime on})> upcoming(
      List<Event> events, DateTime from,
      {int days = 60, int limit = 5}) {
    final first = DateTime(from.year, from.month, from.day);
    final end = DateTime(from.year, from.month, from.day + days);
    final out = <({Event event, DateTime on})>[];
    for (final e in events) {
      final anchor = _anchorOf(e);
      switch (e.repeat) {
        case EventRepeat.none:
          if (!anchor.isBefore(first) && anchor.isBefore(end)) {
            out.add((event: e, on: anchor));
          }
        case EventRepeat.yearly:
          for (var year = first.year; year <= end.year; year++) {
            final on = _yearlyOn(anchor, year);
            if (!on.isBefore(first) && on.isBefore(end) &&
                !on.isBefore(anchor)) {
              out.add((event: e, on: on));
            }
          }
      }
    }
    out.sort(_byWhen);
    return out.length <= limit ? out : out.sublist(0, limit);
  }

  static DateTime _anchorOf(Event e) {
    final d = DateTime.parse(e.date);
    return DateTime(d.year, d.month, d.day);
  }

  /// The anchor's month+day carried into [year], clamped to the month's
  /// last day so Feb-29 resolves to Feb-28 when the year isn't leap.
  static DateTime _yearlyOn(DateTime anchor, int year) {
    final cap = LedgerDates.daysInMonth(DateTime(year, anchor.month));
    return DateTime(year, anchor.month, anchor.day <= cap ? anchor.day : cap);
  }

  static int _byWhen(
      ({Event event, DateTime on}) a, ({Event event, DateTime on}) b) {
    final byDate = a.on.compareTo(b.on);
    if (byDate != 0) return byDate;
    // All-day entries lead the day's list.
    return (a.event.timeMinutes ?? -1).compareTo(b.event.timeMinutes ?? -1);
  }
}
