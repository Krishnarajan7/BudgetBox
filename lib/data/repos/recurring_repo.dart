import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../db.dart';
import 'txn_repo.dart';

/// A recurring charge with its next landing date resolved.
class DueItem {
  const DueItem({required this.recurring, required this.due});

  final Recurring recurring;
  final DateTime due;

  bool get isBill => recurring.kind == RecurringKind.bill;
}

class RecurringRepo {
  RecurringRepo(this._db, this._txns);

  final LedgerDb _db;
  final TxnRepo _txns;

  Stream<List<Recurring>> watchAll() {
    final q = _db.select(_db.recurrings)
      ..where((r) => r.active.equals(true))
      ..orderBy([(r) => OrderingTerm.asc(r.dayOfMonth)]);
    return q.watch();
  }

  Future<int> create({
    required String title,
    required int amountPaise,
    required int accountId,
    required int dayOfMonth,
    required RecurringKind kind,
    int? categoryId,
    int everyMonths = 1,
  }) {
    final next = nextDate(dayOfMonth, everyMonths, DateTime.now());
    return _db.into(_db.recurrings).insert(
          RecurringsCompanion.insert(
            title: title,
            amountPaise: amountPaise,
            accountId: accountId,
            dayOfMonth: dayOfMonth,
            kind: kind,
            categoryId: Value(categoryId),
            everyMonths: Value(everyMonths),
            nextDue: LedgerDates.dayKey(next),
          ),
        );
  }

  Future<void> stop(int id) {
    return (_db.update(_db.recurrings)..where((r) => r.id.equals(id)))
        .write(const RecurringsCompanion(active: Value(false)));
  }

  /// The next time this charge lands on or after [from], with the day of
  /// month clamped so the 31st still works in February.
  static DateTime nextDate(int dayOfMonth, int everyMonths, DateTime from) {
    var year = from.year;
    var month = from.month;
    for (var i = 0; i < 60; i++) {
      final lastDay = DateTime(year, month + 1, 0).day;
      final candidate = DateTime(year, month, dayOfMonth.clamp(1, lastDay));
      if (!candidate.isBefore(DateTime(from.year, from.month, from.day))) {
        return candidate;
      }
      month += everyMonths;
      if (month > 12) {
        year += (month - 1) ~/ 12;
        month = (month - 1) % 12 + 1;
      }
    }
    return DateTime(year, month, dayOfMonth);
  }

  /// Everything landing between now and [days] out, soonest first.
  Stream<List<DueItem>> watchUpcoming({int days = 45}) {
    final now = DateTime.now();
    final horizon = now.add(Duration(days: days));
    return watchAll().map((rows) {
      final items = <DueItem>[];
      for (final r in rows) {
        final due = nextDate(r.dayOfMonth, r.everyMonths, now);
        if (due.isAfter(horizon)) continue;
        items.add(DueItem(recurring: r, due: due));
      }
      items.sort((a, b) => a.due.compareTo(b.due));
      return items;
    });
  }

  /// What this month has already promised away — the honest number behind
  /// "left to spend". Only counts charges that haven't been paid yet.
  Stream<int> watchCommittedThisMonth() {
    final now = DateTime.now();
    final end = LedgerDates.monthEnd(now);
    return watchAll().asyncMap((rows) async {
      var total = 0;
      for (final r in rows) {
        final due = nextDate(r.dayOfMonth, r.everyMonths, now);
        if (!due.isBefore(end)) continue;
        final paid = await _paidThisMonth(r);
        if (!paid) total += r.amountPaise;
      }
      return total;
    });
  }

  /// Committed-but-unpaid amounts per category, for budget projections.
  Future<Map<int, int>> upcomingByCategory() async {
    final now = DateTime.now();
    final end = LedgerDates.monthEnd(now);
    final rows = await (_db.select(_db.recurrings)
          ..where((r) => r.active.equals(true)))
        .get();
    final out = <int, int>{};
    for (final r in rows) {
      if (r.categoryId == null) continue;
      final due = nextDate(r.dayOfMonth, r.everyMonths, now);
      if (!due.isBefore(end)) continue;
      if (await _paidThisMonth(r)) continue;
      out[r.categoryId!] = (out[r.categoryId!] ?? 0) + r.amountPaise;
    }
    return out;
  }

  Future<bool> _paidThisMonth(Recurring r) async {
    final now = DateTime.now();
    final count = _db.txns.id.count();
    final q = _db.selectOnly(_db.txns)
      ..addColumns([count])
      ..where(_db.txns.recurringId.equals(r.id) &
          _db.txns.at.isBiggerOrEqualValue(LedgerDates.monthStart(now)) &
          _db.txns.at.isSmallerThanValue(LedgerDates.monthEnd(now)));
    return ((await q.getSingle()).read(count) ?? 0) > 0;
  }

  /// Mark a recurring charge as actually paid — writes the real entry and
  /// advances the schedule.
  Future<int> markPaid(Recurring r, {int? amountPaise}) async {
    final id = await _txns.addExpense(
      amountPaise: amountPaise ?? r.amountPaise,
      accountId: r.accountId,
      categoryId: r.categoryId,
      title: r.title,
      recurringId: r.id,
    );
    final next = nextDate(
      r.dayOfMonth,
      r.everyMonths,
      DateTime.now().add(const Duration(days: 1)),
    );
    await (_db.update(_db.recurrings)..where((x) => x.id.equals(r.id)))
        .write(RecurringsCompanion(nextDue: Value(LedgerDates.dayKey(next))));
    return id;
  }

  /// Yearly cost of everything on the shelf, cadences normalised.
  Future<int> yearlyTotal({RecurringKind? kind}) async {
    final rows = await (_db.select(_db.recurrings)
          ..where((r) => r.active.equals(true)))
        .get();
    return rows
        .where((r) => kind == null || r.kind == kind)
        .fold<int>(0, (s, r) => s + r.amountPaise * (12 ~/ r.everyMonths));
  }
}
