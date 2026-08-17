import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/core/widgets/charts.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/budget_repo.dart';
import 'package:budgetbox/data/repos/recurring_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/plans/plans_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plans is three books in one: the pace line on every budget, the shelf,
/// and the goals. These guard the parts a redesign is most likely to drop.
void main() {
  late LedgerDb db;

  Widget host(Widget child) => ProviderScope(
    overrides: [dbProvider.overrideWithValue(db)],
    child: MaterialApp(
      theme: ledgerDayTheme(),
      home: Scaffold(body: child),
    ),
  );

  /// Drift's stream teardown schedules a timer; let it fire before the
  /// binding checks for leaks.
  Future<void> settleAndUnmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  setUp(() async {
    db = LedgerDb.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> seedFood() async {
    final accounts = AccountRepo(db);
    final txns = TxnRepo(db);
    final cash = await accounts.create(
      name: 'Cash',
      kind: AccountKind.cash,
      openingBalancePaise: 500000,
    );
    final cats = await db.select(db.categories).get();
    final food = cats.firstWhere((c) => c.name == 'Food & chai').id;
    await BudgetRepo(
      db,
    ).create(name: 'Food & chai', limitPaise: 600000, categoryId: food);
    final now = DateTime.now();
    await txns.addExpense(
      amountPaise: 18000,
      accountId: cash,
      categoryId: food,
      title: 'Saravana Bhavan',
      at: DateTime(now.year, now.month, 1, 12),
    );
    return cash;
  }

  testWidgets('a budget row opens its own pace line', (tester) async {
    await seedFood();
    await tester.pumpWidget(host(const PlansPage()));
    await tester.pumpAndSettle();

    expect(find.byType(PaceChart), findsNothing);
    await tester.tap(find.text('Food & chai'));
    await tester.pumpAndSettle();
    expect(find.byType(PaceChart), findsOneWidget);

    // And folds away again.
    await tester.tap(find.text('Food & chai'));
    await tester.pumpAndSettle();
    expect(find.byType(PaceChart), findsNothing);

    await settleAndUnmount(tester);
  });

  testWidgets('month headline counts spending outside budgeted categories', (
    tester,
  ) async {
    final cash = await seedFood();
    final rent = (await db.select(db.categories).get())
        .firstWhere((c) => c.name == 'Rent')
        .id;
    await TxnRepo(db).addExpense(
      amountPaise: 650000,
      accountId: cash,
      categoryId: rent,
      title: 'Unbudgeted rent',
    );

    await tester.pumpWidget(host(const PlansPage()));
    await tester.pumpAndSettle();

    // ₹180 Food + ₹6,500 Rent is measured against the one ₹6,000 line.
    expect(find.text('₹680'), findsOneWidget);
    expect(find.text('over this month’s lines'), findsOneWidget);
    expect(find.text('₹0'), findsNothing);

    await settleAndUnmount(tester);
  });

  testWidgets('an empty goals page offers to name the first thing', (
    tester,
  ) async {
    await tester.pumpWidget(host(const PlansPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('goals'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing being saved for yet.'), findsOneWidget);
    expect(find.text('name the first thing'), findsOneWidget);

    await settleAndUnmount(tester);
  });

  testWidgets('a template draws a whole month, skipping lines that stand',
      (tester) async {
    // One hand-drawn line first: the template must land around it.
    final cats = await db.select(db.categories).get();
    final food = cats.firstWhere((c) => c.name == 'Food & chai').id;
    await BudgetRepo(
      db,
    ).create(name: 'Food & chai', limitPaise: 999900, categoryId: food);

    await tester.pumpWidget(host(const PlansPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('from a template'));
    await tester.pumpAndSettle();
    expect(find.text('A month, pre-drawn.'), findsOneWidget);
    expect(find.text('the at-home month'), findsOneWidget);
    expect(find.text('the Pune office month'), findsOneWidget);
    expect(find.text('the lean month'), findsOneWidget);

    await tester.tap(find.text('the at-home month'));
    await tester.pumpAndSettle();

    final drawn = await db.select(db.budgets).get();
    final byName = {for (final b in drawn) b.name: b.limitPaise};
    // The standing line was left exactly as drawn…
    expect(byName['Food & chai'], 999900);
    // …and the template's other lines landed with their own limits.
    expect(byName['Clothes & shoes'], 300000);
    expect(byName['Grooming & care'], 150000);
    expect(byName['Kirana & home'], 300000);
    expect(drawn.length, 7, reason: 'six template lines around one kept');

    await settleAndUnmount(tester);
  });

  testWidgets('the recurring shelf has a way onto it', (tester) async {
    final cash = await seedFood();
    await RecurringRepo(db, TxnRepo(db)).create(
      title: 'Rent',
      amountPaise: 1500000,
      accountId: cash,
      dayOfMonth: 5,
      kind: RecurringKind.bill,
    );

    await tester.pumpWidget(host(const PlansPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('recurring'));
    await tester.pumpAndSettle();

    expect(find.text('Rent'), findsOneWidget);
    await tester.tap(find.text('add a bill or a subscription'));
    await tester.pumpAndSettle();
    expect(find.text('onto the shelf'), findsOneWidget);

    await settleAndUnmount(tester);
  });
}
