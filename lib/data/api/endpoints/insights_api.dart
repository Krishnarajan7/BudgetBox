import '../api_client.dart';
import 'wire.dart';

/// The month, told back. Every conditional page is nullable on purpose: a
/// month with no evidence stays quiet rather than filling the space with a
/// sentence that means nothing.
class InsightsApi {
  const InsightsApi(this._c);

  final BbxClient _c;

  /// [month] is a month key, 'yyyy-MM'; omitted it means this month in IST.
  Future<MonthStoryOut> monthStory({String? month}) async =>
      MonthStoryOut.fromJson(
        wireObject(await _c.get('/v1/insights/month-story', {'month': month})),
      );
}

class MonthStoryOut {
  const MonthStoryOut({
    required this.month,
    required this.label,
    required this.spentPaise,
    required this.incomePaise,
    required this.keptPaise,
    required this.quietDays,
    required this.vsLastMonth,
    required this.flows,
    required this.topCategory,
    required this.biggestDay,
    required this.quietestWeek,
    required this.budgetHeld,
    required this.goalMoved,
  });

  /// A month key, 'yyyy-MM'.
  final String month;

  /// The month as it should be written on the page — 'July 2026'.
  final String label;
  final int spentPaise;
  final int incomePaise;
  final int keptPaise;

  /// Days with nothing on them at all.
  final int quietDays;
  final VsLastMonth vsLastMonth;

  /// In and out, largest first — the shape of the month.
  final List<FlowOut> flows;

  /// Null in a month with nothing spent.
  final NamedAmount? topCategory;
  final DayAmount? biggestDay;

  /// Only present when the month actually had a quiet week worth pointing at.
  final QuietWeekOut? quietestWeek;

  /// The budget that held its line, when one did.
  final BudgetHeldOut? budgetHeld;

  /// The goal that moved, when one did.
  final GoalMovedOut? goalMoved;

  factory MonthStoryOut.fromJson(Map<String, dynamic> json) => MonthStoryOut(
        month: json.text('month'),
        label: json.text('label'),
        spentPaise: json.whole('spent_paise'),
        incomePaise: json.whole('income_paise'),
        keptPaise: json.whole('kept_paise'),
        quietDays: json.whole('quiet_days'),
        vsLastMonth: json.object('vs_last_month', VsLastMonth.fromJson),
        flows: json.objects('flows', FlowOut.fromJson),
        topCategory: json.objectOrNull('top_category', NamedAmount.fromJson),
        biggestDay: json.objectOrNull('biggest_day', DayAmount.fromJson),
        quietestWeek:
            json.objectOrNull('quietest_week', QuietWeekOut.fromJson),
        budgetHeld: json.objectOrNull('budget_held', BudgetHeldOut.fromJson),
        goalMoved: json.objectOrNull('goal_moved', GoalMovedOut.fromJson),
      );
}

class VsLastMonth {
  const VsLastMonth({required this.spentDeltaPaise, required this.verdict});

  /// Positive means this month cost more.
  final int spentDeltaPaise;

  /// The server's own wording for it — shown, not switched on.
  final String verdict;

  factory VsLastMonth.fromJson(Map<String, dynamic> json) => VsLastMonth(
        spentDeltaPaise: json.whole('spent_delta_paise'),
        verdict: json.text('verdict'),
      );
}

class FlowOut {
  const FlowOut({
    required this.name,
    required this.paise,
    required this.isIncome,
  });

  final String name;
  final int paise;
  final bool isIncome;

  factory FlowOut.fromJson(Map<String, dynamic> json) => FlowOut(
        name: json.text('name'),
        paise: json.whole('paise'),
        isIncome: json.flag('is_income'),
      );
}

class NamedAmount {
  const NamedAmount({required this.name, required this.paise});

  final String name;
  final int paise;

  factory NamedAmount.fromJson(Map<String, dynamic> json) => NamedAmount(
        name: json.text('name'),
        paise: json.whole('paise'),
      );
}

class DayAmount {
  const DayAmount({required this.date, required this.paise});

  /// 'yyyy-MM-dd'.
  final String date;
  final int paise;

  factory DayAmount.fromJson(Map<String, dynamic> json) => DayAmount(
        date: json.day('date'),
        paise: json.whole('paise'),
      );
}

/// The calmest stretch of the month, given as days of the month rather than
/// dates because that is how the page says it: 'the 8th to the 14th'.
class QuietWeekOut {
  const QuietWeekOut({
    required this.startDay,
    required this.endDay,
    required this.spentPaise,
    required this.projectedPaise,
  });

  final int startDay;
  final int endDay;
  final int spentPaise;

  /// What a whole month at that week's rate would have cost.
  final int projectedPaise;

  factory QuietWeekOut.fromJson(Map<String, dynamic> json) => QuietWeekOut(
        startDay: json.whole('start_day'),
        endDay: json.whole('end_day'),
        spentPaise: json.whole('spent_paise'),
        projectedPaise: json.whole('projected_paise'),
      );
}

class BudgetHeldOut {
  const BudgetHeldOut({
    required this.budgetId,
    required this.name,
    required this.limitPaise,
    required this.spentPaise,
    required this.sparePaise,
    required this.spareYearPaise,
    required this.usage,
  });

  final String budgetId;
  final String name;
  final int limitPaise;
  final int spentPaise;

  /// What was left over.
  final int sparePaise;

  /// The same slack at a year's scale — what holding this line is worth.
  final int spareYearPaise;

  /// Spent over limit, 0…1 — a ratio, not money.
  final double usage;

  factory BudgetHeldOut.fromJson(Map<String, dynamic> json) => BudgetHeldOut(
        budgetId: json.text('budget_id'),
        name: json.text('name'),
        limitPaise: json.whole('limit_paise'),
        spentPaise: json.whole('spent_paise'),
        sparePaise: json.whole('spare_paise'),
        spareYearPaise: json.whole('spare_year_paise'),
        usage: json.real('usage'),
      );
}

class GoalMovedOut {
  const GoalMovedOut({
    required this.goalId,
    required this.name,
    required this.movedPaise,
    required this.remainingPaise,
    required this.monthsLeft,
    required this.reached,
  });

  final String goalId;
  final String name;

  /// What went in this month.
  final int movedPaise;
  final int remainingPaise;

  /// At this month's rate; null when there is no rate to project from.
  final int? monthsLeft;
  final bool reached;

  factory GoalMovedOut.fromJson(Map<String, dynamic> json) => GoalMovedOut(
        goalId: json.text('goal_id'),
        name: json.text('name'),
        movedPaise: json.whole('moved_paise'),
        remainingPaise: json.whole('remaining_paise'),
        monthsLeft: json.wholeOrNull('months_left'),
        reached: json.flag('reached'),
      );
}
