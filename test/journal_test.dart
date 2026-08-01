import 'package:budgetbox/core/dates.dart';
import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/journal_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/journal/journal_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LedgerDb db;
  late JournalRepo repo;

  setUp(() {
    db = LedgerDb.forTesting(NativeDatabase.memory());
    repo = JournalRepo(db);
  });

  tearDown(() => db.close());

  group('JournalRepo.upsert', () {
    test('setting mood does not clobber body, and vice versa', () async {
      await repo.upsert('2026-07-30', body: 'wrote a little');
      await repo.upsert('2026-07-30', mood: 4);

      var e = await repo.watch('2026-07-30').first;
      expect(e, isNotNull);
      expect(e!.body, 'wrote a little');
      expect(e.mood, 4);

      await repo.upsert('2026-07-30', body: 'wrote a little more');
      e = await repo.watch('2026-07-30').first;
      expect(e!.body, 'wrote a little more');
      expect(e.mood, 4, reason: 'a body write must leave the mood alone');
    });

    test('creates the page on first write, mood-only included', () async {
      await repo.upsert('2026-07-29', mood: 2);
      final e = await repo.watch('2026-07-29').first;
      expect(e!.mood, 2);
      expect(e.body, '', reason: 'body falls back to the empty default');
    });

    test('bumps updatedAt on every write', () async {
      await repo.upsert('2026-07-28', body: 'first');
      final before = (await repo.watch('2026-07-28').first)!.updatedAt;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await repo.upsert('2026-07-28', mood: 3);
      final after = (await repo.watch('2026-07-28').first)!.updatedAt;
      expect(after.isAfter(before), isTrue);
    });
  });

  test('watchAll returns pages newest first', () async {
    await repo.upsert('2026-07-12', body: 'middle');
    await repo.upsert('2026-07-30', body: 'newest');
    await repo.upsert('2026-06-01', body: 'oldest');

    final all = await repo.watchAll().first;
    expect(all.map((e) => e.date).toList(),
        ['2026-07-30', '2026-07-12', '2026-06-01']);
  });

  group('JournalRepo.dayFacts', () {
    test('sums expenses, work focus, and notes for the day only', () async {
      final accountId = await db.into(db.accounts).insert(
            AccountsCompanion.insert(name: 'Cash', kind: AccountKind.cash),
          );
      final txns = TxnRepo(db);
      final day = DateTime(2026, 7, 30);

      // Two expenses on the day; income and other days must not count.
      await txns.addExpense(
        amountPaise: 20000,
        accountId: accountId,
        title: 'Chai',
        at: DateTime(2026, 7, 30, 9, 15),
      );
      await txns.addExpense(
        amountPaise: 14000,
        accountId: accountId,
        title: 'Auto',
        at: DateTime(2026, 7, 30, 18, 40),
      );
      await txns.addIncome(
        amountPaise: 500000,
        accountId: accountId,
        title: 'Freelance',
        at: DateTime(2026, 7, 30, 12),
      );
      await txns.addExpense(
        amountPaise: 9900,
        accountId: accountId,
        title: 'Yesterday lunch',
        at: DateTime(2026, 7, 29, 13),
      );

      // Focus: one completed work block counts; incomplete work and
      // completed rest do not.
      await db.into(db.focusSessions).insert(FocusSessionsCompanion.insert(
            startedAt: DateTime(2026, 7, 30, 8),
            minutes: 50,
            kind: FocusKind.work,
            completed: const Value(true),
          ));
      await db.into(db.focusSessions).insert(FocusSessionsCompanion.insert(
            startedAt: DateTime(2026, 7, 30, 10),
            minutes: 25,
            kind: FocusKind.work,
            completed: const Value(true),
          ));
      await db.into(db.focusSessions).insert(FocusSessionsCompanion.insert(
            startedAt: DateTime(2026, 7, 30, 11),
            minutes: 25,
            kind: FocusKind.work,
            completed: const Value(false),
          ));
      await db.into(db.focusSessions).insert(FocusSessionsCompanion.insert(
            startedAt: DateTime(2026, 7, 30, 12),
            minutes: 10,
            kind: FocusKind.rest,
            completed: const Value(true),
          ));

      // Notes: one live note counts; archived and other-day ones do not.
      await db.into(db.notes).insert(NotesCompanion.insert(
            title: const Value('groceries'),
            createdAt: Value(DateTime(2026, 7, 30, 14)),
          ));
      await db.into(db.notes).insert(NotesCompanion.insert(
            title: const Value('old draft'),
            createdAt: Value(DateTime(2026, 7, 30, 15)),
            archived: const Value(true),
          ));
      await db.into(db.notes).insert(NotesCompanion.insert(
            title: const Value('another day'),
            createdAt: Value(DateTime(2026, 7, 29, 15)),
          ));

      final f = await repo.dayFacts(day);
      expect(f.spentPaise, 34000);
      expect(f.txnCount, 2);
      expect(f.focusMinutes, 75);
      expect(f.notesCount, 1);
    });

    test('an untouched day reads all zero', () async {
      final f = await repo.dayFacts(DateTime(2026, 1, 1));
      expect(f.spentPaise, 0);
      expect(f.txnCount, 0);
      expect(f.focusMinutes, 0);
      expect(f.notesCount, 0);
    });
  });

  testWidgets('typing on today\'s page autosaves after the debounce',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(theme: ledgerDayTheme(), home: const JournalPage()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'A good day, mostly quiet.');
    await tester.pump(const Duration(seconds: 1));

    final key = LedgerDates.dayKey(DateTime.now());
    final saved = await (db.select(db.journalEntries)
          ..where((e) => e.date.equals(key)))
        .getSingleOrNull();
    expect(saved?.body, 'A good day, mostly quiet.');

    // Unmount and drain timers so the binding sees a clean end.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });
}
