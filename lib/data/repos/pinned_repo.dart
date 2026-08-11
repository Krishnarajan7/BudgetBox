import 'package:drift/drift.dart';

import '../db.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';
import 'txn_repo.dart';

/// The one-tap repeats — the only path that beats five seconds.
class PinnedRepo {
  PinnedRepo(this._db, this._txns);

  final LedgerDb _db;
  final TxnRepo _txns;

  Stream<List<Pinned>> watchAll() {
    final q = _db.select(_db.pinneds)
      ..orderBy([(p) => OrderingTerm.asc(p.sortOrder)]);
    return q.watch();
  }

  Future<int> pin({
    required String title,
    required int amountPaise,
    required int categoryId,
    required int accountId,
  }) {
    return _db.transaction(() async {
      final id = await _db.into(_db.pinneds).insert(
            PinnedsCompanion.insert(
              title: title,
              amountPaise: amountPaise,
              categoryId: categoryId,
              accountId: accountId,
            ),
          );
      await bbxSync.upsert(SyncKinds.pinned, id);
      return id;
    });
  }

  Future<void> unpin(int id) {
    return _db.transaction(() async {
      await (_db.delete(_db.pinneds)..where((p) => p.id.equals(id))).go();
      await bbxSync.remove(SyncKinds.pinned, id);
    });
  }

  /// Tap a pin → a stamped entry, now.
  Future<int> stamp(Pinned p) {
    return _txns.addExpense(
      amountPaise: p.amountPaise,
      accountId: p.accountId,
      categoryId: p.categoryId,
      title: p.title,
    );
  }
}
