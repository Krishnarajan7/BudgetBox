import '../../tables.dart';
import '../api_client.dart';
import 'wire.dart';

/// The dates that aren't money: birthdays, the trip, the exam.
///
/// A stored event has one anchor date; a yearly one is expanded server-side
/// into the concrete observances inside a window, so the calendar never has to
/// do recurrence maths.
class EventsApi {
  const EventsApi(this._c);

  final BbxClient _c;

  /// Concrete observances inside an inclusive 'yyyy-MM-dd' window.
  Future<List<OccurrenceOut>> occurrences({
    required String fromDay,
    required String toDay,
  }) async =>
      wireList(
        await _c.get('/v1/events', {'from_day': fromDay, 'to_day': toDay}),
        OccurrenceOut.fromJson,
      );

  /// The stored rows themselves, unexpanded — what the manager screen edits.
  Future<List<EventOut>> all({bool includeArchived = false}) async => wireList(
        await _c.get('/v1/events/all', {'include_archived': includeArchived}),
        EventOut.fromJson,
      );

  Future<EventOut> upsert(String id, EventIn body) async => EventOut.fromJson(
        wireObject(await _c.put('/v1/events/$id', body.toJson())),
      );

  Future<EventOut> patch(String id, EventPatch body) async => EventOut.fromJson(
        wireObject(await _c.patch('/v1/events/$id', body.toJson())),
      );
}

class EventOut {
  const EventOut({
    required this.id,
    required this.title,
    required this.note,
    required this.date,
    required this.timeMinutes,
    required this.repeat,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? note;

  /// The anchor day, 'yyyy-MM-dd'. A yearly event recurs on its month and day.
  final String date;

  /// Minutes past midnight; null means all-day.
  final int? timeMinutes;
  final EventRepeat repeat;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory EventOut.fromJson(Map<String, dynamic> json) => EventOut(
        id: json.text('id'),
        title: json.text('title'),
        note: json.textOrNull('note'),
        date: json.day('date'),
        timeMinutes: json.wholeOrNull('time_minutes'),
        repeat: json.enumAt('repeat', eventRepeatWire),
        archived: json.flag('archived'),
        createdAt: json.instant('created_at'),
        updatedAt: json.instant('updated_at'),
      );
}

class EventIn {
  const EventIn({
    required this.title,
    required this.date,
    this.note,
    this.timeMinutes,
    this.repeat = EventRepeat.none,
  });

  final String title;

  /// 'yyyy-MM-dd'.
  final String date;
  final String? note;
  final int? timeMinutes;
  final EventRepeat repeat;

  Map<String, dynamic> toJson() => {
        'title': title,
        'date': date,
        'note': note,
        'time_minutes': timeMinutes,
        'repeat': eventRepeatWire.toWire(repeat),
      };
}

/// A note and a time of day can both be dropped, so they take an [Opt]; the
/// rest read null as "leave it alone".
class EventPatch {
  const EventPatch({
    this.title,
    this.note,
    this.date,
    this.timeMinutes,
    this.repeat,
    this.archived,
  });

  final String? title;
  final Opt<String?>? note;

  /// 'yyyy-MM-dd'.
  final String? date;

  /// `Opt(null)` makes it an all-day event.
  final Opt<int?>? timeMinutes;
  final EventRepeat? repeat;
  final bool? archived;

  Map<String, dynamic> toJson() => (WireBody()
        ..maybe('title', title)
        ..opt('note', note)
        ..maybe('date', date)
        ..opt('time_minutes', timeMinutes)
        ..maybe('repeat', eventRepeatWire.toWireOrNull(repeat))
        ..maybe('archived', archived))
      .build();
}

/// One concrete observance inside a queried window: the stored row plus the
/// day it actually lands on, which is not the anchor date for a yearly repeat.
class OccurrenceOut {
  const OccurrenceOut({
    required this.event,
    required this.date,
    required this.timeMinutes,
  });

  final EventOut event;

  /// 'yyyy-MM-dd' — the day inside the window.
  final String date;
  final int? timeMinutes;

  factory OccurrenceOut.fromJson(Map<String, dynamic> json) => OccurrenceOut(
        event: json.object('event', EventOut.fromJson),
        date: json.day('date'),
        timeMinutes: json.wholeOrNull('time_minutes'),
      );
}
