import '../../tables.dart';
import '../api_client.dart';
import 'wire.dart';

/// Time spent on purpose. A session is written when it ends, so an abandoned
/// timer leaves nothing behind — [FocusIn.completed] is the difference between
/// a session that counts and one that was merely started.
class FocusApi {
  const FocusApi(this._c);

  final BbxClient _c;

  /// [month] is a month key, 'yyyy-MM'; omitted it means this month in IST.
  Future<List<FocusOut>> sessions({String? month}) async => wireList(
        await _c.get('/v1/focus/sessions', {'month': month}),
        FocusOut.fromJson,
      );

  Future<FocusOut> upsert(String id, FocusIn body) async => FocusOut.fromJson(
        wireObject(await _c.put('/v1/focus/sessions/$id', body.toJson())),
      );

  Future<FocusOut> patch(String id, FocusPatch body) async => FocusOut.fromJson(
        wireObject(await _c.patch('/v1/focus/sessions/$id', body.toJson())),
      );

  Future<StatsOut> stats({String? month}) async => StatsOut.fromJson(
        wireObject(await _c.get('/v1/focus/stats', {'month': month})),
      );
}

class FocusOut {
  const FocusOut({
    required this.id,
    required this.startedAt,
    required this.minutes,
    required this.kind,
    required this.completed,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final DateTime startedAt;
  final int minutes;
  final FocusKind kind;

  /// Only completed work counts towards the records.
  final bool completed;

  /// What it was for; null when it was just time.
  final String? label;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory FocusOut.fromJson(Map<String, dynamic> json) => FocusOut(
        id: json.text('id'),
        startedAt: json.instant('started_at'),
        minutes: json.whole('minutes'),
        kind: json.enumAt('kind', focusKindWire),
        completed: json.flag('completed'),
        label: json.textOrNull('label'),
        createdAt: json.instant('created_at'),
        updatedAt: json.instant('updated_at'),
      );
}

class FocusIn {
  const FocusIn({
    required this.startedAt,
    required this.minutes,
    required this.kind,
    this.completed = false,
    this.label,
  });

  final DateTime startedAt;
  final int minutes;
  final FocusKind kind;
  final bool completed;
  final String? label;

  Map<String, dynamic> toJson() => {
        'started_at': wireInstant(startedAt),
        'minutes': minutes,
        'kind': focusKindWire.toWire(kind),
        'completed': completed,
        'label': label,
      };
}

/// A session's start and kind are fixed once written. The label can be
/// dropped, so it takes an [Opt]; the rest read null as "leave it alone".
class FocusPatch {
  const FocusPatch({this.minutes, this.completed, this.label});

  final int? minutes;
  final bool? completed;
  final Opt<String?>? label;

  Map<String, dynamic> toJson() => (WireBody()
        ..maybe('minutes', minutes)
        ..maybe('completed', completed)
        ..opt('label', label))
      .build();
}

class StatsOut {
  const StatsOut({
    required this.todayWorkMinutes,
    required this.weekMinutes,
    required this.dayMinutes,
    required this.totalMinutes,
    required this.sessions,
    required this.bestDay,
    required this.bestDayMinutes,
    required this.record,
  });

  final int todayWorkMinutes;

  /// Seven entries, Monday first — the week's bars.
  final List<int> weekMinutes;

  /// One entry per day of the month that had any.
  final List<DayMinutes> dayMinutes;

  /// This month's totals, not all time — see [record] for that.
  final int totalMinutes;
  final int sessions;

  /// 'yyyy-MM-dd'; null in a month with no completed work.
  final String? bestDay;
  final int bestDayMinutes;
  final FocusRecord record;

  factory StatsOut.fromJson(Map<String, dynamic> json) => StatsOut(
        todayWorkMinutes: json.whole('today_work_minutes'),
        weekMinutes: json.wholes('week_minutes'),
        dayMinutes: json.objects('day_minutes', DayMinutes.fromJson),
        totalMinutes: json.whole('total_minutes'),
        sessions: json.whole('sessions'),
        bestDay: json.dayOrNull('best_day'),
        bestDayMinutes: json.whole('best_day_minutes'),
        record: json.object('record', FocusRecord.fromJson),
      );
}

class DayMinutes {
  const DayMinutes({required this.date, required this.minutes});

  /// 'yyyy-MM-dd'.
  final String date;
  final int minutes;

  factory DayMinutes.fromJson(Map<String, dynamic> json) => DayMinutes(
        date: json.day('date'),
        minutes: json.whole('minutes'),
      );
}

/// All-time, completed work only: what the best of it has ever looked like.
class FocusRecord {
  const FocusRecord({
    required this.totalMinutes,
    required this.sessions,
    required this.longestMinutes,
    required this.longestAt,
    required this.bestDay,
    required this.bestDayMinutes,
    required this.streakDays,
  });

  final int totalMinutes;
  final int sessions;
  final int longestMinutes;

  /// When the longest session was; null until there has been one.
  final DateTime? longestAt;

  /// 'yyyy-MM-dd'.
  final String? bestDay;
  final int bestDayMinutes;

  /// Consecutive days with work on them, counting back from today.
  final int streakDays;

  factory FocusRecord.fromJson(Map<String, dynamic> json) => FocusRecord(
        totalMinutes: json.whole('total_minutes'),
        sessions: json.whole('sessions'),
        longestMinutes: json.whole('longest_minutes'),
        longestAt: json.instantOrNull('longest_at'),
        bestDay: json.dayOrNull('best_day'),
        bestDayMinutes: json.whole('best_day_minutes'),
        streakDays: json.whole('streak_days'),
      );
}
