import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/settings/activity_log.dart';
import 'package:budgetbox/features/settings/settings_page.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the box — plain facts', () {
    test('ordinalDay says the day the way a person would', () {
      expect(ordinalDay(1), '1st');
      expect(ordinalDay(2), '2nd');
      expect(ordinalDay(3), '3rd');
      expect(ordinalDay(4), '4th');
      expect(ordinalDay(11), '11th');
      expect(ordinalDay(12), '12th');
      expect(ordinalDay(13), '13th');
      expect(ordinalDay(21), '21st');
      expect(ordinalDay(31), '31st');
    });

    test('yearFrameCaption names the frame and the months it spans', () {
      final d = DateTime(2026, 7, 31);
      expect(yearFrameCaption('fy', now: d), 'FY 26-27 · April to March');
      expect(
          yearFrameCaption('calendar', now: d), '2026 · January to December');
    });

    test('salaryDayGrid lays 1–31 seven to a line', () {
      final grid = salaryDayGrid();
      expect(grid.length, 5);
      expect(grid.first, [1, 2, 3, 4, 5, 6, 7]);
      expect(grid.last, [29, 30, 31]);
      expect(grid.expand((r) => r).toList(), [for (var d = 1; d <= 31; d++) d]);
    });
  });

  group('CSV export', () {
    test('cells quote only when they must', () {
      expect(csvCell('chai'), 'chai');
      expect(csvCell('lunch, Saravana'), '"lunch, Saravana"');
      expect(csvCell('the "good" auto'), '"the ""good"" auto"');
      expect(csvCell('two\nlines'), '"two\nlines"');
    });

    test('paise become plain rupees, two decimals, no symbol', () {
      expect(csvAmount(2000), '20.00');
      expect(csvAmount(18050), '180.50');
      expect(csvAmount(7), '0.07');
    });

    test('the sheet carries names, not ids', () async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      final accountId =
          await AccountRepo(db).create(name: 'Cash', kind: AccountKind.cash);
      final category = await (db.select(db.categories)
            ..where((c) => c.name.equals('Food & chai')))
          .getSingle();
      await TxnRepo(db).addExpense(
        amountPaise: 18000,
        accountId: accountId,
        title: 'lunch, Saravana',
        categoryId: category.id,
        at: DateTime(2026, 7, 14, 12, 40),
      );

      final txns = await (db.select(db.txns)
            ..orderBy([(t) => OrderingTerm.asc(t.at)]))
          .get();
      final csv = buildLedgerCsv(
        txns,
        categories: {category.id: category.name},
        accounts: {accountId: 'Cash'},
      );

      final lines = csv.trim().split('\n');
      expect(lines.first,
          'date,time,title,type,amount,category,account,note');
      expect(
        lines[1],
        '2026-07-14,12:40,"lunch, Saravana",expense,180.00,Food & chai,Cash,',
      );

      await db.close();
    });
  });

  group('the activity log reads its own strokes', () {
    test('word, snapshot and day grouping', () async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      final accountId =
          await AccountRepo(db).create(name: 'Cash', kind: AccountKind.cash);
      final repo = TxnRepo(db);
      final id = await repo.addExpense(
        amountPaise: 2000,
        accountId: accountId,
        title: 'chai',
      );
      await repo.deleteTxn(id);

      final rows = await (db.select(db.activities)
            ..orderBy([(a) => OrderingTerm.desc(a.id)]))
          .get();
      final strokes = [for (final r in rows) strokeFrom(r)!];

      expect(strokes.map((s) => strokeWord(s.action)), ['struck', 'wrote']);
      expect(strokes.first.title, 'chai');
      expect(strokes.first.amountPaise, 2000);
      expect(strokes.first.isStrike, isTrue);

      // Both strokes happened to-day — one block.
      expect(strokesByDay(strokes).length, 1);
      expect(strokesByDay(strokes).single.$2.length, 2);
      expect(
        strokeDayLabel(strokesByDay(strokes).single.$1),
        'to-day',
      );

      await db.close();
    });

    test('an unreadable snapshot is dropped, not half-drawn', () async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      await db.customStatement(
        "INSERT INTO activities (txn_id, action, snapshot, at) "
        "VALUES (1, 2, 'not json', 0)",
      );
      final row = await db.select(db.activities).getSingle();
      expect(strokeFrom(row), isNull);
      await db.close();
    });
  });

  group('the box on the page', () {
    Future<void> drain(WidgetTester tester, LedgerDb db) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await db.close();
    }

    testWidgets('every row says something true, and the footer counts',
        (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      final accountId =
          await AccountRepo(db).create(name: 'Cash', kind: AccountKind.cash);
      await TxnRepo(db)
          .addExpense(amountPaise: 2000, accountId: accountId, title: 'chai');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('the 1st, every month'), findsOneWidget);
      expect(find.text('${DateTime.now().year} · January to December'),
          findsOneWidget);
      // No PIN yet, so the face is honest about waiting for one.
      expect(find.text('waits on a PIN — set one and the face takes over'),
          findsOneWidget);
      // The footer sits below the fold — scroll the box to its last line.
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('home-cooked, for one · '), findsOneWidget);
      expect(find.text(' entry · '), findsOneWidget);
      expect(find.text(' days closed'), findsOneWidget);

      await drain(tester, db);
    });

    testWidgets('salary day is picked from the grid and kept', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Salary day'));
      await tester.pumpAndSettle();
      expect(find.text('when does the money land?'), findsOneWidget);

      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();

      expect(find.text('the 15th, every month'), findsOneWidget);
      expect(await SettingsRepo(db).salaryDay(), 15);

      await drain(tester, db);
    });

    testWidgets('the year frame swaps in place', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();

      expect(await SettingsRepo(db).yearFrame(), 'fy');
      expect(find.textContaining('April to March'), findsOneWidget);

      await drain(tester, db);
    });

    testWidgets('the newest strike can be brought back', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      final accountId =
          await AccountRepo(db).create(name: 'Cash', kind: AccountKind.cash);
      final repo = TxnRepo(db);
      final id = await repo.addExpense(
        amountPaise: 2000,
        accountId: accountId,
        title: 'chai',
      );
      await repo.deleteTxn(id);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const ActivityLogPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('struck'), findsOneWidget);
      expect(find.text('wrote'), findsOneWidget);
      expect(
        find.textContaining('chai', findRichText: true),
        findsNWidgets(2),
      );
      expect(find.text('bring it back'), findsOneWidget);

      await tester.tap(find.text('bring it back'));
      await tester.pumpAndSettle();

      expect(await db.select(db.txns).get(), hasLength(1));
      // The strike is gone from the log; only writings remain.
      expect(find.text('struck'), findsNothing);
      expect(find.text('bring it back'), findsNothing);

      await drain(tester, db);
    });

    testWidgets('an empty log says so', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const ActivityLogPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing to confess. The book is as written.'),
        findsOneWidget,
      );

      await drain(tester, db);
    });
  });
}
