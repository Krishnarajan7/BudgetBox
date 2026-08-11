import 'package:drift/drift.dart';

import '../db.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';
import 'txn_repo.dart';

/// A goal and the real, tagged entries behind it — never a separate ledger,
/// so it can't drift out of step with the book.
class GoalView {
  const GoalView({
    required this.goal,
    required this.donePaise,
    required this.entryCount,
  });

  final Goal goal;
  final int donePaise;
  final int entryCount;

  int get remainingPaise => (goal.targetPaise - donePaise).clamp(0, 1 << 62);
  double get fraction =>
      goal.targetPaise <= 0 ? 1 : (donePaise / goal.targetPaise).clamp(0, 1);
  bool get reached => donePaise >= goal.targetPaise;

  /// Month this lands in at the current rate, or null when there's nothing
  /// to go on yet.
  DateTime? etaFrom(DateTime now) {
    if (reached) return null;
    final monthly = goal.monthlyPaise ?? _impliedMonthly(now);
    if (monthly == null || monthly <= 0) return null;
    final months = (remainingPaise / monthly).ceil();
    return DateTime(now.year, now.month + months);
  }

  /// Average contribution per month so far, if the goal is old enough to
  /// have a rate worth quoting.
  int? _impliedMonthly(DateTime now) {
    if (entryCount == 0) return null;
    final started = goal.targetDate == null
        ? null
        : DateTime.tryParse(goal.targetDate!);
    if (started == null) return null;
    final months = (now.difference(started).inDays / 30).ceil();
    return months <= 0 ? null : donePaise ~/ months;
  }
}

class GoalRepo {
  GoalRepo(this._db, this._txns);

  final LedgerDb _db;
  final TxnRepo _txns;

  Future<int> create({
    required String name,
    required int targetPaise,
    GoalKind kind = GoalKind.save,
    DateTime? targetDate,
    int? monthlyPaise,
  }) {
    return _db.transaction(() async {
      final id = await _db.into(_db.goals).insert(
            GoalsCompanion.insert(
              name: name,
              targetPaise: targetPaise,
              kind: kind,
              targetDate:
                  Value(targetDate?.toIso8601String().split('T').first),
              monthlyPaise: Value(monthlyPaise),
            ),
          );
      await bbxSync.upsert(SyncKinds.goal, id);
      return id;
    });
  }

  Future<void> archive(int id) {
    return _db.transaction(() async {
      await (_db.update(_db.goals)..where((g) => g.id.equals(id)))
          .write(const GoalsCompanion(archived: Value(true)));
      await bbxSync.patch(SyncKinds.goal, id, {'archived': true});
    });
  }

  /// Contribute to a goal: a real entry, tagged, that also moves the account.
  Future<int> contribute({
    required Goal goal,
    required int amountPaise,
    required int accountId,
  }) {
    return _txns.addExpense(
      amountPaise: amountPaise,
      accountId: accountId,
      title: goal.name,
      goalId: goal.id,
    );
  }

  Stream<List<GoalView>> watchViews() {
    final q = _db.select(_db.goals)
      ..where((g) => g.archived.equals(false));
    return q.watch().asyncMap((goals) async {
      final views = <GoalView>[];
      for (final g in goals) {
        final sum = _db.txns.amountPaise.sum();
        final count = _db.txns.id.count();
        final query = _db.selectOnly(_db.txns)
          ..addColumns([sum, count])
          ..where(_db.txns.goalId.equals(g.id));
        final row = await query.getSingle();
        views.add(GoalView(
          goal: g,
          donePaise: row.read(sum) ?? 0,
          entryCount: row.read(count) ?? 0,
        ));
      }
      return views;
    });
  }

  /// The entries that built a goal.
  Stream<List<Txn>> watchEntries(int goalId) {
    final q = _db.select(_db.txns)
      ..where((t) => t.goalId.equals(goalId))
      ..orderBy([(t) => OrderingTerm.desc(t.at)]);
    return q.watch();
  }
}
