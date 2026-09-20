import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/insights/insight_math.dart';
import 'package:budgetbox/features/insights/insights_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page that says where the money went — and, more usefully, where it
/// *moved*.
void main() {
  group('categoryShifts — the arithmetic', () {
    test('sorts by the size of the movement, both directions', () {
      final shifts = categoryShifts(
        [(1, 10000), (2, 50000)], // this month
        [(1, 40000), (2, 45000)], // last month
      );
      // Food fell ₹300, chai rose ₹50: the fall leads.
      expect(shifts.first.categoryId, 1);
      expect(shifts.first.deltaPaise, -30000);
      expect(shifts.last.categoryId, 2);
      expect(shifts.last.deltaPaise, 5000);
    });

    test('names arrivals and departures', () {
      final shifts = categoryShifts(
        [(1, 20000)],
        [(2, 15000)],
      );
      expect(shifts.firstWhere((s) => s.categoryId == 1).isNew, isTrue);
      expect(shifts.firstWhere((s) => s.categoryId == 2).wentQuiet, isTrue);
    });

    test('a category that did not move says nothing', () {
      final shifts = categoryShifts([(1, 5000)], [(1, 5000)]);
      expect(shifts, isEmpty);
    });
  });

  group('InsightsPage', () {
    testWidgets('two months of entries become totals, bars and shifts',
        (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final accountId = await AccountRepo(db)
          .create(name: 'Cash', kind: AccountKind.cash);
      final cats = await db.select(db.categories).get();
      final food = cats.firstWhere((c) => c.name == 'Food & chai').id;

      final now = DateTime.now();
      final txns = TxnRepo(db);
      await txns.addExpense(
          amountPaise: 30000,
          accountId: accountId,
          categoryId: food,
          title: 'mess bill',
          at: now);
      await txns.addExpense(
          amountPaise: 12000,
          accountId: accountId,
          title: 'unfiled thing',
          at: now);
      // Last month: food cost more.
      await txns.addExpense(
          amountPaise: 50000,
          accountId: accountId,
          categoryId: food,
          title: 'mess bill',
          at: DateTime(now.year, now.month - 1, 15));

      await tester.pumpWidget(ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(
            theme: ledgerDayTheme(), home: const InsightsPage()),
      ));
      await tester.pumpAndSettle();

      // The month's figure and its verdict against last month.
      expect(find.text('₹420'), findsOneWidget);
      expect(find.textContaining('lighter than last month'), findsOneWidget);

      // The month's shape, then the ranking — each line judged against
      // its own past: food ran ₹200 under its ₹500 usual; the unfiled
      // entry has no past to judge by and says so instead of guessing.
      expect(find.text('THE DAYS'), findsOneWidget);
      expect(find.text('WHERE IT WENT'), findsOneWidget);
      expect(find.text('Food & chai'), findsWidgets);
      expect(find.textContaining('under its usual'), findsOneWidget);
      expect(find.textContaining('first seen'), findsOneWidget);
      // And the share, so the heaviest is tellable at a glance.
      expect(find.text('71%'), findsOneWidget);

      // The movement against last month: food fell ₹200 — exactly at the
      // floor, so it is still news; the ₹120 arrival is not.
      await tester.scrollUntilVisible(find.text('−₹200'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('−₹200'), findsOneWidget);

      // The heaviest single line — at the foot of the page, so scroll.
      await tester.scrollUntilVisible(find.text('HEAVIEST LINES'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('HEAVIEST LINES'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a book with nothing written says so', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(
            theme: ledgerDayTheme(), home: const InsightsPage()),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('a quiet page has nothing to explain'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('erasing the book', () {
    test('every table empties, the categories come back seeded', () async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final accountId = await AccountRepo(db)
          .create(name: 'Cash', kind: AccountKind.cash);
      await TxnRepo(db).addExpense(
          amountPaise: 2000,
          accountId: accountId,
          title: 'chai',
          at: DateTime.now());

      await db.eraseBook();

      expect(await db.select(db.txns).get(), isEmpty);
      expect(await db.select(db.accounts).get(), isEmpty);
      expect(await db.select(db.settings).get(), isEmpty);
      expect(await db.select(db.outbox).get(), isEmpty);
      // An empty book still needs words for money.
      final cats = await db.select(db.categories).get();
      expect(cats.map((c) => c.name), contains('Food & chai'));
      expect(cats.length, greaterThanOrEqualTo(8));
    });
  });

  group('the shape of the days', () {
    test('daily totals land on their day', () {
      final daily = dailyTotals([(1, 5000), (1, 2000), (14, 10000)], 31);
      expect(daily.length, 31);
      expect(daily[0], 7000);
      expect(daily[13], 10000);
    });

    test('the heaviest day must genuinely stand out', () {
      // ₹500 on the 3rd against ₹40 days around it: a story.
      final spiky = dailyTotals([(3, 50_000), (1, 4_000), (2, 4_000)], 30);
      expect(heaviestDay(spiky, elapsed: 10), (3, 50_000));
      // A flat month has no heaviest day worth a sentence.
      final flat = dailyTotals(
        [for (var d = 1; d <= 10; d++) (d, 50_000)],
        30,
      );
      expect(heaviestDay(flat, elapsed: 10), isNull);
    });

    test('the quietest week is named only when genuinely quiet', () {
      // Two loud weeks, then silence.
      final daily = dailyTotals(
        [for (var d = 1; d <= 14; d++) (d, 100_000)],
        31,
      );
      expect(quietestWeek(daily, elapsed: 28), (15, 0));
      // Under two weeks lived: too soon to talk about a quiet week.
      expect(quietestWeek(daily, elapsed: 13), isNull);
      // An even month has no quiet stretch worth a line.
      final even = dailyTotals(
        [for (var d = 1; d <= 28; d++) (d, 50_000)],
        31,
      );
      expect(quietestWeek(even, elapsed: 28), isNull);
    });

    test('projection speaks only when the month can be extrapolated', () {
      expect(
        paceProjection(
          spentPaise: 70_000,
          elapsedDays: 7,
          daysInMonth: 30,
          priorMonthTotals: [200_000],
        ),
        (projected: 300_000, usual: 200_000),
      );
      // Too young to extrapolate honestly.
      expect(
        paceProjection(
          spentPaise: 70_000,
          elapsedDays: 5,
          daysInMonth: 30,
          priorMonthTotals: [],
        ),
        isNull,
      );
      // The last day is no longer a projection.
      expect(
        paceProjection(
          spentPaise: 70_000,
          elapsedDays: 30,
          daysInMonth: 30,
          priorMonthTotals: [],
        ),
        isNull,
      );
      // Quiet prior months are not a yardstick.
      final noPrior = paceProjection(
        spentPaise: 140_000,
        elapsedDays: 14,
        daysInMonth: 28,
        priorMonthTotals: [0, 0, 0],
      )!;
      expect(noPrior.projected, 280_000);
      expect(noPrior.usual, isNull);
    });
  });

  group('categoryStories — every judgement against its own past', () {
    // (category, paise, title) rows; category 1 is food, 2 is tickets.
    List<SpendRow> month(List<(int?, int, String)> rows) => rows;

    test('ranked heaviest first, with honest shares', () {
      final stories = categoryStories(
        month([(1, 60_000, 'meals'), (2, 40_000, 'bus')]),
        const [],
      );
      expect(stories.map((s) => s.categoryId), [1, 2]);
      expect(stories.first.share, 0.6);
      expect(stories.last.share, 0.4);
    });

    test('running hot means past its own median, not any yardstick', () {
      final stories = categoryStories(
        month([(1, 90_000, 'meals')]),
        [
          month([(1, 50_000, 'meals')]),
          month([(1, 60_000, 'meals')]),
          month([(1, 40_000, 'meals')]),
        ],
      );
      final food = stories.single;
      // Median of 40/50/60k is 50k; 90k is 40k past it.
      expect(food.usualPaise, 50_000);
      expect(food.verdict, CategoryVerdict.runningHot);
      expect(food.overPaise, 40_000);
    });

    test('a small swing is not news', () {
      // ₹120 over a ₹500 usual: over the band by ratio, but under the
      // rupee floor — chai does not make headlines.
      final stories = categoryStories(
        month([(1, 62_000, 'meals')]),
        [month([(1, 50_000, 'meals')])],
      );
      expect(stories.single.verdict, CategoryVerdict.steady);
    });

    test('months that never knew a category are not counted as zero', () {
      // Tickets appear once in history. If the two quiet months counted
      // as ₹0, the median would be 0 and any ticket would read as "hot".
      final stories = categoryStories(
        month([(2, 80_000, 'bus to Madurai')]),
        [
          month([(1, 50_000, 'meals')]),
          month([(1, 50_000, 'meals'), (2, 80_000, 'flight')]),
          month([(1, 50_000, 'meals')]),
        ],
      );
      final tickets = stories.singleWhere((s) => s.categoryId == 2);
      expect(tickets.usualPaise, 80_000);
      expect(tickets.verdict, CategoryVerdict.steady);
    });

    test('one line holding a category is named as the story', () {
      final stories = categoryStories(
        month([(2, 4_50_000, 'flight home'), (2, 30_000, 'auto')]),
        [month([(2, 40_000, 'bus')])],
      );
      expect(stories.single.verdict, CategoryVerdict.oneBigLine);
      expect(stories.single.biggestTitle, 'flight home');
    });

    test('a category with no history says so instead of guessing', () {
      final stories = categoryStories(
        month([(3, 25_000, 'cake')]),
        [month([(1, 50_000, 'meals')])],
      );
      expect(stories.single.verdict, CategoryVerdict.firstMonth);
      expect(stories.single.usualPaise, isNull);
    });

    test('the headline names the hottest runner, or stays calm', () {
      final hot = categoryStories(
        month([(1, 90_000, 'meals'), (2, 10_000, 'bus')]),
        [month([(1, 40_000, 'meals'), (2, 10_000, 'bus')])],
      );
      final (story, calm) = headline(hot)!;
      expect(calm, isFalse);
      expect(story.categoryId, 1);

      final quiet = categoryStories(
        month([(1, 42_000, 'meals')]),
        [month([(1, 40_000, 'meals')])],
      );
      final (lead, isCalm) = headline(quiet)!;
      expect(isCalm, isTrue);
      expect(lead.categoryId, 1);

      expect(headline(const []), isNull);
    });
  });
}
