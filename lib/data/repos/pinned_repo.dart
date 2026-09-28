import 'package:drift/drift.dart';

import '../db.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';
import '../../features/insights/insight_math.dart';
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
      final id = await _db
          .into(_db.pinneds)
          .insert(
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

  /// Lines he keeps writing by hand that should be one tap — the same
  /// title three or more times in the last three weeks at a steady price,
  /// not already pinned and not one he has passed on.
  Future<List<PinCandidate>> suggest({
    int days = 21,
    Set<String> passed = const {},
  }) async {
    final from = DateTime.now().subtract(Duration(days: days));
    final rows =
        await (_db.select(_db.txns)
              ..where(
                (t) =>
                    t.type.equalsValue(TxnType.expense) &
                    t.at.isBiggerOrEqualValue(from),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.at)]))
            .get();
    final pins = await _db.select(_db.pinneds).get();
    final cats = await _db.select(_db.categories).get();
    return pinCandidates(
      [
        for (final t in rows)
          (t.title, t.amountPaise, t.categoryId, t.accountId),
      ],
      taken: {for (final p in pins) p.title.trim().toLowerCase(), ...passed},
      categoryNames: {for (final c in cats) c.name.trim().toLowerCase()},
    );
  }

  /// Tap a pin → a stamped entry, now.
  ///
  /// [accountId] overrides the pocket the pin remembers. A pin is a habit,
  /// and the pocket a habit is usually paid from is not always the pocket
  /// that had money in it this time — the shortfall sheet resolves which,
  /// and hands the answer back through here.
  Future<int> stamp(Pinned p, {int? accountId}) {
    return _txns.addExpense(
      amountPaise: p.amountPaise,
      accountId: accountId ?? p.accountId,
      categoryId: p.categoryId,
      title: p.title,
    );
  }
}
