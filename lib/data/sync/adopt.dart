import 'package:drift/drift.dart';

import '../db.dart';
import 'ids.dart';
import 'wire.dart';

/// First contact: marry the phone's rows to the server's before either side
/// pushes anything.
///
/// Both halves of BudgetBox seed the same ten categories on an empty
/// database — the phone in its Drift migration, the server in its own. Left
/// alone, the first sweep would push all ten upstream as brand-new rows and
/// Krish would open Settings to twenty categories, two of everything. The
/// same trap waits for anyone reinstalling the app against a server that
/// already holds their book.
///
/// So before the first sweep, anything that can be recognised by a natural
/// key — a category's name, an account's name — is *adopted*: the local row
/// takes the server's uuid7 as its own instead of inventing one. After that
/// the id bridge carries the relationship and names are free to diverge.
///
/// Runs once, guarded by a flag in Settings. It only ever creates mappings;
/// it never edits or deletes a row on either side, so a wrong guess is a
/// mapping to correct rather than data to mourn.
class SyncAdopter {
  SyncAdopter(this._db);

  final LedgerDb _db;

  static const _flag = 'sync.adopted';

  Future<bool> alreadyRun() async {
    final row = await (_db.select(_db.settings)
          ..where((s) => s.key.equals(_flag)))
        .getSingleOrNull();
    return row?.value == 'true';
  }

  /// Returns how many local rows found a twin upstream.
  Future<int> adopt(SyncWire wire) async {
    if (await alreadyRun()) return 0;

    var claimed = 0;
    claimed += await _adoptCategories(wire);
    claimed += await _adoptAccounts(wire);

    await _db.into(_db.settings).insertOnConflictUpdate(
          const SettingsCompanion(
            key: Value(_flag),
            value: Value('true'),
          ),
        );
    return claimed;
  }

  Future<int> _adoptCategories(SyncWire wire) async {
    final remote = await wire.list('/v1/categories');
    if (remote.isEmpty) return 0;

    // Key on name + kind: two categories may share a name across the expense
    // and income books ("Interest" is plausible in both).
    final byKey = <String, String>{};
    for (final r in remote) {
      final name = '${r['name'] ?? ''}'.trim().toLowerCase();
      final kind = '${r['kind'] ?? ''}';
      final id = '${r['id'] ?? ''}';
      if (name.isEmpty || id.isEmpty) continue;
      byKey.putIfAbsent('$kind/$name', () => id);
    }

    var claimed = 0;
    for (final local in await _db.select(_db.categories).get()) {
      final key = '${local.kind.name}/${local.name.trim().toLowerCase()}';
      final remoteId = byKey[key];
      if (remoteId == null) continue;
      if (await _bind(SyncKinds.category, local.id, remoteId)) claimed++;
    }
    return claimed;
  }

  Future<int> _adoptAccounts(SyncWire wire) async {
    final remote = await wire.list('/v1/accounts');
    if (remote.isEmpty) return 0;

    final byKey = <String, String>{};
    for (final r in remote) {
      final name = '${r['name'] ?? ''}'.trim().toLowerCase();
      final id = '${r['id'] ?? ''}';
      if (name.isEmpty || id.isEmpty) continue;
      byKey.putIfAbsent(name, () => id);
    }

    var claimed = 0;
    for (final local in await _db.select(_db.accounts).get()) {
      final remoteId = byKey[local.name.trim().toLowerCase()];
      if (remoteId == null) continue;
      if (await _bind(SyncKinds.account, local.id, remoteId)) claimed++;
    }
    return claimed;
  }

  /// Records the marriage, unless either side is already spoken for — a local
  /// row that has been mapped, or a remote id already claimed by another
  /// local row (the unique index would refuse it anyway).
  Future<bool> _bind(String kind, int localId, String remoteId) async {
    final existing = await (_db.select(_db.remoteIds)
          ..where((r) => r.kind.equals(kind) & r.localId.equals(localId)))
        .getSingleOrNull();
    if (existing != null) return false;

    final taken = await (_db.select(_db.remoteIds)
          ..where((r) => r.kind.equals(kind) & r.remoteId.equals(remoteId)))
        .getSingleOrNull();
    if (taken != null) return false;

    await _db.into(_db.remoteIds).insert(
          RemoteIdsCompanion.insert(
            kind: kind,
            localId: localId,
            remoteId: remoteId,
            syncedAt: Value(DateTime.now().toUtc()),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return true;
  }
}
