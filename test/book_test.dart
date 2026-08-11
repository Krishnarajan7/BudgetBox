import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/core/widgets/cat_mark.dart';
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
    expect(rewriteWhisper(1, DateTime(2026, 7, 12)), 'rewritten once · last on 12 Jul');
    expect(rewriteWhisper(2, DateTime(2026, 7, 12)), 'rewritten twice · last on 12 Jul');
    expect(
        rewriteWhisper(9, DateTime(2026, 7, 12)), 'rewritten 9 times · last on 12 Jul');
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

      expect(find.byType(CatMark), findsWidgets);
      await settleAndUnmount(tester);
    });

    testWidgets('a struck line stays on the page and can be kept',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.drag(find.text('Chai'), const Offset(-400, 0));
      await tester.pumpAndSettle();

      // Struck, not gone: nothing has left the database yet.
      expect(find.textContaining('tap to keep it'), findsOneWidget);
      expect(await db.select(db.txns).get(), hasLength(1));

      await tester.tap(find.textContaining('tap to keep it'));
      await tester.pumpAndSettle();

      expect(find.text('Chai'), findsOneWidget);
      expect(find.textContaining('tap to keep it'), findsNothing);

      // Well past the grace — the entry that was kept is still there.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(await db.select(db.txns).get(), hasLength(1));

      await settleAndUnmount(tester);
    });

    testWidgets('left alone, the strike lands after its grace',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.drag(find.text('Chai'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(await db.select(db.txns).get(), hasLength(1));

      await tester.pump(bookStrikeGrace + const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(await db.select(db.txns).get(), isEmpty);
      // The account got its money back with the line.
      final account = (await db.select(db.accounts).get()).single;
      expect(account.balancePaise, 500000);

      await settleAndUnmount(tester);
    });

    testWidgets('the heat view closes with one sentence, not a tally',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('heat'));
      await tester.pumpAndSettle();

      expect(find.textContaining('entry written'), findsOneWidget);
      expect(find.text('Quiet days'), findsNothing);
      expect(find.text('Entries written'), findsNothing);

      await settleAndUnmount(tester);
    });
  });
}
