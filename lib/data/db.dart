import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'db.g.dart';

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Txns,
    Recurrings,
    Budgets,
    Goals,
    Pinneds,
    DaySeals,
    Activities,
    Settings,
    Notes,
    FocusSessions,
    JournalEntries,
    Events,
    VaultItems,
    BalanceSnapshots,
    RemoteIds,
    Outbox,
    DayMarks,
  ],
)
class LedgerDb extends _$LedgerDb {
  LedgerDb() : super(driftDatabase(name: 'budgetbox'));

  /// In-memory database for tests.
  LedgerDb.forTesting(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedCategories();
    },
    onUpgrade: (m, from, to) async {
      if (from < 7) {
        // v7: the day's marks — habits, meals, and the clean count.
        await m.createTable(dayMarks);
      }
      if (from < 6) {
        // v6 opens the line to the server: what the phone's row numbers
        // are called upstream, and what it still owes.
        await m.createTable(remoteIds);
        await m.createTable(outbox);
        await m.createIndex(_remoteIdLookup);
        await m.createIndex(_outboxOrder);
      }
      if (from < 5) {
        // v5 gives balances a memory.
        await m.createTable(balanceSnapshots);
      }
      if (from < 4) {
        // v4: the calendar and the sealed vault.
        await m.createTable(events);
        await m.createTable(vaultItems);
      }
      if (from < 3) {
        // v3 opens the other books in the box.
        await m.createTable(notes);
        await m.createTable(focusSessions);
        await m.createTable(journalEntries);
      }
      if (from < 2) {
        // v2 traded the emoji column for an icon key. Rebuild the table
        // without the old column, then re-mark the seeded categories.
        await m.alterTable(
          TableMigration(
            categories,
            newColumns: [categories.icon],
            columnTransformer: {categories.icon: const Constant('circle')},
          ),
        );
        for (final (icon, name) in [..._expenseSeed, ..._incomeSeed]) {
          await (update(categories)..where((c) => c.name.equals(name))).write(
            CategoriesCompanion(icon: Value(icon)),
          );
        }
      }
    },
  );

  /// Krish's starting categories — his, editable, not a template dump.
  static const _expenseSeed = [
    ('cup', 'Food & chai'),
    ('bus', 'Getting around'),
    ('basket', 'Kirana & home'),
    ('home', 'Rent'),
    ('bill', 'Bills & recharge'),
    ('film', 'Fun & extras'),
    ('health', 'Health'),
    ('gift', 'Family & gifts'),
  ];

  static const _incomeSeed = [('work', 'Salary'), ('up', 'Extra income')];

  /// Burn the book — this device only.
  ///
  /// Children before parents so foreign keys never object, sync bookkeeping
  /// included so a later re-wire starts honest (adopt, then pull — never a
  /// queued delete-storm). Categories are re-seeded because an empty book
  /// still needs words for money. The server copy, if one exists, is not
  /// touched from here — by design.
  Future<void> eraseBook() async {
    await transaction(() async {
      for (final table in <TableInfo<Table, Object?>>[
        outbox,
        remoteIds,
        activities,
        balanceSnapshots,
        txns,
        pinneds,
        budgets,
        recurrings,
        goals,
        daySeals,
        dayMarks,
        journalEntries,
        notes,
        focusSessions,
        events,
        vaultItems,
        settings,
        categories,
        accounts,
      ]) {
        await delete(table).go();
      }
      await _seedCategories();
    });
  }

  Future<void> _seedCategories() async {
    await batch((b) {
      for (final (i, (icon, name)) in _expenseSeed.indexed) {
        b.insert(
          categories,
          CategoriesCompanion.insert(
            name: name,
            icon: Value(icon),
            kind: CategoryKind.expense,
            sortOrder: Value(i),
          ),
        );
      }
      for (final (i, (icon, name)) in _incomeSeed.indexed) {
        b.insert(
          categories,
          CategoriesCompanion.insert(
            name: name,
            icon: Value(icon),
            kind: CategoryKind.income,
            sortOrder: Value(i),
          ),
        );
      }
    });
  }
}

/// Reverse lookup: the server hands back a uuid7, the phone needs its own row
/// number for it. Unique so one remote row can never claim two local ones.
final _remoteIdLookup = Index(
  'remote_ids_by_remote',
  'CREATE UNIQUE INDEX IF NOT EXISTS remote_ids_by_remote '
      'ON remote_ids (kind, remote_id)',
);

/// The queue is drained oldest first.
final _outboxOrder = Index(
  'outbox_by_queued',
  'CREATE INDEX IF NOT EXISTS outbox_by_queued ON outbox (queued_at)',
);

/// Money kept aside — investments, the emergency fund. A holding is not a
/// pocket: daily spending never offers it, so nothing drains it by accident.
/// Only a deliberate hand touches it — a transfer, or a correction from
/// Worth with a reason of its own.
extension AccountNature on Account {
  bool get keptAside => kind == AccountKind.asset;
}
