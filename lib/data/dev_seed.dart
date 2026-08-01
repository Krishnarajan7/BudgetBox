import 'db.dart';
import 'repos/budget_repo.dart';
import 'repos/goal_repo.dart';
import 'repos/pinned_repo.dart';
import 'repos/recurring_repo.dart';
import 'repos/txn_repo.dart';

/// Debug-only: until the setup ritual persists, a fresh install gets a
/// believable month — accounts, entries, budgets, recurring charges, goals —
/// so every screen shows something true-shaped. Never runs in release.
Future<void> devSeed(LedgerDb db) async {
  final existing = await db.select(db.accounts).get();
  if (existing.isNotEmpty) return;

  final txns = TxnRepo(db);
  final pins = PinnedRepo(db, txns);
  final budgets = BudgetRepo(db);
  final recurring = RecurringRepo(db, txns);
  final goals = GoalRepo(db, txns);

  final hdfc = await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          name: 'HDFC salary',
          kind: AccountKind.bank,
        ),
      );
  final cash = await db.into(db.accounts).insert(
        AccountsCompanion.insert(name: 'Cash', kind: AccountKind.cash),
      );

  final cats = await db.select(db.categories).get();
  int cat(String name) => cats.firstWhere((c) => c.name == name).id;
  final food = cat('Food & chai');
  final travel = cat('Getting around');
  final kirana = cat('Kirana & home');
  final rent = cat('Rent');
  final bills = cat('Bills & recharge');
  final fun = cat('Fun & extras');
  final salary = cat('Salary');

  final now = DateTime.now();

  await txns.addIncome(
    amountPaise: 9200000,
    accountId: hdfc,
    categoryId: salary,
    title: 'Salary',
    at: DateTime(now.year, now.month, 1, 7),
  );

  final entries = <(int day, int paise, int cat, int acct, String title)>[
    (2, 2000, food, cash, "chai at Ganesh's"),
    (2, 6000, travel, cash, 'auto to office'),
    (3, 18000, food, hdfc, 'Saravana Bhavan'),
    (4, 68900, kirana, hdfc, 'kirana run'),
    (5, 43100, food, hdfc, 'Zomato dinner'),
    (6, 3500, travel, cash, 'metro'),
    (8, 12000, food, cash, 'mess lunch'),
    (10, 2000, food, cash, "chai at Ganesh's"),
    (12, 111800, fun, hdfc, 'new sandals, Bata'),
    (13, 6000, travel, cash, 'auto to office'),
    (14, 18000, food, hdfc, 'Saravana Bhavan'),
    (15, 9000, bills, hdfc, 'Jio recharge'),
  ];
  for (final (day, paise, catId, acct, title) in entries) {
    if (day >= now.day) continue;
    await txns.addExpense(
      amountPaise: paise,
      accountId: acct,
      categoryId: catId,
      title: title,
      at: DateTime(now.year, now.month, day, 12),
    );
  }

  // Budgets — one per everyday category.
  for (final (catId, name, limit) in [
    (food, 'Food & chai', 900000),
    (travel, 'Getting around', 350000),
    (kirana, 'Kirana & home', 1000000),
    (rent, 'Rent', 1500000),
    (bills, 'Bills & recharge', 240000),
    (fun, 'Fun & extras', 400000),
  ]) {
    await budgets.create(name: name, limitPaise: limit, categoryId: catId);
  }

  // The recurring shelf — bills that must land, subscriptions that could go.
  await recurring.create(
      title: 'Rent', amountPaise: 1500000, accountId: hdfc,
      dayOfMonth: 1, kind: RecurringKind.bill, categoryId: rent);
  await recurring.create(
      title: 'Electricity, TNEB', amountPaise: 110000, accountId: hdfc,
      dayOfMonth: 4, kind: RecurringKind.bill, categoryId: bills);
  await recurring.create(
      title: 'Jio fiber', amountPaise: 99900, accountId: hdfc,
      dayOfMonth: 12, kind: RecurringKind.bill, categoryId: bills);
  await recurring.create(
      title: 'Netflix', amountPaise: 64900, accountId: hdfc,
      dayOfMonth: 3, kind: RecurringKind.subscription, categoryId: fun);
  await recurring.create(
      title: 'Spotify', amountPaise: 11900, accountId: hdfc,
      dayOfMonth: 9, kind: RecurringKind.subscription, categoryId: fun);
  await recurring.create(
      title: 'iCloud 200GB', amountPaise: 21900, accountId: hdfc,
      dayOfMonth: 18, kind: RecurringKind.subscription, categoryId: bills);

  // Goals — fed by real, tagged entries.
  final ladakhId = await goals.create(
    name: 'Ladakh, next June',
    targetPaise: 6000000,
    monthlyPaise: 400000,
  );
  final ladakh = await (db.select(db.goals)
        ..where((g) => g.id.equals(ladakhId)))
      .getSingle();
  for (final day in [3, 10]) {
    if (day >= now.day) continue;
    await db.transaction(() => goals.contribute(
          goal: ladakh,
          amountPaise: 400000,
          accountId: hdfc,
        ));
  }

  await goals.create(
    name: 'Camera EMI',
    targetPaise: 4200000,
    kind: GoalKind.clear,
    monthlyPaise: 350000,
  );

  await pins.pin(
      title: "chai at Ganesh's", amountPaise: 2000, categoryId: food, accountId: cash);
  await pins.pin(
      title: 'auto to office', amountPaise: 6000, categoryId: travel, accountId: cash);
  await pins.pin(
      title: 'mess lunch', amountPaise: 12000, categoryId: food, accountId: cash);
  await pins.pin(
      title: 'metro', amountPaise: 3500, categoryId: travel, accountId: cash);
}
