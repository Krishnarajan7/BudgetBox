import '../../tables.dart';
import '../api_client.dart';
import 'categories_api.dart';
import 'wire.dart';

/// The lines drawn in advance, and the evidence for whether they held.
///
/// `month` parameters here are month keys — 'yyyy-MM' — not days. Omitted,
/// they mean the current month in IST.
class BudgetsApi {
  const BudgetsApi(this._c);

  final BbxClient _c;

  Future<List<BudgetOut>> list({bool includeArchived = false}) async =>
      wireList(
        await _c.get('/v1/budgets', {'include_archived': includeArchived}),
        BudgetOut.fromJson,
      );

  Future<BudgetOut> upsert(String id, BudgetIn body) async =>
      BudgetOut.fromJson(
        wireObject(await _c.put('/v1/budgets/$id', body.toJson())),
      );

  Future<BudgetOut> patch(String id, BudgetPatch body) async =>
      BudgetOut.fromJson(
        wireObject(await _c.patch('/v1/budgets/$id', body.toJson())),
      );

  /// The Plans page in one call: every budget with its category and where it
  /// stands against the clock, not just against the limit.
  Future<List<BudgetView>> pace({String? month}) async => wireList(
        await _c.get('/v1/budgets/pace', {'month': month}),
        BudgetView.fromJson,
      );

  /// The evidence behind one row: this month's daily climb against an even
  /// pace, and what the last [months] months actually cost.
  Future<BudgetTrail> trail(
    String budgetId, {
    String? month,
    int months = 6,
  }) async =>
      BudgetTrail.fromJson(
        wireObject(
          await _c.get('/v1/budgets/$budgetId/trail', {
            'month': month,
            'months': months,
          }),
        ),
      );

  /// Limits worth setting, read off what the last [months] months actually
  /// cost — a proposal with arithmetic behind it, not a round number.
  Future<List<BudgetSuggestion>> suggestions({int months = 3}) async =>
      wireList(
        await _c.get('/v1/budgets/suggestions', {'months': months}),
        BudgetSuggestion.fromJson,
      );

  /// Move the slack from the budgets that are under to the ones that are over,
  /// server-side and atomic, so no half-rebalanced state can exist.
  Future<List<BudgetOut>> rebalance(RebalanceIn body, {String? month}) async =>
      wireList(
        await _c.post(
          pathWithQuery('/v1/budgets/rebalance', {'month': month}),
          body.toJson(),
        ),
        BudgetOut.fromJson,
      );

  /// Hand-pick a transaction into an `added` budget — the trip book's way of
  /// counting only what belongs to the trip.
  Future<void> addTxn(String budgetId, String txnId) =>
      _c.put('/v1/budgets/$budgetId/txns/$txnId', const {});

  Future<void> removeTxn(String budgetId, String txnId) =>
      _c.delete('/v1/budgets/$budgetId/txns/$txnId');
}

/// Where a budget stands. `pending` is an honest fourth answer: too early in
/// the month for the projection to mean anything yet.
enum BudgetStatus { onPace, projectedOver, over, pending }

final budgetStatusWire = WireEnum<BudgetStatus>('budget status', const {
  'on_pace': BudgetStatus.onPace,
  'projected_over': BudgetStatus.projectedOver,
  'over': BudgetStatus.over,
  'pending': BudgetStatus.pending,
});

class BudgetOut {
  const BudgetOut({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.limitPaise,
    required this.period,
    required this.kind,
    required this.rollover,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// Null means an overall budget — every category counts against it.
  final String? categoryId;
  final int limitPaise;
  final BudgetPeriod period;
  final BudgetKind kind;
  final bool rollover;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory BudgetOut.fromJson(Map<String, dynamic> json) => BudgetOut(
        id: json.text('id'),
        name: json.text('name'),
        categoryId: json.textOrNull('category_id'),
        limitPaise: json.whole('limit_paise'),
        period: json.enumAt('period', budgetPeriodWire),
        kind: json.enumAt('kind', budgetKindWire),
        rollover: json.flag('rollover'),
        archived: json.flag('archived'),
        createdAt: json.instant('created_at'),
        updatedAt: json.instant('updated_at'),
      );
}

class BudgetIn {
  const BudgetIn({
    required this.name,
    required this.limitPaise,
    required this.period,
    this.categoryId,
    this.kind = BudgetKind.all,
    this.rollover = false,
  });

  final String name;
  final int limitPaise;
  final BudgetPeriod period;
  final String? categoryId;
  final BudgetKind kind;
  final bool rollover;

  Map<String, dynamic> toJson() => {
        'name': name,
        'limit_paise': limitPaise,
        'period': budgetPeriodWire.toWire(period),
        'category_id': categoryId,
        'kind': budgetKindWire.toWire(kind),
        'rollover': rollover,
      };
}

/// Category, period and kind are fixed once set — changing them would rewrite
/// history. Null means "leave it alone".
class BudgetPatch {
  const BudgetPatch({this.name, this.limitPaise, this.rollover, this.archived});

  final String? name;
  final int? limitPaise;
  final bool? rollover;
  final bool? archived;

  Map<String, dynamic> toJson() => (WireBody()
        ..maybe('name', name)
        ..maybe('limit_paise', limitPaise)
        ..maybe('rollover', rollover)
        ..maybe('archived', archived))
      .build();
}

/// One Plans row, assembled server-side: the budget, its category, and the
/// pace maths for the window it is being judged over.
class BudgetView {
  const BudgetView({
    required this.budget,
    required this.category,
    required this.pace,
    required this.windowStart,
    required this.windowEnd,
  });

  final BudgetOut budget;

  /// Null for an overall budget, or when the category has been removed.
  final CategoryOut? category;
  final PaceOut pace;

  /// 'yyyy-MM-dd' bounds of the window being measured; null for a custom
  /// budget with no dates yet.
  final String? windowStart;
  final String? windowEnd;

  factory BudgetView.fromJson(Map<String, dynamic> json) => BudgetView(
        budget: json.object('budget', BudgetOut.fromJson),
        category: json.objectOrNull('category', CategoryOut.fromJson),
        pace: json.object('pace', PaceOut.fromJson),
        windowStart: json.dayOrNull('window_start'),
        windowEnd: json.dayOrNull('window_end'),
      );
}

/// Spending measured against the clock, not just against the limit.
class PaceOut {
  const PaceOut({
    required this.limitPaise,
    required this.spentPaise,
    required this.remainingPaise,
    required this.upcomingPaise,
    required this.projectedPaise,
    required this.projectedOverspendPaise,
    required this.elapsedDays,
    required this.totalDays,
    required this.fractionElapsed,
    required this.fractionSpent,
    required this.status,
  });

  final int limitPaise;
  final int spentPaise;

  /// Limit minus spent — can go negative, and is allowed to.
  final int remainingPaise;

  /// Known future charges landing inside this window.
  final int upcomingPaise;
  final int projectedPaise;
  final int projectedOverspendPaise;
  final int elapsedDays;
  final int totalDays;

  /// Ratios, not money — the only doubles in this file.
  final double fractionElapsed;
  final double fractionSpent;
  final BudgetStatus status;

  factory PaceOut.fromJson(Map<String, dynamic> json) => PaceOut(
        limitPaise: json.whole('limit_paise'),
        spentPaise: json.whole('spent_paise'),
        remainingPaise: json.whole('remaining_paise'),
        upcomingPaise: json.whole('upcoming_paise'),
        projectedPaise: json.whole('projected_paise'),
        projectedOverspendPaise: json.whole('projected_overspend_paise'),
        elapsedDays: json.whole('elapsed_days'),
        totalDays: json.whole('total_days'),
        fractionElapsed: json.real('fraction_elapsed'),
        fractionSpent: json.real('fraction_spent'),
        status: json.enumAt('status', budgetStatusWire),
      );
}

class BudgetTrail {
  const BudgetTrail({
    required this.budgetId,
    required this.limitPaise,
    required this.months,
    required this.dailyCumulativePaise,
    required this.evenPacePaise,
    required this.heldMonthsRunning,
  });

  final String budgetId;
  final int limitPaise;

  /// Oldest first — the sparkline behind the row.
  final List<MonthSpend> months;

  /// This month's running total, one entry per elapsed day.
  final List<int> dailyCumulativePaise;

  /// What an even spend would have looked like on those same days.
  final List<int> evenPacePaise;

  /// 'held its line N months running' — zero when there is no streak, rather
  /// than a guess.
  final int heldMonthsRunning;

  factory BudgetTrail.fromJson(Map<String, dynamic> json) => BudgetTrail(
        budgetId: json.text('budget_id'),
        limitPaise: json.whole('limit_paise'),
        months: json.objects('months', MonthSpend.fromJson),
        dailyCumulativePaise: json.wholes('daily_cumulative_paise'),
        evenPacePaise: json.wholes('even_pace_paise'),
        heldMonthsRunning: json.whole('held_months_running'),
      );
}

class MonthSpend {
  const MonthSpend({
    required this.month,
    required this.spentPaise,
    required this.held,
  });

  /// A month key, 'yyyy-MM'.
  final String month;
  final int spentPaise;
  final bool held;

  factory MonthSpend.fromJson(Map<String, dynamic> json) => MonthSpend(
        month: json.text('month'),
        spentPaise: json.whole('spent_paise'),
        held: json.flag('held'),
      );
}

class BudgetSuggestion {
  const BudgetSuggestion({
    required this.categoryId,
    required this.averageSpentPaise,
    required this.suggestedLimitPaise,
    required this.months,
  });

  final String categoryId;
  final int averageSpentPaise;
  final int suggestedLimitPaise;

  /// How many months the average is drawn from — the weight of the evidence.
  final int months;

  factory BudgetSuggestion.fromJson(Map<String, dynamic> json) =>
      BudgetSuggestion(
        categoryId: json.text('category_id'),
        averageSpentPaise: json.whole('average_spent_paise'),
        suggestedLimitPaise: json.whole('suggested_limit_paise'),
        months: json.whole('months'),
      );
}

class RebalanceIn {
  const RebalanceIn(this.budgetIds);

  /// The budgets taking part; slack moves only between these.
  final List<String> budgetIds;

  Map<String, dynamic> toJson() => {'budget_ids': budgetIds};
}
