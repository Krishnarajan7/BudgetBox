import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/data/repos/work_repo.dart';
import 'package:budgetbox/features/add/add_sheet.dart';
import 'package:budgetbox/features/income/income_page.dart';
import 'package:budgetbox/features/income/pot_math.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the money came from, kept apart from where it sits.
void main() {
  Txn line(
    int id,
    TxnType type,
    int rupees, {
    int? category,
    int? source,
    DateTime? at,
  }) => Txn(
    id: id,
    amountPaise: rupees * 100,
    type: type,
    categoryId: category,
    sourceId: source,
    accountId: 1,
    title: 'line $id',
    at: at ?? DateTime(2026, 9, 10),
    createdAt: DateTime(2026, 9, 10),
  );
  Category pot(int id, String name) => Category(
    id: id,
    name: name,
    icon: 'work',
    kind: CategoryKind.income,
    sortOrder: id,
    archived: false,
  );

  group('the pots — the arithmetic', () {
    final salary = pot(1, 'Salary');
    final extra = pot(2, 'Extra income');
    final window = [
      line(1, TxnType.income, 35000, category: 1),
      line(2, TxnType.income, 8000, category: 2),
      line(3, TxnType.expense, 12000, source: 1),
      line(4, TxnType.expense, 3000, source: 2),
      line(5, TxnType.expense, 500), // never named a pot
      line(6, TxnType.expense, 900), // never named a pot
    ];
    final earlier = [
      line(7, TxnType.income, 35000, category: 1, at: DateTime(2026, 8, 1)),
      line(8, TxnType.expense, 30000, source: 1, at: DateTime(2026, 8, 20)),
    ];

    test('each pot says what came in, what was drawn, what is kept', () {
      final pots = potLedgers(window, [...earlier, ...window], [salary, extra]);
      expect(pots.map((p) => p.name), ['Salary', 'Extra income']);
      final s = pots.first;
      expect(s.inPaise, 3500000);
      expect(s.outPaise, 1200000);
      expect(s.keptPaise, 2300000);
      expect(s.keptShare, closeTo(23 / 35, 0.001));
      // Since the book began: two salaries in, ₹42,000 drawn.
      expect(s.allKeptPaise, (70000 - 42000) * 100);
      expect(potLine(s), '66% of it still unspent');
      final e = pots.last;
      expect(e.keptPaise, 500000);
      expect(e.allKeptPaise, 500000);
    });

    test('a pot nobody has used is not a pot yet', () {
      final gift = pot(3, 'Gifts');
      final pots = potLedgers(window, window, [salary, extra, gift]);
      expect(pots.map((p) => p.name), isNot(contains('Gifts')));
    });

    test('the lines that never named a pot are counted apart', () {
      final loose = unassigned(window);
      expect(loose.count, 2);
      expect(loose.paise, 140000);
      expect(loose.ids, [5, 6]);
    });

    test('an overdraw is said plainly', () {
      final pots = potLedgers(
        [
          line(1, TxnType.income, 1000, category: 1),
          line(2, TxnType.expense, 1500, source: 1),
        ],
        [
          line(1, TxnType.income, 1000, category: 1),
          line(2, TxnType.expense, 1500, source: 1),
        ],
        [salary],
      );
      expect(pots.single.keptPaise, -50000);
      expect(pots.single.keptShare, 0);
      expect(potLine(pots.single), 'spent past what came in');
    });
  });

  group('the ledger', () {
    late LedgerDb db;
    late int cash;
    late int salary;
    late int extra;

    setUp(() async {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      cash = await AccountRepo(db).create(name: 'Cash', kind: AccountKind.cash);
      final cats = await db.select(db.categories).get();
      salary = cats.firstWhere((c) => c.name == 'Salary').id;
      extra = cats.firstWhere((c) => c.name == 'Extra income').id;
    });
    tearDown(() => db.close());

    test(
      'an expense remembers the pot it drew on, and can be re-settled',
      () async {
        final txns = TxnRepo(db);
        final id = await txns.addExpense(
          amountPaise: 5000,
          accountId: cash,
          title: 'chai',
          sourceId: salary,
        );
        var row = await (db.select(
          db.txns,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(row.sourceId, salary);
        await txns.assignSource([id], extra);
        row = await (db.select(
          db.txns,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(row.sourceId, extra);
      },
    );

    test(
      'an income line never carries a source, even through an edit',
      () async {
        final txns = TxnRepo(db);
        final id = await txns.addIncome(
          amountPaise: 3500000,
          accountId: cash,
          title: 'salary',
          categoryId: salary,
        );
        await txns.updateTxn(
          id,
          amountPaise: 3500000,
          categoryId: salary,
          accountId: cash,
          title: 'salary',
          at: DateTime.now(),
          sourceId: extra,
        );
        final row = await (db.select(
          db.txns,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(row.sourceId, isNull);
      },
    );

    test('the work book fills and draws on the extra pot', () async {
      final repo = WorkRepo(db, TxnRepo(db));
      expect(await repo.workPot(), extra);
      final client = await repo.createClient('Ghouthia');
      final project = await repo.createProject(
        clientId: client,
        name: 'Website',
        kind: ProjectKind.oneTime,
        quotePaise: 5000000,
      );
      final received = await repo.receive(
        project,
        amountPaise: 2000000,
        accountId: cash,
        title: 'advance',
      );
      final cost = await repo.spend(
        project,
        amountPaise: 106000,
        accountId: cash,
        title: 'domain',
      );
      final rows = {for (final t in await db.select(db.txns).get()) t.id: t};
      expect(rows[received]!.categoryId, extra);
      expect(rows[cost]!.sourceId, extra);
    });
  });

  group('the pages', () {
    late LedgerDb db;

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    setUp(() => db = LedgerDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    testWidgets('the add sheet asks which pot, and remembers the answer', (
      tester,
    ) async {
      final cash = await AccountRepo(
        db,
      ).create(name: 'Cash', kind: AccountKind.cash);
      final cats = await db.select(db.categories).get();
      final extra = cats.firstWhere((c) => c.name == 'Extra income').id;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const Scaffold(body: AddSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('out of'), findsOneWidget);
      expect(find.text('salary'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('add-pot-$extra')));
      await tester.pumpAndSettle();
      for (final k in ['1', '2', '0']) {
        await tester.tap(find.byKey(ValueKey('add-key-$k')));
        await tester.pump();
      }
      await tester.tap(find.text('stamp'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final rows = await db.select(db.txns).get();
      expect(rows.single.sourceId, extra);
      expect(rows.single.accountId, cash);
      expect(await SettingsRepo(db).lastSourceId(), extra);
      await unmount(tester);
    });

    testWidgets(
      'the income page shows each pot and offers to settle the loose lines',
      (tester) async {
        final cash = await AccountRepo(
          db,
        ).create(name: 'Cash', kind: AccountKind.cash);
        final cats = await db.select(db.categories).get();
        final salary = cats.firstWhere((c) => c.name == 'Salary').id;
        final extra = cats.firstWhere((c) => c.name == 'Extra income').id;
        final txns = TxnRepo(db);
        final now = DateTime.now();
        await txns.addIncome(
          amountPaise: 3500000,
          accountId: cash,
          title: 'salary',
          categoryId: salary,
          at: now,
        );
        await txns.addIncome(
          amountPaise: 800000,
          accountId: cash,
          title: 'ghouthia',
          categoryId: extra,
          at: now,
        );
        await txns.addExpense(
          amountPaise: 1200000,
          accountId: cash,
          title: 'rent',
          sourceId: salary,
          at: now,
        );
        await txns.addExpense(
          amountPaise: 50000,
          accountId: cash,
          title: 'chai',
          at: now,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [dbProvider.overrideWithValue(db)],
            child: MaterialApp(
              theme: ledgerDayTheme(),
              home: const IncomePage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final head = find.text('KEPT BY SOURCE');
        await tester.scrollUntilVisible(
          head,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(head, findsOneWidget);
        expect(find.text('66% of it still unspent'), findsOneWidget);
        expect(find.text('₹23,000'), findsWidgets);
        expect(
          find.textContaining('1 line worth ₹500 never named a pot'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('income-assign')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('assign-all-$extra')));
        await tester.pumpAndSettle();
        final chai = (await db.select(db.txns).get()).firstWhere(
          (t) => t.title == 'chai',
        );
        expect(chai.sourceId, extra);
        expect(find.textContaining('never named a pot'), findsNothing);
        await unmount(tester);
      },
    );
  });
}
