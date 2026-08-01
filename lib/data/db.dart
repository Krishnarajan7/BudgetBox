import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'db.g.dart';

@DriftDatabase(tables: [
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
])
class LedgerDb extends _$LedgerDb {
  LedgerDb() : super(driftDatabase(name: 'budgetbox'));

  /// In-memory database for tests.
  LedgerDb.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedCategories();
        },
        onUpgrade: (m, from, to) async {
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
                columnTransformer: {
                  categories.icon: const Constant('circle'),
                },
              ),
            );
            for (final (icon, name) in [..._expenseSeed, ..._incomeSeed]) {
              await (update(categories)..where((c) => c.name.equals(name)))
                  .write(CategoriesCompanion(icon: Value(icon)));
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

  static const _incomeSeed = [
    ('work', 'Salary'),
    ('up', 'Extra income'),
  ];

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
