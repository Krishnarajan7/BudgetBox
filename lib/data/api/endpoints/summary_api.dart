import '../api_client.dart';
import 'events_api.dart';
import 'pinned_api.dart';
import 'recurring_api.dart';
import 'txns_api.dart';
import 'wire.dart';

/// The read models shaped by screen: a whole page in one call, so Today never
/// has to fan out to six endpoints and stitch them.
class SummaryApi {
  const SummaryApi(this._c);

  final BbxClient _c;

  Future<TodaySummary> today() async =>
      TodaySummary.fromJson(wireObject(await _c.get('/v1/summary/today')));

  /// [month] is a month key, 'yyyy-MM'; omitted it means this month in IST.
  Future<MonthSummary> month({String? month}) async => MonthSummary.fromJson(
        wireObject(await _c.get('/v1/summary/month', {'month': month})),
      );

  /// An inclusive 'yyyy-MM-dd' window with everything the calendar draws:
  /// money per day, the charges landing in it, and the events beside them.
  Future<CalendarWindow> calendar({
    required String fromDay,
    required String toDay,
  }) async =>
      CalendarWindow.fromJson(
        wireObject(
          await _c.get('/v1/summary/calendar', {
            'from_day': fromDay,
            'to_day': toDay,
          }),
        ),
      );
}

/// The Today page. The `window_*` fields are the salary period, not the
/// calendar month — the span the spending is actually judged over.
class TodaySummary {
  const TodaySummary({
    required this.day,
    required this.spentTodayPaise,
    required this.spentYesterdayPaise,
    required this.todayTxns,
    required this.pinned,
    required this.upcoming,
    required this.committedPaise,
    required this.sealed,
    required this.sealStreakDays,
    required this.quietDays,
    required this.windowStart,
    required this.windowEnd,
    required this.windowSpentPaise,
    required this.windowElapsedDays,
    required this.windowTotalDays,
  });

  /// 'yyyy-MM-dd' in IST — the server's idea of today, which is the only one
  /// that matters for a seal.
  final String day;
  final int spentTodayPaise;
  final int spentYesterdayPaise;
  final List<TxnOut> todayTxns;
  final List<PinnedOut> pinned;

  /// What is due next.
  final List<DueItem> upcoming;

  /// The weight of everything already promised this window.
  final int committedPaise;
  final bool sealed;
  final int sealStreakDays;

  /// 'yyyy-MM-dd' days in this window with nothing spent at all.
  final List<String> quietDays;

  /// 'yyyy-MM-dd' bounds of the salary window.
  final String windowStart;
  final String windowEnd;
  final int windowSpentPaise;
  final int windowElapsedDays;
  final int windowTotalDays;

  factory TodaySummary.fromJson(Map<String, dynamic> json) => TodaySummary(
        day: json.day('day'),
        spentTodayPaise: json.whole('spent_today_paise'),
        spentYesterdayPaise: json.whole('spent_yesterday_paise'),
        todayTxns: json.objects('today_txns', TxnOut.fromJson),
        pinned: json.objects('pinned', PinnedOut.fromJson),
        upcoming: json.objects('upcoming', DueItem.fromJson),
        committedPaise: json.whole('committed_paise'),
        sealed: json.flag('sealed'),
        sealStreakDays: json.whole('seal_streak_days'),
        quietDays: json.days('quiet_days'),
        windowStart: json.day('window_start'),
        windowEnd: json.day('window_end'),
        windowSpentPaise: json.whole('window_spent_paise'),
        windowElapsedDays: json.whole('window_elapsed_days'),
        windowTotalDays: json.whole('window_total_days'),
      );
}

class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.start,
    required this.end,
    required this.inPaise,
    required this.outPaise,
    required this.keptPaise,
    required this.entryCount,
    required this.dayTotals,
    required this.categories,
    required this.biggestExpense,
    required this.biggestExpenseShare,
    required this.heaviestDay,
    required this.heaviestDayPaise,
    required this.quietDays,
    required this.sealedDays,
    required this.elapsedDays,
    required this.totalDays,
    required this.salaryDayOfMonth,
  });

  /// A month key, 'yyyy-MM'.
  final String month;

  /// 'yyyy-MM-dd' bounds of the period, which follow the salary day when one
  /// is set rather than the calendar.
  final String start;
  final String end;
  final int inPaise;
  final int outPaise;

  /// In minus out — negative months are real and shown as such.
  final int keptPaise;
  final int entryCount;
  final List<DayTotal> dayTotals;
  final List<CategorySlice> categories;

  /// Null in a month with nothing spent.
  final TxnOut? biggestExpense;

  /// Its share of the month's spending, 0…1 — a ratio, not money.
  final double? biggestExpenseShare;

  /// 'yyyy-MM-dd'; null when nothing was spent all month.
  final String? heaviestDay;
  final int heaviestDayPaise;

  /// How many days had nothing on them.
  final int quietDays;

  /// 'yyyy-MM-dd' days already closed.
  final List<String> sealedDays;
  final int elapsedDays;
  final int totalDays;

  /// Null until the setup ritual has been told one.
  final int? salaryDayOfMonth;

  factory MonthSummary.fromJson(Map<String, dynamic> json) => MonthSummary(
        month: json.text('month'),
        start: json.day('start'),
        end: json.day('end'),
        inPaise: json.whole('in_paise'),
        outPaise: json.whole('out_paise'),
        keptPaise: json.whole('kept_paise'),
        entryCount: json.whole('entry_count'),
        dayTotals: json.objects('day_totals', DayTotal.fromJson),
        categories: json.objects('categories', CategorySlice.fromJson),
        biggestExpense: json.objectOrNull('biggest_expense', TxnOut.fromJson),
        biggestExpenseShare: json.realOrNull('biggest_expense_share'),
        heaviestDay: json.dayOrNull('heaviest_day'),
        heaviestDayPaise: json.whole('heaviest_day_paise'),
        quietDays: json.whole('quiet_days'),
        sealedDays: json.days('sealed_days'),
        elapsedDays: json.whole('elapsed_days'),
        totalDays: json.whole('total_days'),
        salaryDayOfMonth: json.wholeOrNull('salary_day_of_month'),
      );
}

class DayTotal {
  const DayTotal({
    required this.date,
    required this.spentPaise,
    required this.earnedPaise,
    required this.entryCount,
  });

  /// 'yyyy-MM-dd'.
  final String date;
  final int spentPaise;
  final int earnedPaise;
  final int entryCount;

  factory DayTotal.fromJson(Map<String, dynamic> json) => DayTotal(
        date: json.day('date'),
        spentPaise: json.whole('spent_paise'),
        earnedPaise: json.whole('earned_paise'),
        entryCount: json.whole('entry_count'),
      );
}

/// Where it went. A null [categoryId] is the uncategorised pile, not a total.
class CategorySlice {
  const CategorySlice({required this.categoryId, required this.spentPaise});

  final String? categoryId;
  final int spentPaise;

  factory CategorySlice.fromJson(Map<String, dynamic> json) => CategorySlice(
        categoryId: json.textOrNull('category_id'),
        spentPaise: json.whole('spent_paise'),
      );
}

class CalendarWindow {
  const CalendarWindow({
    required this.fromDay,
    required this.toDay,
    required this.days,
    required this.charges,
    required this.chargeTotalPaise,
    required this.events,
  });

  /// Inclusive 'yyyy-MM-dd' bounds of what was asked for.
  final String fromDay;
  final String toDay;
  final List<DayMoney> days;

  /// Recurrings landing inside the window.
  final List<DueItem> charges;
  final int chargeTotalPaise;
  final List<OccurrenceOut> events;

  factory CalendarWindow.fromJson(Map<String, dynamic> json) => CalendarWindow(
        fromDay: json.day('from_day'),
        toDay: json.day('to_day'),
        days: json.objects('days', DayMoney.fromJson),
        charges: json.objects('charges', DueItem.fromJson),
        chargeTotalPaise: json.whole('charge_total_paise'),
        events: json.objects('events', OccurrenceOut.fromJson),
      );
}

class DayMoney {
  const DayMoney({
    required this.date,
    required this.spentPaise,
    required this.earnedPaise,
  });

  /// 'yyyy-MM-dd'.
  final String date;
  final int spentPaise;
  final int earnedPaise;

  factory DayMoney.fromJson(Map<String, dynamic> json) => DayMoney(
        date: json.day('date'),
        spentPaise: json.whole('spent_paise'),
        earnedPaise: json.whole('earned_paise'),
      );
}
