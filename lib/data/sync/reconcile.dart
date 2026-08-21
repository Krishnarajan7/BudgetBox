import 'package:drift/drift.dart';

import '../db.dart';
import 'ids.dart';
import 'outbox.dart';

/// The catch-up sweep: anything in the local book the server has never been
/// told about gets queued.
///
/// It exists for two honest reasons:
///
/// 1. The book predates the server. A phone that has been keeping accounts,
///    categories and months of entries locally must be able to hand all of it
///    upstream the first time it is wired, without anyone re-typing a thing.
/// 2. Two screens still write Drift directly rather than through a repo — the
///    category manager in Settings, and sealing a day from Today/Book. Those
///    screens are frozen, so the sweep is what carries their writes. It is
///    exact for seals (a seal has no editable content: it is either there or
///    it isn't) and covers *creation* for categories; a category renamed by
///    the frozen manager is the one write this layer still cannot see.
///
/// Kinds are swept in dependency order, so an account is queued before the
/// transaction that names it.
class SyncReconciler {
  SyncReconciler(this._db, this._outbox);

  final LedgerDb _db;
  final SyncOutbox _outbox;

  /// One sync stays bounded; a very long history simply takes a few passes.
  static const perKindCap = 500;

  Future<int> sweep() async {
    var queued = 0;
    for (final kind in SyncKinds.inDependencyOrder) {
      for (final localId in await _unmapped(kind)) {
        await _outbox.upsert(kind, localId);
        // An account the server has never seen carries a balance the server
        // can never derive: its anchor was set while the book was unwired, so
        // no anchor row was ever queued. Send the current reading alongside
        // the account itself — anchored at *now*, because the local figure
        // already includes every entry that will be pushed with it. Without
        // this, the first pull after the queue drains would overwrite the
        // phone's worth with whatever the server derived from nothing.
        if (kind == SyncKinds.account) {
          final row = await (_db.select(
            _db.accounts,
          )..where((a) => a.id.equals(localId))).getSingleOrNull();
          if (row != null) {
            await _outbox.anchor(localId, row.balancePaise, DateTime.now());
          }
        }
        queued++;
      }
    }
    queued += await _sweepReopenedDays();
    return queued;
  }

  /// Local rows with no uuid7 yet.
  Future<List<int>> _unmapped(String kind) async {
    final source = _sourceFor(kind);
    if (source == null) return const [];
    final rows = await _db.customSelect(
      'SELECT x.lid AS lid FROM (SELECT ${source.idExpr} AS lid '
      'FROM ${source.table}) x '
      'LEFT JOIN remote_ids r ON r.kind = ? AND r.local_id = x.lid '
      'WHERE r.local_id IS NULL ORDER BY x.lid LIMIT $perKindCap',
      variables: [Variable.withString(kind)],
    ).get();
    return [for (final r in rows) r.read<int>('lid')];
  }

  /// A day that was sealed, synced, and then reopened on the phone. The seal
  /// is the only row a frozen screen deletes outright, so the absence has to
  /// be noticed here rather than at the call site.
  Future<int> _sweepReopenedDays() async {
    final rows = await _db.customSelect(
      "SELECT r.local_id AS lid FROM remote_ids r "
      "LEFT JOIN day_seals s "
      "ON CAST(REPLACE(s.date, '-', '') AS INTEGER) = r.local_id "
      "WHERE r.kind = ? AND s.date IS NULL",
      variables: [Variable.withString(SyncKinds.seal)],
    ).get();
    for (final r in rows) {
      await _outbox.remove(SyncKinds.seal, r.read<int>('lid'));
    }
    return rows.length;
  }

  static ({String table, String idExpr})? _sourceFor(String kind) =>
      switch (kind) {
        SyncKinds.account => (table: 'accounts', idExpr: 'id'),
        SyncKinds.category => (table: 'categories', idExpr: 'id'),
        SyncKinds.goal => (table: 'goals', idExpr: 'id'),
        SyncKinds.recurring => (table: 'recurrings', idExpr: 'id'),
        SyncKinds.budget => (table: 'budgets', idExpr: 'id'),
        SyncKinds.pinned => (table: 'pinneds', idExpr: 'id'),
        SyncKinds.txn => (table: 'txns', idExpr: 'id'),
        SyncKinds.note => (table: 'notes', idExpr: 'id'),
        SyncKinds.focus => (table: 'focus_sessions', idExpr: 'id'),
        SyncKinds.event => (table: 'events', idExpr: 'id'),
        SyncKinds.vault => (table: 'vault_items', idExpr: 'id'),
        SyncKinds.mark => (table: 'day_marks', idExpr: 'id'),
        SyncKinds.alarm => (table: 'alarms', idExpr: 'id'),
        SyncKinds.seal => (
            table: 'day_seals',
            idExpr: "CAST(REPLACE(date, '-', '') AS INTEGER)",
          ),
        SyncKinds.journal => (
            table: 'journal_entries',
            idExpr: "CAST(REPLACE(date, '-', '') AS INTEGER)",
          ),
        _ => null,
      };
}
