import '../api_client.dart';
import 'wire.dart';

/// One page per day. The day is always the path, never the payload — there is
/// exactly one entry per IST day and the server owns which day that is.
class JournalApi {
  const JournalApi(this._c);

  final BbxClient _c;

  /// Entries inside an inclusive 'yyyy-MM-dd' window.
  Future<List<JournalOut>> between({
    required String fromDay,
    required String toDay,
  }) async =>
      wireList(
        await _c.get('/v1/journal', {'from_day': fromDay, 'to_day': toDay}),
        JournalOut.fromJson,
      );

  /// [month] is a month key, 'yyyy-MM'; omitted it means this month in IST.
  Future<JournalMonth> month({String? month}) async => JournalMonth.fromJson(
        wireObject(await _c.get('/v1/journal/month', {'month': month})),
      );

  /// [day] is 'yyyy-MM-dd'.
  Future<JournalOut> get(String day) async =>
      JournalOut.fromJson(wireObject(await _c.get('/v1/journal/$day')));

  Future<JournalOut> upsert(String day, JournalIn body) async =>
      JournalOut.fromJson(
        wireObject(await _c.put('/v1/journal/$day', body.toJson())),
      );

  Future<void> delete(String day) => _c.delete('/v1/journal/$day');

  /// What the rest of the box already knows about a day, so the page arrives
  /// half-written instead of blank.
  Future<DayFacts> facts(String day) async =>
      DayFacts.fromJson(wireObject(await _c.get('/v1/journal/$day/facts')));
}

class JournalOut {
  const JournalOut({
    required this.date,
    required this.body,
    required this.mood,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 'yyyy-MM-dd' — the page this is.
  final String date;
  final String body;

  /// 1 (rough) … 5 (great); null when the day went unrated, which is not the
  /// same as a middling one.
  final int? mood;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory JournalOut.fromJson(Map<String, dynamic> json) => JournalOut(
        date: json.day('date'),
        body: json.text('body'),
        mood: json.wholeOrNull('mood'),
        createdAt: json.instant('created_at'),
        updatedAt: json.instant('updated_at'),
      );
}

class JournalIn {
  const JournalIn({this.body = '', this.mood});

  final String body;

  /// 1 … 5, or null to leave the day unrated.
  final int? mood;

  Map<String, dynamic> toJson() => {'body': body, 'mood': mood};
}

class JournalMonth {
  const JournalMonth({
    required this.month,
    required this.entries,
    required this.moodDots,
    required this.pagesWritten,
    required this.streakDays,
    required this.moodMoney,
  });

  /// A month key, 'yyyy-MM'.
  final String month;
  final List<JournalOut> entries;

  /// One slot per day of the month, in order; null where the day went unrated.
  final List<int?> moodDots;
  final int pagesWritten;
  final int streakDays;

  /// Null when the month has too little to say anything honest about the line
  /// between mood and money.
  final MoodMoneyOut? moodMoney;

  factory JournalMonth.fromJson(Map<String, dynamic> json) => JournalMonth(
        month: json.text('month'),
        entries: json.objects('entries', JournalOut.fromJson),
        moodDots: json.wholesOrNulls('mood_dots'),
        pagesWritten: json.whole('pages_written'),
        streakDays: json.whole('streak_days'),
        moodMoney: json.objectOrNull('mood_money', MoodMoneyOut.fromJson),
      );
}

/// Whether rough days or bright ones cost more.
class MoodMoneyOut {
  const MoodMoneyOut({
    required this.roughDays,
    required this.roughAvgPaise,
    required this.brightDays,
    required this.brightAvgPaise,
    required this.verdict,
  });

  final int roughDays;
  final int roughAvgPaise;
  final int brightDays;
  final int brightAvgPaise;

  /// The server's own wording for it — shown, not switched on.
  final String verdict;

  factory MoodMoneyOut.fromJson(Map<String, dynamic> json) => MoodMoneyOut(
        roughDays: json.whole('rough_days'),
        roughAvgPaise: json.whole('rough_avg_paise'),
        brightDays: json.whole('bright_days'),
        brightAvgPaise: json.whole('bright_avg_paise'),
        verdict: json.text('verdict'),
      );
}

/// What the box already knows about a day.
class DayFacts {
  const DayFacts({
    required this.date,
    required this.spentPaise,
    required this.txnCount,
    required this.focusMinutes,
    required this.notesCount,
  });

  /// 'yyyy-MM-dd'.
  final String date;
  final int spentPaise;
  final int txnCount;
  final int focusMinutes;
  final int notesCount;

  factory DayFacts.fromJson(Map<String, dynamic> json) => DayFacts(
        date: json.day('date'),
        spentPaise: json.whole('spent_paise'),
        txnCount: json.whole('txn_count'),
        focusMinutes: json.whole('focus_minutes'),
        notesCount: json.whole('notes_count'),
      );
}
