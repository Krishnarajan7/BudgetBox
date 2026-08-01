import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/budget_repo.dart';
import 'package:budgetbox/data/repos/goal_repo.dart';
import 'package:budgetbox/data/repos/recurring_repo.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LedgerDb db;
  late TxnRepo txns;
  late int cash;
  late int food;
  late int rent;

  setUp(() async {
    db = LedgerDb.forTesting(NativeDatabase.memory());
    txns = TxnRepo(db);
    cash = await AccountRepo(db)
        .create(name: 'Cash', kind: AccountKind.cash, openingBalancePaise: 10000000);
    final cats = await db.select(db.categories).get();
    food = cats.firstWhere((c) => c.name == 'Food & chai').id;
    rent = cats.firstWhere((c) => c.name == 'Rent').id;
  });

  tearDown(() => db.close());

  group('RecurringRepo.nextDate', () {
    test('lands this month when the day is still ahead', () {
      final d = RecurringRepo.nextDate(20, 1, DateTime(2026, 7, 5));
      expect(d, DateTime(2026, 7, 20));
    });

    test('rolls to next month when the day has passed', () {
      final d = RecurringRepo.nextDate(3, 1, DateTime(2026, 7, 5));
      expect(d, DateTime(2026, 8, 3));
    });

    test('today counts as due today', () {
      final d = RecurringRepo.nextDate(5, 1, DateTime(2026, 7, 5, 23));
      expect(d, DateTime(2026, 7, 5));
    });

    test('clamps the 31st into February', () {
      final d = RecurringRepo.nextDate(31, 1, DateTime(2027, 2, 1));
      expect(d, DateTime(2027, 2, 28));
    });

    test('yearly cadence crosses the year boundary', () {
      final d = RecurringRepo.nextDate(15, 12, DateTime(2026, 12, 20));
      expect(d.isAfter(DateTime(2026, 12, 20)), isTrue);
      expect(d.day, 15);
    });
  });

  group('RecurringRepo', () {
    test('committed counts only unpaid charges due this month', () async {
      final repo = RecurringRepo(db, txns);
      final now = DateTime.now();
      // Due later this month (or today) — clamp keeps it valid.
      await repo.create(
        title: 'Netflix',
        amountPaise: 64900,
        accountId: cash,
        dayOfMonth: now.day,
        kind: RecurringKind.subscription,
        categoryId: food,
      );
      expect(await repo.watchCommittedThisMonth().first, 64900);

      final r = (await db.select(db.recurrings).get()).single;
      await repo.markPaid(r);
      expect(await repo.watchCommittedThisMonth().first, 0);

      // The real entry exists and the schedule moved on.
      final paid = await db.select(db.txns).get();
      expect(paid.single.recurringId, r.id);
      final advanced = (await db.select(db.recurrings).get()).single;
      expect(advanced.nextDue.compareTo(r.nextDue) > 0, isTrue);
    });

    test('yearly total normalises cadence', () async {
      final repo = RecurringRepo(db, txns);
      await repo.create(
        title: 'Spotify',
        amountPaise: 11900,
        accountId: cash,
        dayOfMonth: 9,
        kind: RecurringKind.subscription,
      );
      await repo.create(
        title: 'Domain',
        amountPaise: 120000,
        accountId: cash,
        dayOfMonth: 1,
        everyMonths: 12,
        kind: RecurringKind.bill,
      );
      expect(await repo.yearlyTotal(), 11900 * 12 + 120000);
      expect(await repo.yearlyTotal(kind: RecurringKind.subscription),
          11900 * 12);
    });
  });

  group('BudgetRepo', () {
    test('views fold real spend into pace, sorted by spend', () async {
      final repo = BudgetRepo(db);
      await repo.create(name: 'Food', limitPaise: 900000, categoryId: food);
      await repo.create(name: 'Rent', limitPaise: 1500000, categoryId: rent);
      await txns.addExpense(
          amountPaise: 20000, accountId: cash, categoryId: food, title: 'meals');

      final views = await repo.watchViews(DateTime.now()).first;
      expect(views, hasLength(2));
      expect(views.first.name, 'Food & chai'); // heaviest spender first
      expect(views.first.pace.spentPaise, 20000);
      expect(views.last.pace.spentPaise, 0);
    });

    test('rebalance keeps the total and follows the spending', () async {
      final repo = BudgetRepo(db);
      await repo.create(name: 'Food', limitPaise: 500000, categoryId: food);
      await repo.create(name: 'Rent', limitPaise: 500000, categoryId: rent);
      await txns.addExpense(
          amountPaise: 30000, accountId: cash, categoryId: food, title: 'a');
      await txns.addExpense(
          amountPaise: 10000, accountId: cash, categoryId: rent, title: 'b');

      final before = await repo.watchViews(DateTime.now()).first;
      await repo.rebalance(before);
      final after = await repo.watchViews(DateTime.now()).first;

      final total = after.fold(0, (s, v) => s + v.pace.limitPaise);
      expect(total, 1000000); // unchanged
      final foodView = after.firstWhere((v) => v.category?.id == food);
      final rentView = after.firstWhere((v) => v.category?.id == rent);
      expect(foodView.pace.limitPaise, greaterThan(rentView.pace.limitPaise));
    });
  });

  group('GoalRepo', () {
    test('contributions feed the view through real tagged entries', () async {
      final repo = GoalRepo(db, txns);
      final id = await repo.create(name: 'Ladakh', targetPaise: 6000000);
      final goal =
          await (db.select(db.goals)..where((g) => g.id.equals(id))).getSingle();

      await repo.contribute(goal: goal, amountPaise: 400000, accountId: cash);
      await repo.contribute(goal: goal, amountPaise: 200000, accountId: cash);

      final view = (await repo.watchViews().first).single;
      expect(view.donePaise, 600000);
      expect(view.entryCount, 2);
      expect(view.remainingPaise, 5400000);

      // And the account genuinely paid for it.
      final acct = await (db.select(db.accounts)
            ..where((a) => a.id.equals(cash)))
          .getSingle();
      expect(acct.balancePaise, 10000000 - 600000);
    });
  });

  group('SettingsRepo — the lock', () {
    test('set, check, and clear a PIN', () async {
      final settings = SettingsRepo(db);
      expect(await settings.hasPin(), isFalse);

      await settings.setPin('4271');
      expect(await settings.hasPin(), isTrue);
      expect(await settings.checkPin('4271'), isTrue);
      expect(await settings.checkPin('0000'), isFalse);

      await settings.clearPin();
      expect(await settings.hasPin(), isFalse);
      expect(await settings.checkPin('4271'), isFalse);
    });

    test('theme mode round-trips', () async {
      final settings = SettingsRepo(db);
      expect(await settings.themeMode(), isNull);
      await settings.setThemeMode('dark');
      expect(await settings.themeMode(), 'dark');
    });
  });
}
