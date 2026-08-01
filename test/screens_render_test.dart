import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/book/book_page.dart';
import 'package:budgetbox/features/calendar/calendar_page.dart';
import 'package:budgetbox/features/focus/focus_page.dart';
import 'package:budgetbox/features/journal/journal_page.dart';
import 'package:budgetbox/features/lock/lock_page.dart';
import 'package:budgetbox/features/notes/notes_page.dart';
import 'package:budgetbox/features/plans/plans_page.dart';
import 'package:budgetbox/features/settings/settings_page.dart';
import 'package:budgetbox/features/setup/setup_flow.dart';
import 'package:budgetbox/features/story/story_page.dart';
import 'package:budgetbox/features/today/today_page.dart';
import 'package:budgetbox/features/vault/vault_page.dart';
import 'package:budgetbox/features/worth/worth_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every screen must survive a build against a real (if small) book, and
/// against an empty one. Cheap insurance: a screen that throws in build
/// takes the whole app down with a red page.
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

  Future<void> seed() async {
    final accounts = AccountRepo(db);
    final txns = TxnRepo(db);
    final cash = await accounts.create(
      name: 'Cash',
      kind: AccountKind.cash,
      openingBalancePaise: 500000,
    );
    await accounts.create(
      name: 'Camera EMI',
      kind: AccountKind.liability,
      openingBalancePaise: 2800000,
    );
    final cats = await db.select(db.categories).get();
    final food = cats.firstWhere((c) => c.name == 'Food & chai').id;
    final now = DateTime.now();

    await txns.addIncome(
      amountPaise: 9200000,
      accountId: cash,
      title: 'Salary',
      at: DateTime(now.year, now.month, 1, 9),
    );
    // Two entries on the same day so the "biggest day" tally has to pick.
    await txns.addExpense(
      amountPaise: 18000,
      accountId: cash,
      categoryId: food,
      title: 'Saravana Bhavan',
      at: DateTime(now.year, now.month, now.day, 12),
    );
    await txns.addExpense(
      amountPaise: 2000,
      accountId: cash,
      categoryId: food,
      title: "chai at Ganesh's",
      at: DateTime(now.year, now.month, now.day, 8),
    );
  }

  final screens = <String, Widget>{
    'Today': const TodayPage(),
    'Book': const BookPage(),
    'Plans': const PlansPage(),
    'Worth': const WorthPage(),
    'Story': const StoryPage(),
    'Lock': const LockPage(),
    'Settings': const SettingsPage(),
    'Setup ritual': const SetupFlow(),
    'Notes': const NotesPage(),
    'Focus': const FocusPage(),
    'Journal': const JournalPage(),
    'Calendar': const CalendarPage(),
    'Vault': const VaultPage(),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} renders with a book that has entries',
        (tester) async {
      await seed();
      await tester.pumpWidget(host(entry.value));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await settleAndUnmount(tester);
    });

    testWidgets('${entry.key} renders on a blank book', (tester) async {
      await tester.pumpWidget(host(entry.value));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await settleAndUnmount(tester);
    });
  }

  testWidgets('the story swipes to the Sankey without throwing',
      (tester) async {
    await seed();
    await tester.pumpWidget(host(const StoryPage()));
    await tester.pumpAndSettle();

    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.textContaining('came in'), findsOneWidget);
    await settleAndUnmount(tester);
  });
}
