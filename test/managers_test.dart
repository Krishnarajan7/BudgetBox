import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/pinned_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/settings/account_manager.dart';
import 'package:budgetbox/features/settings/category_manager.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CategoryStore', () {
    late LedgerDb db;
    late CategoryStore store;

    setUp(() {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      store = CategoryStore(db);
    });

    tearDown(() => db.close());

    Future<Category> byName(String name) =>
        (db.select(db.categories)..where((c) => c.name.equals(name)))
            .getSingle();

    test('rename, re-mark, and retire all persist', () async {
      final before = await byName('Food & chai');

      await store.edit(before.id, name: 'Meals out', icon: 'meal');
      var after = await (db.select(db.categories)
            ..where((c) => c.id.equals(before.id)))
          .getSingle();
      expect(after.name, 'Meals out');
      expect(after.icon, 'meal');
      expect(after.archived, isFalse);

      await store.retire(before.id);
      after = await (db.select(db.categories)
            ..where((c) => c.id.equals(before.id)))
          .getSingle();
      // Retired, not deleted — the row survives for history.
      expect(after.archived, isTrue);

      final visible = await store.watchAll().first;
      expect(visible.map((c) => c.id), isNot(contains(before.id)));
    });

    test('create lands at the end of its own group', () async {
      final id = await store.create(
        name: 'Chai fund',
        icon: 'cup',
        kind: CategoryKind.expense,
      );
      final row = await (db.select(db.categories)
            ..where((c) => c.id.equals(id)))
          .getSingle();
      final spendingOrders = [
        for (final c in await store.watchAll().first)
          if (c.kind == CategoryKind.expense && c.id != id) c.sortOrder,
      ];
      expect(row.sortOrder,
          greaterThan(spendingOrders.reduce((a, b) => a > b ? a : b)));
    });

    test('persistOrder writes a simulated reorder back as sortOrder',
        () async {
      final spending = [
        for (final c in await store.watchAll().first)
          if (c.kind == CategoryKind.expense) c,
      ];
      expect(spending.length, greaterThanOrEqualTo(3));

      // Drag the first line to the bottom.
      final reordered = [...spending.skip(1), spending.first];
      await store.persistOrder(reordered);

      final after = [
        for (final c in await store.watchAll().first)
          if (c.kind == CategoryKind.expense) c,
      ];
      expect(
        after.map((c) => c.id).toList(),
        reordered.map((c) => c.id).toList(),
      );
      for (final (i, c) in after.indexed) {
        expect(c.sortOrder, i);
      }
    });
  });

  group('Accounts', () {
    late LedgerDb db;
    late AccountRepo repo;

    setUp(() {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      repo = AccountRepo(db);
    });

    tearDown(() => db.close());

    test('create writes the row; the retire guard tracks the balance',
        () async {
      final id = await repo.create(
        name: 'HDFC salary',
        kind: AccountKind.bank,
        openingBalancePaise: 250000,
      );
      var acct = await (db.select(db.accounts)
            ..where((a) => a.id.equals(id)))
          .getSingle();
      expect(acct.name, 'HDFC salary');
      expect(acct.kind, AccountKind.bank);
      expect(acct.balancePaise, 250000);

      // Holding ₹2,500 — the page must refuse to retire it.
      expect(canRetireAccount(acct.balancePaise), isFalse);

      await repo.setBalance(id, 0);
      acct = await (db.select(db.accounts)..where((a) => a.id.equals(id)))
          .getSingle();
      expect(canRetireAccount(acct.balancePaise), isTrue);
    });

    test('a retire guard in the negative too — a liability owing is not empty',
        () {
      expect(canRetireAccount(-5000), isFalse);
      expect(canRetireAccount(0), isTrue);
    });
  });

  group('Pinned', () {
    late LedgerDb db;
    late PinnedRepo repo;

    setUp(() {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      repo = PinnedRepo(db, TxnRepo(db));
    });

    tearDown(() => db.close());

    test('pin puts the repeat on the list; unpin takes it off', () async {
      final accountId = await AccountRepo(db)
          .create(name: 'Cash', kind: AccountKind.cash);
      final category = await (db.select(db.categories)
            ..where((c) => c.name.equals('Food & chai')))
          .getSingle();

      final id = await repo.pin(
        title: 'Morning chai',
        amountPaise: 1500,
        categoryId: category.id,
        accountId: accountId,
      );

      final pinned = await repo.watchAll().first;
      expect(pinned.length, 1);
      expect(pinned.single.title, 'Morning chai');
      expect(pinned.single.amountPaise, 1500);

      await repo.unpin(id);
      expect(await repo.watchAll().first, isEmpty);
    });
  });

  group('CategoryManagerPage', () {
    testWidgets('seeded categories render under spending', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const CategoryManagerPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('spending'), findsOneWidget);
      expect(find.text('income'), findsOneWidget);
      for (final name in ['Food & chai', 'Getting around', 'Kirana & home']) {
        expect(find.text(name), findsOneWidget);
      }
      // The seeded income lines live under their own header.
      expect(find.text('Salary'), findsOneWidget);

      // Unmount and drain drift's timers so the binding ends clean.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await db.close();
    });
  });
}
