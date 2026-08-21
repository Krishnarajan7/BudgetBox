import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/nudges.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/data/tonight.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('evening wording rotates while keeping the day facts', () {
    final first = eveningNudgeCopy(
      DateTime(2026, 8, 13),
      expenseCount: 2,
      spentPaise: 119200,
    );
    final next = eveningNudgeCopy(
      DateTime(2026, 8, 14),
      expenseCount: 2,
      spentPaise: 119200,
    );

    expect(first, isNot(next));
    expect('${first.title} ${first.body}', contains('₹1,192'));
    expect('${first.title} ${first.body}', contains('two entries'));
    expect('${next.title} ${next.body}', contains('₹1,192'));
    expect('${next.title} ${next.body}', contains('two entries'));
  });

  test('standing fallback changes each day and never claims a total', () {
    final copies = [
      for (var day = 13; day <= 16; day++)
        standingNudgeCopy(DateTime(2026, 8, day)),
    ];

    expect(copies.toSet(), hasLength(4));
    for (final copy in copies) {
      expect('${copy.title} ${copy.body}', isNot(contains('₹')));
    }
  });

  test('an empty page gets rotating zero-day wording', () {
    final first = eveningNudgeCopy(
      DateTime(2026, 8, 13),
      expenseCount: 0,
      spentPaise: 0,
    );
    final next = eveningNudgeCopy(
      DateTime(2026, 8, 14),
      expenseCount: 0,
      spentPaise: 0,
    );

    expect(first, isNot(next));
    expect('${first.title} ${first.body}', contains('₹0'));
  });

  /// The bug this group exists for: the nine o'clock notification's words are
  /// fixed when it is *scheduled*, hours before it speaks. Composed once in
  /// the morning and never again, it arrived on evenings with a dozen entries
  /// on them still saying "a quiet money day? confirm the ₹0" — which teaches
  /// you to stop reading it.
  group('tonight’s line follows the ledger', () {
    late LedgerDb db;
    late TxnRepo txns;
    late int cash;

    setUp(() async {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      txns = TxnRepo(db);
      cash = await AccountRepo(db).create(name: 'Cash', kind: AccountKind.cash);
    });
    tearDown(() async {
      uninstallEveningVoice();
      await db.close();
    });

    test('an empty page says so', () async {
      final line = await tonightsLine(db);
      expect(line, isNotNull);
      expect('${line!.title} ${line.body}', contains('₹0'));
    });

    test('a written page never claims ₹0', () async {
      await txns.addExpense(
        amountPaise: 12000,
        accountId: cash,
        title: 'Auto',
      );
      final line = (await tonightsLine(db))!;
      final said = '${line.title} ${line.body}';
      expect(said, isNot(contains('₹0')));
      expect(said, contains('₹120'));
      expect(said, contains('one entry'));
    });

    test('only today counts, and only expenses', () async {
      await txns.addExpense(
        amountPaise: 50000,
        accountId: cash,
        title: 'Yesterday',
        at: DateTime.now().subtract(const Duration(days: 1)),
      );
      await txns.addIncome(
        amountPaise: 900000,
        accountId: cash,
        title: 'Salary',
      );
      final line = (await tonightsLine(db))!;
      // Money in is not a written page, and yesterday is yesterday.
      expect('${line.title} ${line.body}', contains('₹0'));
    });

    test('a sealed day has nothing left to say', () async {
      await txns.addExpense(amountPaise: 12000, accountId: cash, title: 'Auto');
      await db
          .into(db.daySeals)
          .insert(DaySealsCompanion.insert(date: _todayKey()));
      expect(await tonightsLine(db), isNull);
    });

    test('stamping re-says the line there and then', () async {
      // The regression itself. The morning's line is composed while the page
      // is empty; by the time an entry lands, the evening must already have
      // been told about it — not at some later lifecycle event that may never
      // arrive before nine.
      final said = <NudgeCopy?>[];
      installEveningVoice((db, {DateTime? now}) async {
        said.add(await tonightsLine(db, now: now));
      });

      expect(said, isEmpty, reason: 'nothing written, nothing re-said');

      await txns.addExpense(amountPaise: 12000, accountId: cash, title: 'Auto');
      expect(said, hasLength(1));
      expect('${said.last!.title} ${said.last!.body}', contains('₹120'));

      await txns.addExpense(amountPaise: 8000, accountId: cash, title: 'Chai');
      expect(said, hasLength(2));
      expect('${said.last!.title} ${said.last!.body}', contains('₹200'));
      expect('${said.last!.title} ${said.last!.body}', contains('two entries'));
    });

    test('deleting the day’s only entry re-says it too', () async {
      final said = <NudgeCopy?>[];
      installEveningVoice((db, {DateTime? now}) async {
        said.add(await tonightsLine(db, now: now));
      });

      final id = await txns.addExpense(
        amountPaise: 12000,
        accountId: cash,
        title: 'Auto',
      );
      await txns.deleteTxn(id);
      // Struck out, so the page really is empty again — and says so.
      expect('${said.last!.title} ${said.last!.body}', contains('₹0'));
    });

    test('editing an amount re-says the total', () async {
      final said = <NudgeCopy?>[];
      final id = await txns.addExpense(
        amountPaise: 12000,
        accountId: cash,
        title: 'Auto',
      );
      installEveningVoice((db, {DateTime? now}) async {
        said.add(await tonightsLine(db, now: now));
      });
      await txns.updateTxn(
        id,
        amountPaise: 45000,
        categoryId: null,
        accountId: cash,
        title: 'Auto',
        at: DateTime.now(),
      );
      expect('${said.last!.title} ${said.last!.body}', contains('₹450'));
    });

    test('the ledger stays silent until an app installs the voice', () async {
      // A repo must be usable with no notification service in sight; the
      // default hook is silence, not a platform channel.
      await txns.addExpense(amountPaise: 12000, accountId: cash, title: 'Auto');
      expect(await tonightsLine(db), isNotNull);
    });
  });
}

String _todayKey() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}
