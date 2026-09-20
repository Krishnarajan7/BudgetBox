import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/core/undo_banner.dart';
import 'package:budgetbox/core/widgets/plates.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/book/book_page.dart';
import 'package:budgetbox/features/book/txn_editor.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the book says its numbers', () {
    test('small counts are spelled, large ones stay figures', () {
      expect(bookCount(0).text, 'no');
      expect(bookCount(0).mono, isFalse);
      expect(bookCount(1).text, 'one');
      expect(bookCount(9).text, 'nine');
      expect(bookCount(12).text, 'twelve');
      expect(bookCount(22).text, '22');
      expect(bookCount(22).mono, isTrue);
    });

    test('days get their ordinal', () {
      expect(bookOrdinal(1), '1st');
      expect(bookOrdinal(2), '2nd');
      expect(bookOrdinal(3), '3rd');
      expect(bookOrdinal(4), '4th');
      expect(bookOrdinal(11), '11th');
      expect(bookOrdinal(12), '12th');
      expect(bookOrdinal(13), '13th');
      expect(bookOrdinal(21), '21st');
      expect(bookOrdinal(31), '31st');
    });
  });

  group('the heaviest line only speaks when it matters', () {
    test('a modest entry stays quiet', () {
      expect(shareOfMonth(1000, 100000), isNull);
      expect(shareOfMonth(0, 100000), isNull);
      expect(shareOfMonth(500, 0), isNull);
    });

    test('an outsized entry gets a share in words', () {
      expect(shareOfMonth(20000, 100000), 'about a fifth');
      expect(shareOfMonth(25000, 100000), 'about a quarter');
      expect(shareOfMonth(35000, 100000), 'about a third');
      expect(shareOfMonth(60000, 100000), 'nearly half');
    });
  });

  test('the rewrite whisper reads like a margin note', () {
    expect(
      rewriteWhisper(1, DateTime(2026, 7, 12)),
      'rewritten once · last on 12 Jul',
    );
    expect(
      rewriteWhisper(2, DateTime(2026, 7, 12)),
      'rewritten twice · last on 12 Jul',
    );
    expect(
      rewriteWhisper(9, DateTime(2026, 7, 12)),
      'rewritten 9 times · last on 12 Jul',
    );
  });

  group('striking a line out', () {
    late LedgerDb db;

    Widget host() => ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ledgerDayTheme(),
        home: const Scaffold(body: BookPage()),
      ),
    );

    Future<void> settleAndUnmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    setUp(() async {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      final cash = await AccountRepo(db).create(
        name: 'Cash',
        kind: AccountKind.cash,
        openingBalancePaise: 500000,
      );
      final cats = await db.select(db.categories).get();
      final food = cats.firstWhere((c) => c.kind == CategoryKind.expense).id;
      final now = DateTime.now();
      await TxnRepo(db).addExpense(
        amountPaise: 18000,
        accountId: cash,
        categoryId: food,
        title: 'Chai',
        at: DateTime(now.year, now.month, now.day, 12),
      );
    });

    tearDown(() => db.close());

    testWidgets('every line carries its category mark', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.byType(Medallion), findsWidgets);
      await settleAndUnmount(tester);
    });

    testWidgets('a struck line dissolves, offers undo, and undo re-forms it', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.drag(find.text('Chai'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      // Through the stroke and the full dissolve; the undo offer stands.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(BookPage)),
      );
      final banner = container.read(undoBannerProvider);
      expect(banner, isNotNull);
      // Dissolved, not gone: nothing has left the database yet.
      expect(await db.select(db.txns).get(), hasLength(1));

      // Undo: the particles run backwards and the line stands whole again.
      banner!.onUndo();
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 850));
      await tester.pump();

      expect(find.text('Chai'), findsOneWidget);
      expect(container.read(undoBannerProvider), isNull);

      // Well past the undo window — the kept entry is still there.
      await tester.pump(const Duration(seconds: 8));
      await tester.pump();
      expect(await db.select(db.txns).get(), hasLength(1));

      await settleAndUnmount(tester);
    });

    testWidgets('left alone, the strike lands after its undo window', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.drag(find.text('Chai'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      // Through the stroke and the full dissolve, into the undo window.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
      expect(await db.select(db.txns).get(), hasLength(1));

      await tester.pump(bookStrikeGrace + const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(await db.select(db.txns).get(), isEmpty);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BookPage)),
      );
      expect(container.read(undoBannerProvider), isNull);
      // The account got its money back with the line.
      final account = (await db.select(db.accounts).get()).single;
      expect(account.balancePaise, 500000);

      await settleAndUnmount(tester);
    });

    testWidgets('a busy past day folds its small lines under one quiet line', (
      tester,
    ) async {
      final now = DateTime.now();
      // On the 1st there is no past day in the month to fold — today
      // itself never folds. The fold is exercised the other 27+ mornings.
      if (now.day == 1) return;
      final cash = (await db.select(db.accounts).get()).single.id;
      final day1 = DateTime(now.year, now.month, 1, 10);
      await TxnRepo(db).addExpense(
        amountPaise: 100000,
        accountId: cash,
        title: 'Big shop',
        at: day1,
      );
      for (var i = 1; i <= 5; i++) {
        await TxnRepo(db).addExpense(
          amountPaise: 2000,
          accountId: cash,
          title: 'chai $i',
          at: day1.add(Duration(minutes: i)),
        );
      }

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // The line that shaped the day stands; the five ₹20s sleep under
      // one quiet line saying what they cost together.
      expect(find.text('Big shop'), findsOneWidget);
      expect(find.text('chai 1'), findsNothing);
      expect(find.textContaining('quieter lines'), findsOneWidget);

      // Tapping spreads them open in place.
      await tester.tap(find.textContaining('quieter lines'));
      await tester.pumpAndSettle();
      expect(find.text('chai 1'), findsOneWidget);

      // And folds them back.
      await tester.tap(find.textContaining('quieter lines'));
      await tester.pumpAndSettle();
      expect(find.text('chai 1'), findsNothing);

      await settleAndUnmount(tester);
    });

    testWidgets('the heat view closes with one sentence, not a tally', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('month'));
      await tester.pumpAndSettle();

      expect(find.textContaining('entry written'), findsOneWidget);
      expect(find.text('Quiet days'), findsNothing);
      expect(find.text('Entries written'), findsNothing);

      await settleAndUnmount(tester);
    });

    testWidgets('the search has a way out: clear keeps the pen, cancel lifts it', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // Idle: no clear mark, no cancel word.
      expect(find.byKey(const ValueKey('book-search-clear')), findsNothing);
      expect(find.byKey(const ValueKey('book-search-cancel')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('book-search')), 'cha');
      await tester.pumpAndSettle();
      // Typing narrows the page in place and keeps score of the matches.
      expect(find.byKey(const ValueKey('book-match-line')), findsOneWidget);
      expect(find.textContaining('1 match'), findsOneWidget);
      expect(find.byKey(const ValueKey('book-search-clear')), findsOneWidget);
      expect(find.byKey(const ValueKey('book-search-cancel')), findsOneWidget);

      // A miss says so, and says it once.
      await tester.enterText(find.byKey(const ValueKey('book-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('matches "zzz"'), findsOneWidget);
      expect(find.text('no matches'), findsOneWidget);

      // Clear empties the field but the pen stays in it.
      await tester.tap(find.byKey(const ValueKey('book-search-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('book-match-line')), findsNothing);
      expect(find.byKey(const ValueKey('book-search-clear')), findsNothing);
      expect(find.byKey(const ValueKey('book-search-cancel')), findsOneWidget);

      // Cancel lifts it out entirely: the row returns to its idle state.
      await tester.tap(find.byKey(const ValueKey('book-search-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('book-search-cancel')), findsNothing);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('book-search')),
      );
      expect(field.focusNode!.hasFocus, isFalse);

      await settleAndUnmount(tester);
    });

    testWidgets('the month\'s income figure opens the income page', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('book-income-door')));
      await tester.pumpAndSettle();
      expect(find.text('Income'), findsOneWidget);

      await settleAndUnmount(tester);
    });
  });
}
