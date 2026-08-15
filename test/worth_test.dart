import 'package:budgetbox/core/dates.dart';
import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/core/widgets/charts.dart';
import 'package:budgetbox/core/widgets/motion.dart';
import 'package:budgetbox/core/widgets/seal.dart';
import 'package:budgetbox/core/widgets/sheets.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/features/worth/worth_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  setUp(() => db = LedgerDb.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('the range control', () {
    test('each window asks the repo for the right stretch of days', () {
      final now = DateTime(2026, 8, 1);
      expect(WorthRange.month.days(now), 30);
      expect(WorthRange.halfYear.days(now), 180);
      // FY 26-27 opened 1 Apr 2026 — Apr(30) + May(31) + Jun(30) + Jul(31)
      // + to-day.
      expect(WorthRange.fy.days(now), 123);
      expect(WorthRange.all.days(now) > 365 * 50, isTrue);
    });

    test('the delta says which window it is talking about', () {
      final now = DateTime(2026, 8, 1);
      expect(WorthRange.month.phrase(now), 'over the past month');
      expect(WorthRange.halfYear.phrase(now), 'over six months');
      expect(
        WorthRange.fy.phrase(now),
        'so far this ${LedgerDates.fyLabel(now)}',
      );
      expect(WorthRange.fy.phrase(now), contains('FY 26-27'));
      expect(WorthRange.all.phrase(now), 'since the book opened');
    });

    testWidgets('picking a range rewrites the delta line', (tester) async {
      final id = await AccountRepo(db).create(
        name: 'Cash',
        kind: AccountKind.cash,
        openingBalancePaise: 500000,
      );
      // A reading from yesterday: the line needs two mornings to join
      // before the chart and its range chips appear at all.
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await db
          .into(db.balanceSnapshots)
          .insert(
            BalanceSnapshotsCompanion.insert(
              accountId: id,
              date: LedgerDates.dayKey(yesterday),
              balancePaise: 400000,
            ),
          );
      await tester.pumpWidget(host(const WorthPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('over six months'), findsOneWidget);

      await tester.tap(find.text('1M'));
      await tester.pumpAndSettle();
      expect(find.textContaining('over the past month'), findsOneWidget);
      expect(find.textContaining('over six months'), findsNothing);

      await tester.tap(find.text('FY'));
      await tester.pumpAndSettle();
      expect(find.textContaining('so far this FY'), findsOneWidget);

      await settleAndUnmount(tester);
    });
  });

  testWidgets('an empty shelf speaks, and opens the box', (tester) async {
    await tester.pumpWidget(host(const WorthPage()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing on the shelf yet.'), findsOneWidget);
    expect(find.textContaining('Add an account in the box'), findsOneWidget);

    await tester.tap(find.text('set up what you have ›'));
    await tester.pumpAndSettle();
    expect(find.text('What do you have right now?'), findsOneWidget);

    await settleAndUnmount(tester);
  });

  testWidgets('correcting a balance is stamped, not saved silently', (
    tester,
  ) async {
    final id = await AccountRepo(
      db,
    ).create(name: 'Cash', kind: AccountKind.cash, openingBalancePaise: 500000);
    await tester.pumpWidget(host(const WorthPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    // The sheet comes up through the shared kit — handle and all.
    expect(find.byType(SheetHandle), findsOneWidget);
    expect(find.textContaining('set the balance'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '7200');
    await tester.pumpAndSettle();

    await tester.tap(find.text('That\'s the number'), warnIfMissed: false);
    await tester.pump();
    // The seal lands before the figure is handed back.
    expect(find.byType(Seal), findsOneWidget);

    // The stamp presses down, then the sheet hands the figure over.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle();
    // The sheet takes itself away once the seal has landed.
    expect(find.byType(SheetHandle), findsNothing);

    final row = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(id))).getSingle();
    expect(row.balancePaise, 720000);

    await settleAndUnmount(tester);
  });

  testWidgets('a below-zero pocket can absorb the recorded spending: '
      '"what I had" minus what was written', (tester) async {
    // ₹500 of spending was recorded before any money was declared — the
    // classic young-book state that reads −₹500.
    final id = await AccountRepo(
      db,
    ).create(name: 'Cash', kind: AccountKind.cash, openingBalancePaise: -50000);
    await tester.pumpWidget(host(const WorthPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    // Below zero, the sheet offers both readings of the typed figure.
    expect(find.text('what\'s in it right now'), findsOneWidget);
    expect(find.text('what I had before the spending'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('what I had before the spending'));
    await tester.pumpAndSettle();

    // The preview does the arithmetic out loud: 1000 − 500 = 500.
    expect(find.textContaining('will read ₹500'), findsOneWidget);
    expect(find.textContaining('₹500 already written'), findsOneWidget);

    // The chips make this sheet taller than the flat one; under the test
    // binding the button sits below the keyboard, so press it by handler —
    // the save wiring is what this test guards, not hit-testing.
    tester
        .widget<Pressable>(
          find
              .ancestor(
                of: find.text('That\'s the number'),
                matching: find.byType(Pressable),
              )
              .first,
        )
        .onTap!();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle();
    // Let the write behind the pop reach the database.
    await tester.pump(const Duration(milliseconds: 400));

    final row = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(id))).getSingle();
    expect(row.balancePaise, 50000);

    await settleAndUnmount(tester);
  });

  testWidgets('long-pressing an account opens its balance history', (
    tester,
  ) async {
    await AccountRepo(
      db,
    ).create(name: 'Cash', kind: AccountKind.cash, openingBalancePaise: 500000);
    await tester.pumpWidget(host(const WorthPage()));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Cash'));
    await tester.pumpAndSettle();

    expect(find.byType(SheetHandle), findsOneWidget);
    // The sheet names the account again, above its readings.
    expect(find.text('Cash'), findsNWidgets(2));
    expect(find.textContaining('One reading so far'), findsOneWidget);
    expect(
      find.byType(Sparkline),
      findsWidgets,
      reason:
          'the account row keeps its compact spark; the sheet adds no blank chart',
    );

    await settleAndUnmount(tester);
  });
}
