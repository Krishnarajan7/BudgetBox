import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/book/book_page.dart';
import 'package:budgetbox/features/insights/insight_math.dart';
import 'package:budgetbox/features/insights/insights_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The month read for what was his to move — and the habits in it.
void main() {
  var nextId = 0;
  (int, String, int, String?, DateTime) line(
    String title,
    int rupees,
    String? cat,
    DateTime at,
  ) => (++nextId, title, rupees * 100, cat, at);

  DateTime d(int day, [int hour = 20]) => DateTime(2026, 9, day, hour);

  /// The shape of Krish's September: a PG, Rapido hops, Souled Store
  /// buys, shawarma evenings, a few standing charges and nine lines that
  /// only carry a category name.
  List<(int, String, int, String?, DateTime)> september() => [
    line('PG rent', 8500, 'Rent', d(7)),
    line('advance for PG', 3000, 'Rent', d(7)),
    line('Recharge', 890, 'Bills & recharge', d(5)),
    line('rapido', 45, 'Tickets & travel', d(11)),
    line('rapido * 2', 100, 'Tickets & travel', d(10)),
    line('auto rapido', 93, 'Bike & fuel', d(8)),
    line('rapido', 55, 'Tickets & travel', d(14)),
    line('rapido', 45, 'Tickets & travel', d(15)),
    line('rapido', 90, 'Tickets & travel', d(16)),
    line('rapido', 45, 'Tickets & travel', d(17)),
    line('shirt from souled store', 1259, 'Clothes & shoes', d(3)),
    line('baggy from Souled Store', 1979, 'Clothes & shoes', d(5)),
    line('pant from souled store', 1889, 'Clothes & shoes', d(5)),
    line('Souled store membership renewal', 99, 'Bills & recharge', d(2)),
    line('shawarma', 160, 'Food & chai', d(4)),
    line('shawarma', 260, 'Food & chai', d(6)),
    line('shawarma * 2', 389, 'Food & chai', d(12)),
    line('Spotify premium for 1 yr', 800, 'Bills & recharge', d(9)),
    line('Domain purchase for Ghouthia', 3600, 'Bills & recharge', d(1)),
    for (var i = 0; i < 9; i++)
      line('Food & chai', 200, 'Food & chai', d(1 + i, 21)),
  ];

  group('hands — the arithmetic', () {
    test('rent, bills and a deposit are not his to move; the rest is', () {
      final h = hands(september(), days: 17);
      // Rent 11,500 + recharge 890 + membership (bills) 99 + spotify
      // (bills) 800 + domain 3,600 are fixed by category or word.
      expect(h.fixedPaise, (8500 + 3000 + 890 + 99 + 800 + 3600) * 100);
      expect(h.flexiblePaise, h.totalPaise - h.fixedPaise);
      expect(h.share, greaterThan(0.3));
    });

    test('seven rapido hops become one habit called rides, paced', () {
      final h = hands(september(), days: 17);
      final rides = h.habits.singleWhere((x) => x.key == 'often:rides');
      expect(rides.kind, HabitKind.often);
      expect(rides.count, 7);
      expect(rides.paise, (45 + 100 + 93 + 55 + 45 + 90 + 45) * 100);
      expect(rides.search, 'rapido');
      // The hops began on the 8th and the last line is the 17th: ten days
      // of evidence, not seventeen — a habit that came with the move.
      expect(rides.days, 10);
      expect(rides.monthPaise, closeTo(47300 / 10 * 30.4, 100));
      final l = habitLine(rides);
      expect(l, startsWith('7 times in 10 days'));
      expect(l, contains('a month at this pace'));
      expect(l, contains('half of it back'));
    });

    test('three Souled Store buys are a shop, not a small habit', () {
      final h = hands(september(), days: 17);
      final shop = h.habits.singleWhere((x) => x.key == 'shop:souled');
      expect(shop.kind, HabitKind.shop);
      // The membership line is fixed (bills) and stays out of the cluster.
      expect(shop.count, 3);
      expect(shop.paise, (1259 + 1979 + 1889) * 100);
      expect(habitLine(shop), contains('3 visits in 17 days'));
      // "store" overlaps the same lines and is not raised twice.
      expect(h.habits.where((x) => x.key.endsWith(':store')), isEmpty);
    });

    test('shawarma evenings are small and often', () {
      final h = hands(september(), days: 17);
      final sh = h.habits.singleWhere((x) => x.key == 'often:shawarma');
      expect(sh.count, 3);
      expect(sh.paise, (160 + 260 + 389) * 100);
    });

    test('nine lines with only a category name are named as the gap', () {
      final h = hands(september(), days: 17);
      expect(h.habits.last.kind, HabitKind.unnamed);
      expect(h.habits.last.count, 9);
      expect(h.habits.last.paise, 9 * 200 * 100);
      expect(
        habitLine(h.habits.last),
        contains('9 lines this page cannot read'),
      );
    });

    test('standing charges in the flexible half are listed by the year', () {
      // A membership filed under Fun, not Bills, is his to cancel.
      final rows = [
        line('Souled store membership', 99, 'Fun & extras', d(2)),
        line('Netflix', 199, 'Fun & extras', d(3)),
      ];
      final h = hands(rows, days: 17);
      final st = h.habits.singleWhere((x) => x.key == 'standing');
      expect(st.count, 2);
      expect(st.paise, (99 + 199) * 12 * 100);
      expect(habitLine(st), contains('2 standing charges'));
    });

    test('a line a project claims is a client cost, not a habit', () {
      final rows = september();
      final domain = rows.singleWhere((r) => r.$2.startsWith('Domain'));
      final h = hands(rows, days: 17, claimed: {domain.$1});
      expect(h.fixedPaise, (8500 + 3000 + 890 + 99 + 800) * 100);
    });

    test('a habit he called fine is not raised again', () {
      final h = hands(september(), days: 17, muted: {'often:rides', 'unnamed'});
      expect(h.habits.where((x) => x.key == 'often:rides'), isEmpty);
      expect(h.habits.where((x) => x.kind == HabitKind.unnamed), isEmpty);
    });

    test('two of something is not a habit, and a habit needs real money', () {
      final rows = [
        line('chai', 15, 'Food & chai', d(1)),
        line('chai', 15, 'Food & chai', d(2)),
        line('chai', 15, 'Food & chai', d(3)),
        line('cake', 425, 'Food & chai', d(4)),
        line('cake', 425, 'Food & chai', d(5)),
      ];
      final h = hands(rows, days: 17);
      // ₹45 of chai over 17 days is below the floor; two cakes are two.
      expect(h.habits, isEmpty);
    });

    test('weekends carrying the month are said, from three of them on', () {
      final rows = [
        line('shawarma', 300, 'Food & chai', DateTime(2026, 9, 5)), // sat
        line('movie', 1200, 'Fun & extras', DateTime(2026, 9, 6)), // sun
        line('biriyani', 700, 'Food & chai', DateTime(2026, 9, 12)), // sat
        line('lunch', 150, 'Food & chai', DateTime(2026, 9, 8)), // mon
        line('lunch', 150, 'Food & chai', DateTime(2026, 9, 9)), // tue
      ];
      final h = hands(rows, days: 17);
      final w = h.habits.singleWhere((x) => x.key == 'weekend');
      expect(w.count, 3);
      expect(w.paise, (300 + 1200 + 700) * 100);
    });

    test('roundNear says about, not to the rupee', () {
      expect(roundNear(47_312), 47_000);
      expect(roundNear(1_694_120), 1_690_000);
    });
  });

  group('the page', () {
    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('rides show as a habit and "that\'s fine" puts them away', (
      tester,
    ) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final cash = await AccountRepo(
        db,
      ).create(name: 'Cash', kind: AccountKind.cash);
      final txns = TxnRepo(db);
      final now = DateTime.now();
      for (var i = 1; i <= 4; i++) {
        await txns.addExpense(
          amountPaise: 5000,
          accountId: cash,
          title: 'rapido',
          at: now.subtract(Duration(days: i)),
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const InsightsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final head = find.text('IN YOUR HANDS');
      await tester.scrollUntilVisible(
        head,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(head, findsOneWidget);
      expect(find.textContaining('yours to move'), findsOneWidget);
      expect(find.text('rides'), findsOneWidget);
      expect(find.textContaining('4 times in'), findsOneWidget);

      final fine = find.byKey(const ValueKey('habit-fine-often:rides'));
      await tester.ensureVisible(fine);
      await tester.pumpAndSettle();
      await tester.tap(fine);
      await tester.pumpAndSettle();
      expect(find.text('rides'), findsNothing);
      expect(find.textContaining('nothing repeats enough'), findsOneWidget);
      expect(await SettingsRepo(db).handsMuted(), {'often:rides'});
      await unmount(tester);
    });

    testWidgets('a habit row opens the book, and the book stands on its own', (
      tester,
    ) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final cash = await AccountRepo(
        db,
      ).create(name: 'Cash', kind: AccountKind.cash);
      final txns = TxnRepo(db);
      final now = DateTime.now();
      for (var i = 1; i <= 4; i++) {
        await txns.addExpense(
          amountPaise: 5000,
          accountId: cash,
          title: 'rapido',
          at: now.subtract(Duration(days: i)),
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const InsightsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final door = find.byKey(const ValueKey('habit-open-often:rides'));
      await tester.scrollUntilVisible(
        door,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(door);
      await tester.pumpAndSettle();
      await tester.tap(door);
      await tester.pumpAndSettle();
      // The book is up, searched on the word, with no ink complaint from
      // its bar — it was pushed without a Material ancestor once.
      expect(find.byType(BookPage), findsOneWidget);
      expect(find.text('rapido'), findsWidgets);
      expect(tester.takeException(), isNull);
      // It stands clear of the status bar and wears a way back.
      expect(find.byType(SafeArea), findsWidgets);
      final back = find.byKey(const ValueKey('bar-back'));
      expect(back, findsOneWidget);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsNothing);
      await unmount(tester);
    });

    testWidgets('the book opens on the habit\'s word', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final cash = await AccountRepo(
        db,
      ).create(name: 'Cash', kind: AccountKind.cash);
      final txns = TxnRepo(db);
      final now = DateTime.now();
      await txns.addExpense(
        amountPaise: 5000,
        accountId: cash,
        title: 'rapido',
        at: now,
      );
      await txns.addExpense(
        amountPaise: 7000,
        accountId: cash,
        title: 'shawarma',
        at: now,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const Scaffold(body: BookPage(initialQuery: 'rapido')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('rapido'), findsWidgets);
      expect(find.text('shawarma'), findsNothing);
      await unmount(tester);
    });
  });
}
