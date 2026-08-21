import 'dart:convert';

import 'package:drift/drift.dart';

import '../db.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';
import '../tonight.dart';

/// A title suggestion carrying the category it was last filed under —
/// type "sar", get "Saravana Bhavan" + Food & chai for free.
class TitleSuggestion {
  const TitleSuggestion({required this.title, this.categoryId, this.accountId});

  final String title;
  final int? categoryId;
  final int? accountId;
}

/// All writes to the ledger go through here: every mutation adjusts account
/// balances in the same database transaction and leaves an activity line
/// (the undo/audit trail). The ledger never lies and never loses a stroke.
class TxnRepo {
  TxnRepo(this._db);

  final LedgerDb _db;

  // ————— writes —————

  Future<int> addExpense({
    required int amountPaise,
    required int accountId,
    required String title,
    int? categoryId,
    int? goalId,
    int? recurringId,
    String? note,
    DateTime? at,
  }) {
    assert(amountPaise > 0, 'amounts are positive; type carries direction');
    return _insert(
      TxnsCompanion.insert(
        amountPaise: amountPaise,
        type: TxnType.expense,
        accountId: accountId,
        title: title,
        categoryId: Value(categoryId),
        goalId: Value(goalId),
        recurringId: Value(recurringId),
        note: Value(note),
        at: at ?? DateTime.now(),
      ),
    );
  }

  Future<int> addIncome({
    required int amountPaise,
    required int accountId,
    required String title,
    int? categoryId,
    String? note,
    DateTime? at,
  }) {
    assert(amountPaise > 0);
    return _insert(
      TxnsCompanion.insert(
        amountPaise: amountPaise,
        type: TxnType.income,
        accountId: accountId,
        title: title,
        categoryId: Value(categoryId),
        note: Value(note),
        at: at ?? DateTime.now(),
      ),
    );
  }

  Future<int> addTransfer({
    required int amountPaise,
    required int fromAccountId,
    required int toAccountId,
    String title = 'Transfer',
    DateTime? at,
  }) {
    assert(amountPaise > 0);
    return _insert(
      TxnsCompanion.insert(
        amountPaise: amountPaise,
        type: TxnType.transfer,
        accountId: fromAccountId,
        toAccountId: Value(toAccountId),
        title: title,
        at: at ?? DateTime.now(),
      ),
    );
  }

  Future<int> _insert(TxnsCompanion c) async {
    final id = await _db.transaction(() async {
      final id = await _db.into(_db.txns).insert(c);
      final row = await (_db.select(
        _db.txns,
      )..where((t) => t.id.equals(id))).getSingle();
      await _applyBalance(row, direction: 1);
      await _log(row, ActivityAction.created);
      // Same transaction as the write itself: the entry and the promise to
      // send it commit together, or neither of them happened.
      await bbxSync.upsert(SyncKinds.txn, id);
      return id;
    });
    await _revoice();
    return id;
  }

  /// Tonight's nine o'clock line is composed when it is *scheduled*, not when
  /// it speaks — so every stroke in this file has to re-say it, or the
  /// evening arrives still describing the morning. Outside the transaction on
  /// purpose: talking to the notification service is not part of a database
  /// write, and must not be able to roll one back.
  ///
  /// Deliberately awaited rather than fired and forgotten. It is two small
  /// reads and one platform call, it happens at the pace a person stamps
  /// entries, and the alternative — letting it race the app being closed — is
  /// precisely the failure it exists to fix.
  Future<void> _revoice() => bbxEveningVoice(_db);

  Future<void> deleteTxn(int id) async {
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.txns,
      )..where((t) => t.id.equals(id))).getSingle();
      await _applyBalance(row, direction: -1);
      await _log(row, ActivityAction.deleted);
      await (_db.delete(_db.txns)..where((t) => t.id.equals(id))).go();
      await bbxSync.remove(SyncKinds.txn, id);
    });
    await _revoice();
  }

  /// Rewrite an entry: the old stroke is reversed, the new one applied, and
  /// the activity log keeps both. Expense/income only — a transfer is
  /// deleted and rewritten instead.
  Future<void> updateTxn(
    int id, {
    required int amountPaise,
    required int? categoryId,
    required int accountId,
    required String title,
    required DateTime at,
    String? note,
  }) {
    assert(amountPaise > 0);
    return _db.transaction(() async {
      final old = await (_db.select(
        _db.txns,
      )..where((t) => t.id.equals(id))).getSingle();
      assert(
        old.type != TxnType.transfer,
        'transfers are rewritten, not edited',
      );
      await _applyBalance(old, direction: -1);
      await (_db.update(_db.txns)..where((t) => t.id.equals(id))).write(
        TxnsCompanion(
          amountPaise: Value(amountPaise),
          categoryId: Value(categoryId),
          accountId: Value(accountId),
          title: Value(title),
          at: Value(at),
          note: Value(note),
        ),
      );
      final fresh = await (_db.select(
        _db.txns,
      )..where((t) => t.id.equals(id))).getSingle();
      await _applyBalance(fresh, direction: 1);
      await _log(fresh, ActivityAction.edited);
      await bbxSync.upsert(SyncKinds.txn, id);
    }).then((_) => _revoice());
  }

  /// Restores the most recently deleted transaction. Fearless correction.
  Future<int?> undoLastDelete() {
    return _db.transaction(() async {
      final last =
          await (_db.select(_db.activities)
                ..where((a) => a.action.equalsValue(ActivityAction.deleted))
                ..orderBy([(a) => OrderingTerm.desc(a.at)])
                ..limit(1))
              .getSingleOrNull();
      if (last == null) return null;

      final s = jsonDecode(last.snapshot) as Map<String, dynamic>;
      final id = await _insert(
        TxnsCompanion.insert(
          amountPaise: s['amountPaise'] as int,
          type: TxnType.values[s['type'] as int],
          accountId: s['accountId'] as int,
          toAccountId: Value(s['toAccountId'] as int?),
          title: s['title'] as String,
          categoryId: Value(s['categoryId'] as int?),
          goalId: Value(s['goalId'] as int?),
          note: Value(s['note'] as String?),
          at: DateTime.parse(s['at'] as String),
        ),
      );
      await (_db.delete(
        _db.activities,
      )..where((a) => a.id.equals(last.id))).go();
      return id;
    });
  }

  /// The anchor rule — worth is the PRESENT. An account's balance is a
  /// declared reading taken at [Account.asOf] ("this is what I have"), and
  /// every entry dated before that reading is already inside it: the money
  /// left the pocket before the pocket was counted. So only entries on or
  /// after the anchor move the figure — filling in a missed Tuesday records
  /// the truth of Tuesday without draining to-day's worth a second time.
  ///
  /// The same comparison runs on delete and edit, against the CURRENT
  /// anchor, which keeps the arithmetic self-consistent: once a reading has
  /// absorbed an entry, reversing that entry is also a no-op.
  Future<void> _applyBalance(Txn row, {required int direction}) async {
    Future<void> bump(int accountId, int delta) async {
      final acct = await (_db.select(
        _db.accounts,
      )..where((a) => a.id.equals(accountId))).getSingleOrNull();
      if (acct == null || row.at.isBefore(acct.asOf)) return;
      await _db.customUpdate(
        'UPDATE accounts SET balance_paise = balance_paise + ? WHERE id = ?',
        variables: [Variable.withInt(delta), Variable.withInt(accountId)],
        updates: {_db.accounts},
      );
      await snapshotToday(_db, accountId);
    }

    final amt = row.amountPaise * direction;
    switch (row.type) {
      case TxnType.expense:
        await bump(row.accountId, -amt);
      case TxnType.income:
        await bump(row.accountId, amt);
      case TxnType.transfer:
        await bump(row.accountId, -amt);
        await bump(row.toAccountId!, amt);
    }
  }

  /// Records today's reading for an account — the memory behind sparklines.
  static Future<void> snapshotToday(LedgerDb db, int accountId) async {
    final acct = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(accountId))).getSingleOrNull();
    if (acct == null) return;
    final now = DateTime.now();
    final key =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await db
        .into(db.balanceSnapshots)
        .insertOnConflictUpdate(
          BalanceSnapshotsCompanion(
            accountId: Value(accountId),
            date: Value(key),
            balancePaise: Value(acct.balancePaise),
          ),
        );
  }

  Future<void> _log(Txn row, ActivityAction action) {
    return _db
        .into(_db.activities)
        .insert(
          ActivitiesCompanion.insert(
            txnId: row.id,
            action: action,
            snapshot: jsonEncode({
              'amountPaise': row.amountPaise,
              'type': row.type.index,
              'accountId': row.accountId,
              'toAccountId': row.toAccountId,
              'categoryId': row.categoryId,
              'goalId': row.goalId,
              'title': row.title,
              'note': row.note,
              'at': row.at.toIso8601String(),
            }),
          ),
        );
  }

  // ————— reads —————

  /// Newest first, within [from, to).
  Stream<List<Txn>> watchRange(DateTime from, DateTime to) {
    final q = _db.select(_db.txns)
      ..where(
        (t) => t.at.isBiggerOrEqualValue(from) & t.at.isSmallerThanValue(to),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.at)]);
    return q.watch();
  }

  /// Spend total (expenses only) within [from, to).
  Future<int> spentBetween(
    DateTime from,
    DateTime to, {
    int? categoryId,
  }) async {
    final sum = _db.txns.amountPaise.sum();
    final q = _db.selectOnly(_db.txns)
      ..addColumns([sum])
      ..where(
        _db.txns.type.equalsValue(TxnType.expense) &
            _db.txns.at.isBiggerOrEqualValue(from) &
            _db.txns.at.isSmallerThanValue(to) &
            (categoryId == null
                ? const Constant(true)
                : _db.txns.categoryId.equals(categoryId)),
      );
    final row = await q.getSingle();
    return row.read(sum) ?? 0;
  }

  /// Titles matching [prefix] (recent first), each carrying the category and
  /// account it was last filed under.
  Future<List<TitleSuggestion>> suggestTitles(
    String prefix, {
    int limit = 5,
  }) async {
    if (prefix.trim().isEmpty) return const [];
    final q = _db.select(_db.txns)
      ..where((t) => t.title.like('%${prefix.trim()}%'))
      ..orderBy([(t) => OrderingTerm.desc(t.at)])
      ..limit(50);
    final rows = await q.get();
    final seen = <String>{};
    final out = <TitleSuggestion>[];
    for (final r in rows) {
      final key = r.title.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(
        TitleSuggestion(
          title: r.title,
          categoryId: r.categoryId,
          accountId: r.accountId,
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  }

  /// His most-used expense categories, most frequent first — feeds the chips.
  Future<List<int>> topCategoryIds({int limit = 5, DateTime? since}) async {
    final cutoff = since ?? DateTime.now().subtract(const Duration(days: 90));
    final count = _db.txns.id.count();
    final q = _db.selectOnly(_db.txns)
      ..addColumns([_db.txns.categoryId, count])
      ..where(
        _db.txns.type.equalsValue(TxnType.expense) &
            _db.txns.categoryId.isNotNull() &
            _db.txns.at.isBiggerOrEqualValue(cutoff),
      )
      ..groupBy([_db.txns.categoryId])
      ..orderBy([OrderingTerm.desc(count)])
      ..limit(limit);
    final rows = await q.get();
    return [for (final r in rows) r.read(_db.txns.categoryId)!];
  }
}
