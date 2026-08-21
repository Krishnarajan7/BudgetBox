import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rule behind "cash says ₹50 and you stamped ₹80".
///
/// The arithmetic lives in [AccountRepo.shortfall] rather than in the sheet
/// so that what the book decides to interrupt for can be proved without a
/// widget anywhere. What matters most here is what it stays *quiet* about:
/// an interruption on an entry that was never going to overdraw anything is
/// worse than the negative number this feature exists to prevent.
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

  Future<int> counted(String name, int paise, {AccountKind? kind}) async {
    final id = await accounts.create(
      name: name,
      kind: kind ?? AccountKind.cash,
      openingBalancePaise: paise,
    );
    // A declared reading — the thing that makes a pocket a counted one.
    await accounts.setBalance(id, paise);
    return id;
  }

  group('what counts as spending money you do not have', () {
    test('₹80 out of a ₹50 pocket is short by exactly ₹30', () async {
      final cash = await counted('Cash', 5000);
      final short = await accounts.shortfall(
        accountId: cash,
        amountPaise: 8000,
      );
      expect(short, isNotNull);
      expect(short!.shortPaise, 3000);
      expect(short.account.name, 'Cash');
    });

    test('spending exactly what is there is not short', () async {
      final cash = await counted('Cash', 5000);
      expect(
        await accounts.shortfall(accountId: cash, amountPaise: 5000),
        isNull,
      );
    });

    test('a pocket nobody has counted says nothing', () async {
      // Zero because no figure was ever declared, not because it is empty.
      // Stopping to argue here would make the app unusable before setup.
      final fresh = await accounts.create(
        name: 'Cash',
        kind: AccountKind.cash,
      );
      expect(
        await accounts.shortfall(accountId: fresh, amountPaise: 8000),
        isNull,
      );
    });

    test('a pocket spent down to zero is still a counted one', () async {
      final cash = await counted('Cash', 5000);
      await txns.addExpense(
        amountPaise: 5000,
        accountId: cash,
        title: 'Everything',
      );
      final short = await accounts.shortfall(
        accountId: cash,
        amountPaise: 2000,
      );
      expect(short, isNotNull, reason: 'the book has watched this pocket');
      expect(short!.shortPaise, 2000);
    });

    test('a liability is asked to grow, so it is never short', () async {
      final card = await counted('Card', 5000, kind: AccountKind.liability);
      expect(
        await accounts.shortfall(accountId: card, amountPaise: 900000),
        isNull,
      );
    });

    test('an entry older than the reading cannot overdraw it', () async {
      // The anchor rule: money that left before the pocket was counted is
      // already inside the figure, so filling in last Tuesday moves nothing
      // and there is nothing to stop for.
      final cash = await counted('Cash', 5000);
      expect(
        await accounts.shortfall(
          accountId: cash,
          amountPaise: 900000,
          at: DateTime.now().subtract(const Duration(days: 7)),
        ),
        isNull,
      );
    });

    test('an account that is gone is not a shortfall', () async {
      expect(
        await accounts.shortfall(accountId: 4242, amountPaise: 8000),
        isNull,
      );
    });
  });

  group('the resolutions leave the arithmetic true', () {
    test('topping up by the shortfall lands the pocket on zero', () async {
      final cash = await counted('Cash', 5000);
      final bank = await counted('HDFC', 100000);
      final short = (await accounts.shortfall(
        accountId: cash,
        amountPaise: 8000,
      ))!;

      // What the sheet does for "I topped Cash up first": move exactly the
      // shortfall, then write the entry.
      await txns.addTransfer(
        amountPaise: short.shortPaise,
        fromAccountId: bank,
        toAccountId: cash,
      );
      await txns.addExpense(
        amountPaise: 8000,
        accountId: cash,
        title: 'Groceries',
      );

      final rows = await db.select(db.accounts).get();
      final after = {for (final a in rows) a.name: a.balancePaise};
      expect(after['Cash'], 0, reason: 'not minus thirty');
      expect(after['HDFC'], 100000 - 3000);
      // And the money is all still accounted for: ₹80 left the shelf, no more.
      expect(after.values.reduce((a, b) => a + b), 105000 - 8000);
    });

    test('paying from another pocket leaves the first one alone', () async {
      final cash = await counted('Cash', 5000);
      final bank = await counted('HDFC', 100000);
      await txns.addExpense(
        amountPaise: 8000,
        accountId: bank,
        title: 'Groceries',
      );

      final rows = await db.select(db.accounts).get();
      final after = {for (final a in rows) a.name: a.balancePaise};
      expect(after['Cash'], 5000, reason: 'untouched');
      expect(after['HDFC'], 100000 - 8000);
      expect(cash, isNot(bank));
    });

    test('correcting a stale figure clears the shortfall', () async {
      final cash = await counted('Cash', 5000);
      // There was really ₹200 in the wallet; the book was behind.
      await accounts.setBalance(cash, 20000);
      expect(
        await accounts.shortfall(accountId: cash, amountPaise: 8000),
        isNull,
      );
      await txns.addExpense(
        amountPaise: 8000,
        accountId: cash,
        title: 'Groceries',
      );
      final row = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(cash))).getSingle();
      expect(row.balancePaise, 12000);
    });
  });
}
