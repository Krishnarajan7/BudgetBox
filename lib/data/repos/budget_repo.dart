import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../db.dart';
import 'budget_math.dart';

/// A budget joined to what actually happened against it this period.
class BudgetView {
  const BudgetView({
    required this.budget,
    required this.category,
    required this.pace,
  });

  final Budget budget;

  /// Null for an overall budget that isn't tied to one category.
  final Category? category;
  final BudgetPace pace;

  String get name => category?.name ?? budget.name;
  String get icon => category?.icon ?? 'circle';
}

class BudgetRepo {
  BudgetRepo(this._db);

  final LedgerDb _db;

  Stream<List<Budget>> watchAll() {
    final q = _db.select(_db.budgets)
      ..where((b) => b.archived.equals(false));
    return q.watch();
  }

  Future<int> create({
    required String name,
    required int limitPaise,
    int? categoryId,
    BudgetPeriod period = BudgetPeriod.month,
    BudgetKind kind = BudgetKind.all,
    bool rollover = false,
  }) {
    return _db.into(_db.budgets).insert(
          BudgetsCompanion.insert(
            name: name,
            limitPaise: limitPaise,
            period: period,
            kind: kind,
            categoryId: Value(categoryId),
            rollover: Value(rollover),
          ),
        );
  }

  Future<void> setLimit(int budgetId, int limitPaise) {
    return (_db.update(_db.budgets)..where((b) => b.id.equals(budgetId)))
        .write(BudgetsCompanion(limitPaise: Value(limitPaise)));
  }

  Future<void> archive(int budgetId) {
    return (_db.update(_db.budgets)..where((b) => b.id.equals(budgetId)))
        .write(const BudgetsCompanion(archived: Value(true)));
  }

  /// Budgets with this period's real spend and forecast folded in, heaviest
  /// spender first. [upcomingByCategory] lets the caller count committed but
  /// unposted bills toward the projection.
  Stream<List<BudgetView>> watchViews(
    DateTime month, {
    Map<int, int> upcomingByCategory = const {},
  }) {
    final from = LedgerDates.monthStart(month);
    final to = LedgerDates.monthEnd(month);
    final now = DateTime.now();
    final elapsed = (now.isAfter(to) ? LedgerDates.daysInMonth(month) : now.day)
        .clamp(1, LedgerDates.daysInMonth(month));

    final query = _db.select(_db.budgets).join([
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.budgets.categoryId),
      ),
    ])
      ..where(_db.budgets.archived.equals(false));

    return query.watch().asyncMap((rows) async {
      final views = <BudgetView>[];
      for (final row in rows) {
        final budget = row.readTable(_db.budgets);
        final category = row.readTableOrNull(_db.categories);

        final sum = _db.txns.amountPaise.sum();
        final spendQuery = _db.selectOnly(_db.txns)
          ..addColumns([sum])
          ..where(
            _db.txns.type.equalsValue(TxnType.expense) &
                _db.txns.at.isBiggerOrEqualValue(from) &
                _db.txns.at.isSmallerThanValue(to) &
                (budget.categoryId == null
                    ? const Constant(true)
                    : _db.txns.categoryId.equals(budget.categoryId!)),
          );
        final spent = (await spendQuery.getSingle()).read(sum) ?? 0;

        views.add(BudgetView(
          budget: budget,
          category: category,
          pace: BudgetPace(
            spentPaise: spent,
            limitPaise: budget.limitPaise,
            elapsedDays: elapsed,
            totalDays: LedgerDates.daysInMonth(month),
            upcomingPaise: budget.categoryId == null
                ? 0
                : (upcomingByCategory[budget.categoryId!] ?? 0),
          ),
        ));
      }
      views.sort((a, b) => b.pace.spentPaise.compareTo(a.pace.spentPaise));
      return views;
    });
  }

  /// Redistribute the same total across categories in proportion to what was
  /// actually spent — the monthly "my budget is wrong" moment, in one tap.
  Future<void> rebalance(List<BudgetView> views) async {
    final total = views.fold(0, (s, v) => s + v.pace.limitPaise);
    final spent = views.fold(0, (s, v) => s + v.pace.spentPaise);
    if (spent <= 0 || total <= 0) return;

    await _db.batch((b) {
      var assigned = 0;
      for (final (i, v) in views.indexed) {
        // Round to whole rupees, and give the last row the remainder so the
        // total never drifts.
        final share = i == views.length - 1
            ? total - assigned
            : ((total * v.pace.spentPaise / spent) / 100).round() * 100;
        assigned += share;
        b.update(
          _db.budgets,
          BudgetsCompanion(limitPaise: Value(share)),
          where: (t) => t.id.equals(v.budget.id),
        );
      }
    });
  }

  /// Proposes a budget per category from the last [months] of real spending,
  /// rounded to the nearest ₹100 — never round guesses.
  Future<Map<int, int>> suggestFromHistory({int months = 3}) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - months);
    final sum = _db.txns.amountPaise.sum();
    final q = _db.selectOnly(_db.txns)
      ..addColumns([_db.txns.categoryId, sum])
      ..where(_db.txns.type.equalsValue(TxnType.expense) &
          _db.txns.categoryId.isNotNull() &
          _db.txns.at.isBiggerOrEqualValue(from) &
          _db.txns.at.isSmallerThanValue(LedgerDates.monthStart(now)))
      ..groupBy([_db.txns.categoryId]);

    final rows = await q.get();
    return {
      for (final r in rows)
        r.read(_db.txns.categoryId)!:
            (((r.read(sum) ?? 0) / months) / 10000).round() * 10000,
    };
  }
}
