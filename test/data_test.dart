import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/pinned_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LedgerDb db;
  late TxnRepo txns;
  late AccountRepo accounts;
  late PinnedRepo pinned;
  late int hdfc;
  late int cash;
  late int food;

  setUp(() async {
    db = LedgerDb.forTesting(NativeDatabase.memory());
    txns = TxnRepo(db);
    accounts = AccountRepo(db);
    pinned = PinnedRepo(db, txns);
    hdfc = await accounts.create(
      name: 'HDFC salary',
      kind: AccountKind.bank,
      openingBalancePaise: 10000000, // ₹1,00,000
    );
    cash = await accounts.create(name: 'Cash', kind: AccountKind.cash);
    final cats = await db.select(db.categories).get();
    food = cats.firstWhere((c) => c.name == 'Food & chai').id;
  });

  tearDown(() => db.close());

  Future<int> balance(int id) async =>
      (await (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingle())
          .balancePaise;

  test('seeds his categories on create', () async {
    final cats = await db.select(db.categories).get();
    expect(cats.length, 10);
    expect(cats.where((c) => c.kind == CategoryKind.income).length, 2);
  });

  test('expense debits its account inside one db transaction', () async {
    await txns.addExpense(
      amountPaise: 18000,
      accountId: hdfc,
      categoryId: food,
      title: 'Saravana Bhavan',
    );
    expect(await balance(hdfc), 10000000 - 18000);
  });

  test('income credits, transfer moves', () async {
    await txns.addIncome(
      amountPaise: 300000,
      accountId: hdfc,
      title: 'salary — advance',
    );
    expect(await balance(hdfc), 10300000);

    await txns.addTransfer(
      amountPaise: 50000,
      fromAccountId: hdfc,
      toAccountId: cash,
    );
    expect(await balance(hdfc), 10250000);
    expect(await balance(cash), 50000);
  });

  test('delete reverses the balance and undo restores everything', () async {
    final id = await txns.addExpense(
      amountPaise: 18000,
      accountId: hdfc,
      categoryId: food,
      title: 'Saravana Bhavan',
    );
    await txns.deleteTxn(id);
    expect(await balance(hdfc), 10000000);
    expect(await db.select(db.txns).get(), isEmpty);

    final restored = await txns.undoLastDelete();
    expect(restored, isNotNull);
    expect(await balance(hdfc), 10000000 - 18000);
    final row = await db.select(db.txns).getSingle();
    expect(row.title, 'Saravana Bhavan');
    expect(row.categoryId, food);
  });

  test('every mutation leaves an activity line', () async {
    final id = await txns.addExpense(
      amountPaise: 2000,
      accountId: cash,
      categoryId: food,
      title: 'chai',
    );
    await txns.deleteTxn(id);
    final log = await db.select(db.activities).get();
    expect(log.map((a) => a.action),
        containsAll([ActivityAction.created, ActivityAction.deleted]));
  });

  test('title suggestions carry their last category and account', () async {
    await txns.addExpense(
      amountPaise: 18000,
      accountId: hdfc,
      categoryId: food,
      title: 'Saravana Bhavan',
    );
    final s = await txns.suggestTitles('sar');
    expect(s, hasLength(1));
    expect(s.first.title, 'Saravana Bhavan');
    expect(s.first.categoryId, food);
    expect(s.first.accountId, hdfc);
  });

  test('spentBetween counts only expenses in range', () async {
    final july = DateTime(2026, 7);
    await txns.addExpense(
      amountPaise: 10000,
      accountId: cash,
      categoryId: food,
      title: 'lunch',
      at: DateTime(2026, 7, 14),
    );
    await txns.addIncome(
      amountPaise: 999999,
      accountId: hdfc,
      title: 'not spend',
      at: DateTime(2026, 7, 15),
    );
    await txns.addExpense(
      amountPaise: 5000,
      accountId: cash,
      categoryId: food,
      title: 'outside range',
      at: DateTime(2026, 8, 2),
    );
    expect(
      await txns.spentBetween(july, DateTime(2026, 8), categoryId: food),
      10000,
    );
  });

  test('pinned stamp is a real entry', () async {
    final pinId = await pinned.pin(
      title: 'chai at Ganesh\'s',
      amountPaise: 2000,
      categoryId: food,
      accountId: cash,
    );
    expect(pinId, isPositive);
    final pins = await db.select(db.pinneds).get();
    await pinned.stamp(pins.single);
    final row = await db.select(db.txns).getSingle();
    expect(row.amountPaise, 2000);
    expect(await balance(cash), -2000);
  });

  test('net worth subtracts liabilities', () async {
    await accounts.create(
      name: 'Camera EMI',
      kind: AccountKind.liability,
      openingBalancePaise: 2800000,
    );
    expect(await accounts.netWorthPaise(), 10000000 - 2800000);
  });

  test('setBalance refreshes the as-of staleness date', () async {
    // Age the account far into the past, as a long-untouched cash row would be.
    final stale = DateTime(2026, 6, 12);
    await (db.update(db.accounts)..where((a) => a.id.equals(cash)))
        .write(AccountsCompanion(asOf: Value(stale)));

    await accounts.setBalance(cash, 320000);
    final after =
        await (db.select(db.accounts)..where((a) => a.id.equals(cash))).getSingle();
    expect(after.balancePaise, 320000);
    expect(after.asOf.isAfter(stale), isTrue);
  });
}
