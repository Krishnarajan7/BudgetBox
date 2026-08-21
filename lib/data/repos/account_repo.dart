import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../db.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';
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
    return _db.transaction(() async {
      final id = await _db
          .into(_db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: name,
              kind: kind,
              balancePaise: Value(openingBalancePaise),
            ),
          );
      await bbxSync.upsert(SyncKinds.account, id);
      // Upstream a balance is derived, never stored, so the opening figure
      // travels as a confirmed reading rather than a column.
      if (openingBalancePaise != 0) {
        await bbxSync.anchor(id, openingBalancePaise, DateTime.now());
      }
      return id;
    });
  }

  /// "Update balance" on Worth: records the confirmed figure and refreshes
  /// the as-of date the staleness cue reads.
  Future<void> setBalance(int accountId, int balancePaise) async {
    final at = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(
        _db.accounts,
      )..where((a) => a.id.equals(accountId))).write(
        AccountsCompanion(balancePaise: Value(balancePaise), asOf: Value(at)),
      );
      await TxnRepo.snapshotToday(_db, accountId);
      await bbxSync.anchor(accountId, balancePaise, at);
    });
  }

  /// What an expense of [amountPaise] against [accountId] would overdraw the
  /// pocket by, or null when it wouldn't.
  ///
  /// The rule here is the *same* rule [TxnRepo] applies when it moves a
  /// balance, deliberately duplicated rather than approximated:
  ///
  /// * An entry dated before the account's anchor doesn't touch the figure at
  ///   all — the money left the pocket before the pocket was counted — so
  ///   filling in last Tuesday can never overdraw anything.
  /// * A liability is asked to grow, not shrink; "not enough in it" is not a
  ///   sentence about a credit card.
  /// * A pocket nobody has ever counted says nothing. A brand-new account
  ///   sits at zero because no figure was declared, not because it is empty,
  ///   and a book that stopped to argue about every entry until its owner
  ///   finished the setup ritual would be unusable. "Counted" means the
  ///   figure is above zero, or the pocket has at least one reading behind
  ///   it — either way, someone has told the book something true about it.
  ///
  /// Anything this returns is a real, arithmetical shortfall the book is
  /// about to write down, which is why it is worth stopping for.
  Future<({Account account, int shortPaise})?> shortfall({
    required int accountId,
    required int amountPaise,
    DateTime? at,
  }) async {
    final account = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(accountId))).getSingleOrNull();
    if (account == null || account.kind == AccountKind.liability) return null;
    if ((at ?? DateTime.now()).isBefore(account.asOf)) return null;
    if (account.balancePaise <= 0 && !await _everCounted(accountId)) {
      return null;
    }
    final short = amountPaise - account.balancePaise;
    return short > 0 ? (account: account, shortPaise: short) : null;
  }

  /// Has this pocket ever had a reading taken? One snapshot is enough — it
  /// means a figure was declared, or money moved through it and the book
  /// watched.
  Future<bool> _everCounted(int accountId) async {
    final row =
        await (_db.select(_db.balanceSnapshots)
              ..where((s) => s.accountId.equals(accountId))
              ..limit(1))
            .get();
    return row.isNotEmpty;
  }

  /// The last [points] daily readings for an account, oldest first — the
  /// sparkline's memory. Falls back to a flat line when history is short.
  Future<List<double>> spark(int accountId, {int points = 8}) async {
    final rows =
        await (_db.select(_db.balanceSnapshots)
              ..where((s) => s.accountId.equals(accountId))
              ..orderBy([(s) => OrderingTerm.desc(s.date)])
              ..limit(points))
            .get();
    if (rows.length < 2) {
      final acct = await (_db.select(
        _db.accounts,
      )..where((a) => a.id.equals(accountId))).getSingle();
      return [acct.balancePaise.toDouble(), acct.balancePaise.toDouble()];
    }
    return [for (final r in rows.reversed) r.balancePaise.toDouble()];
  }

  /// Actual persisted readings, without inventing a second point for a
  /// drawable row sparkline. The history sheet uses this so one reading is
  /// never reported as two identical readings.
  Future<List<double>> balanceReadings(int accountId, {int points = 30}) async {
    final rows =
        await (_db.select(_db.balanceSnapshots)
              ..where((s) => s.accountId.equals(accountId))
              ..orderBy([(s) => OrderingTerm.desc(s.date)])
              ..limit(points))
            .get();
    return [for (final row in rows.reversed) row.balancePaise.toDouble()];
  }

  /// Daily net worth over the trailing [days], forward-filling gaps —
  /// assets minus liabilities, ending at today's true figure.
  Future<List<int>> netWorthHistory({int days = 180}) async {
    final accounts = await (_db.select(
      _db.accounts,
    )..where((a) => a.archived.equals(false))).get();
    if (accounts.isEmpty) return const [];
    final sign = {
      for (final a in accounts) a.id: a.kind == AccountKind.liability ? -1 : 1,
    };

    final from = DateTime.now().subtract(Duration(days: days));
    final snaps =
        await (_db.select(_db.balanceSnapshots)
              ..where(
                (s) => s.date.isBiggerOrEqualValue(LedgerDates.dayKey(from)),
              )
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
    for (
      var d = DateTime.parse(snaps.first.date);
      !d.isAfter(today);
      d = d.add(const Duration(days: 1))
    ) {
      final readings = byDay[LedgerDates.dayKey(d)];
      if (readings != null) carried.addAll(readings);
      if (carried.isEmpty) continue;
      var total = 0;
      carried.forEach((id, paise) => total += paise * (sign[id] ?? 0));
      series.add(total);
    }
    return series.isEmpty ? [await netWorthPaise()] : series;
  }

  /// Per-account change over the trailing [days]: today's figure minus the
  /// reading that stood when the window opened (carried forward, same rule
  /// as [netWorthHistory]). Liabilities are signed so paying one down counts
  /// as growth. An account whose first reading falls inside the window
  /// counts from zero — arriving on the shelf IS the move.
  Future<Map<int, int>> accountDeltas({int days = 30}) async {
    final accounts = await (_db.select(
      _db.accounts,
    )..where((a) => a.archived.equals(false))).get();
    final fromKey = LedgerDates.dayKey(
      DateTime.now().subtract(Duration(days: days)),
    );
    final deltas = <int, int>{};
    for (final a in accounts) {
      final sign = a.kind == AccountKind.liability ? -1 : 1;
      final before =
          await (_db.select(_db.balanceSnapshots)
                ..where(
                  (s) =>
                      s.accountId.equals(a.id) &
                      s.date.isSmallerOrEqualValue(fromKey),
                )
                ..orderBy([(s) => OrderingTerm.desc(s.date)])
                ..limit(1))
              .get();
      final int baseline;
      if (before.isNotEmpty) {
        baseline = before.first.balancePaise;
      } else {
        final any =
            await (_db.select(_db.balanceSnapshots)
                  ..where((s) => s.accountId.equals(a.id))
                  ..limit(1))
                .get();
        // No reading at all: the account predates its own history — treat
        // it as unmoved rather than inventing a from-zero jump.
        baseline = any.isEmpty ? a.balancePaise : 0;
      }
      deltas[a.id] = (a.balancePaise - baseline) * sign;
    }
    return deltas;
  }

  /// Net worth right now: assets minus liabilities.
  Future<int> netWorthPaise() async {
    final rows = await (_db.select(
      _db.accounts,
    )..where((a) => a.archived.equals(false))).get();
    var total = 0;
    for (final a in rows) {
      total += a.kind == AccountKind.liability
          ? -a.balancePaise
          : a.balancePaise;
    }
    return total;
  }
}
