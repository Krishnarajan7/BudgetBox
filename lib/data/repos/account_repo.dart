import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../db.dart';
import 'txn_repo.dart';

class AccountRepo {
  AccountRepo(this._db);

  final LedgerDb _db;

  /// One-shot: does any account exist at all? (First-launch check — a
  /// stream's `.first` stalls under widget-test fake async.)
  Future<bool> hasAny() async {
    final row = await (_db.select(_db.accounts)..limit(1)).get();
    return row.isNotEmpty;
  }

  Stream<List<Account>> watchAll({bool includeArchived = false}) {
    final q = _db.select(_db.accounts)
      ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]);
    if (!includeArchived) {
      q.where((a) => a.archived.equals(false));
    }
    return q.watch();
  }

  Future<int> create({
    required String name,
    required AccountKind kind,
    int openingBalancePaise = 0,
  }) {
    return _db.into(_db.accounts).insert(
          AccountsCompanion.insert(
            name: name,
            kind: kind,
            balancePaise: Value(openingBalancePaise),
          ),
        );
  }

  /// "Update balance" on Worth: records the confirmed figure and refreshes
  /// the as-of date the staleness cue reads.
  Future<void> setBalance(int accountId, int balancePaise) async {
    await (_db.update(_db.accounts)..where((a) => a.id.equals(accountId)))
        .write(AccountsCompanion(
      balancePaise: Value(balancePaise),
      asOf: Value(DateTime.now()),
    ));
    await TxnRepo.snapshotToday(_db, accountId);
  }

  /// The last [points] daily readings for an account, oldest first — the
  /// sparkline's memory. Falls back to a flat line when history is short.
  Future<List<double>> spark(int accountId, {int points = 8}) async {
    final rows = await (_db.select(_db.balanceSnapshots)
          ..where((s) => s.accountId.equals(accountId))
          ..orderBy([(s) => OrderingTerm.desc(s.date)])
          ..limit(points))
        .get();
    if (rows.length < 2) {
      final acct = await (_db.select(_db.accounts)
            ..where((a) => a.id.equals(accountId)))
          .getSingle();
      return [acct.balancePaise.toDouble(), acct.balancePaise.toDouble()];
    }
    return [for (final r in rows.reversed) r.balancePaise.toDouble()];
  }

  /// Daily net worth over the trailing [days], forward-filling gaps —
  /// assets minus liabilities, ending at today's true figure.
  Future<List<int>> netWorthHistory({int days = 180}) async {
    final accounts = await (_db.select(_db.accounts)
          ..where((a) => a.archived.equals(false)))
        .get();
    if (accounts.isEmpty) return const [];
    final sign = {
      for (final a in accounts)
        a.id: a.kind == AccountKind.liability ? -1 : 1,
    };

    final from = DateTime.now().subtract(Duration(days: days));
    final snaps = await (_db.select(_db.balanceSnapshots)
          ..where((s) => s.date.isBiggerOrEqualValue(LedgerDates.dayKey(from)))
          ..orderBy([(s) => OrderingTerm.asc(s.date)]))
        .get();
    if (snaps.isEmpty) return [await netWorthPaise()];

    // Walk day by day, carrying each account's last known reading forward.
    final byDay = <String, Map<int, int>>{};
    for (final s in snaps) {
      byDay.putIfAbsent(s.date, () => {})[s.accountId] = s.balancePaise;
    }
    final carried = <int, int>{};
    final series = <int>[];
    final today = DateTime.now();
    for (var d = DateTime.parse(snaps.first.date);
        !d.isAfter(today);
        d = d.add(const Duration(days: 1))) {
      final readings = byDay[LedgerDates.dayKey(d)];
      if (readings != null) carried.addAll(readings);
      if (carried.isEmpty) continue;
      var total = 0;
      carried.forEach((id, paise) => total += paise * (sign[id] ?? 0));
      series.add(total);
    }
    return series.isEmpty ? [await netWorthPaise()] : series;
  }

  /// Net worth right now: assets minus liabilities.
  Future<int> netWorthPaise() async {
    final rows = await (_db.select(_db.accounts)
          ..where((a) => a.archived.equals(false)))
        .get();
    var total = 0;
    for (final a in rows) {
      total += a.kind == AccountKind.liability ? -a.balancePaise : a.balancePaise;
    }
    return total;
  }
}
