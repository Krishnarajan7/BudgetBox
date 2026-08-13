import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The anchor rule: worth is the PRESENT. A balance is a reading taken at
/// [Account.asOf]; entries dated before the reading are already inside it
/// and must never move the figure again.
void main() {
  late LedgerDb db;
  late AccountRepo accounts;
  late TxnRepo txns;

  setUp(() {
    db = LedgerDb.forTesting(NativeDatabase.memory());
    accounts = AccountRepo(db);
    txns = TxnRepo(db);
  });

  tearDown(() => db.close());

  Future<int> balance(int id) async =>
      (await (db.select(db.accounts)..where((a) => a.id.equals(id)))
              .getSingle())
          .balancePaise;

  test('a back-dated entry never drains a balance declared after it',
      () async {
    final cash = await accounts.create(
      name: 'Cash',
      kind: AccountKind.cash,
      openingBalancePaise: 100000, // ₹1,000 counted just now
    );
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await txns.addExpense(
      amountPaise: 50000,
      accountId: cash,
      title: 'dress, remembered late',
      at: DateTime(yesterday.year, yesterday.month, yesterday.day, 12),
    );
    // The ₹1,000 was counted AFTER that spend happened — it already
    // reflects it. Catch-up records the truth without double-charging.
    expect(await balance(cash), 100000);
  });

  test('an entry after the reading moves the figure as always', () async {
    final cash = await accounts.create(
      name: 'Cash',
      kind: AccountKind.cash,
      openingBalancePaise: 100000,
    );
    await txns.addExpense(
      amountPaise: 20000,
      accountId: cash,
      title: 'chai run',
      at: DateTime.now().add(const Duration(minutes: 1)),
    );
    expect(await balance(cash), 80000);
  });

  test('re-anchoring absorbs earlier entries: deleting one is then a no-op',
      () async {
    final cash = await accounts.create(
      name: 'Cash',
      kind: AccountKind.cash,
      openingBalancePaise: 100000,
    );
    final id = await txns.addExpense(
      amountPaise: 30000,
      accountId: cash,
      title: 'auto',
    );
    expect(await balance(cash), 70000);

    // A fresh wallet count: ₹500, taken after the auto ride. The reading
    // owns everything before it now.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await accounts.setBalance(cash, 50000);
    expect(await balance(cash), 50000);

    // Striking the pre-reading entry must not "refund" money the count
    // already accounted for.
    await txns.deleteTxn(id);
    expect(await balance(cash), 50000);
  });

  test('a transfer respects each side\'s own anchor', () async {
    final cash = await accounts.create(
      name: 'Cash',
      kind: AccountKind.cash,
      openingBalancePaise: 100000,
    );
    // Timestamps persist at whole-second precision — give the two
    // readings a clear second between them.
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    final bank = await accounts.create(
      name: 'SBI',
      kind: AccountKind.bank,
      openingBalancePaise: 200000,
    );
    // Dated between the two readings: Cash (older anchor) applies it,
    // SBI (younger anchor, which already includes it) does not.
    final between = DateTime.now().subtract(const Duration(milliseconds: 1100));
    await txns.addTransfer(
      amountPaise: 40000,
      fromAccountId: cash,
      toAccountId: bank,
      at: between,
    );
    expect(await balance(cash), 60000);
    expect(await balance(bank), 200000);
  });
}
