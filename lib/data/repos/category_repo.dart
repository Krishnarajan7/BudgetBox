import 'package:drift/drift.dart';

import '../db.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';

/// The wired seam for category writes.
///
/// Categories are the one finance table whose writer still lives in a screen:
/// `CategoryStore` in `lib/features/settings/category_manager.dart` talks to
/// Drift directly, and that file is frozen. Until it is re-pointed here, the
/// sweep in `sync/reconcile.dart` carries newly created categories upstream
/// and a rename made through the manager is not seen. Every method below is a
/// like-for-like replacement for the one it shadows, so the swap is an import
/// change and nothing else.
class CategoryRepo {
  CategoryRepo(this._db);

  final LedgerDb _db;

  Stream<List<Category>> watchAll({bool includeArchived = false}) {
    final q = _db.select(_db.categories)
      ..orderBy([
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.id),
      ]);
    if (!includeArchived) q.where((c) => c.archived.equals(false));
    return q.watch();
  }

  /// A new line at the end of its group.
  Future<int> create({
    required String name,
    required String icon,
    required CategoryKind kind,
  }) {
    return _db.transaction(() async {
      final siblings = await (_db.select(_db.categories)
            ..where((c) => c.kind.equalsValue(kind)))
          .get();
      final next =
          siblings.fold(-1, (int m, c) => c.sortOrder > m ? c.sortOrder : m) + 1;
      final id = await _db.into(_db.categories).insert(
            CategoriesCompanion.insert(
              name: name,
              icon: Value(icon),
              kind: kind,
              sortOrder: Value(next),
            ),
          );
      await bbxSync.upsert(SyncKinds.category, id);
      return id;
    });
  }

  Future<void> edit(int id, {String? name, String? icon}) {
    return _db.transaction(() async {
      await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          name: name == null ? const Value.absent() : Value(name),
          icon: icon == null ? const Value.absent() : Value(icon),
        ),
      );
      await bbxSync.upsert(SyncKinds.category, id);
    });
  }

  /// Retired, not deleted — it leaves the pickers; history keeps it.
  Future<void> retire(int id) {
    return _db.transaction(() async {
      await (_db.update(_db.categories)..where((c) => c.id.equals(id)))
          .write(const CategoriesCompanion(archived: Value(true)));
      // CategoryIn carries no `archived`; retiring is a PATCH upstream.
      await bbxSync.patch(SyncKinds.category, id, {'archived': true});
    });
  }

  /// Writes the given order back as sortOrder 0..n.
  Future<void> persistOrder(List<Category> inOrder) {
    return _db.transaction(() async {
      for (final (i, cat) in inOrder.indexed) {
        await (_db.update(_db.categories)..where((c) => c.id.equals(cat.id)))
            .write(CategoriesCompanion(sortOrder: Value(i)));
        await bbxSync.upsert(SyncKinds.category, cat.id);
      }
    });
  }
}
