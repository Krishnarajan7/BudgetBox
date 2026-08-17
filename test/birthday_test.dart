import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/features/birthday/birthday_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the gate', () {
    test('opens only on 18 august, once a year', () {
      expect(birthdaySurpriseDue(DateTime(2026, 8, 18, 7), null), isTrue);
      expect(birthdaySurpriseDue(DateTime(2026, 8, 18, 23, 59), null), isTrue);
      // Any other day of the year: silence.
      expect(birthdaySurpriseDue(DateTime(2026, 8, 17), null), isFalse);
      expect(birthdaySurpriseDue(DateTime(2026, 8, 19), null), isFalse);
      expect(birthdaySurpriseDue(DateTime(2026, 9, 18), null), isFalse);
      expect(birthdaySurpriseDue(DateTime(2026, 1, 18), null), isFalse);
      // Shown this year: done until the next one.
      expect(birthdaySurpriseDue(DateTime(2026, 8, 18), '2026'), isFalse);
      expect(birthdaySurpriseDue(DateTime(2027, 8, 18), '2026'), isTrue);
    });
  });

  group('the facts', () {
    late LedgerDb db;

    setUp(() => db = LedgerDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('an empty book yields zeros, never an error', () async {
      final facts = await gatherBirthdayFacts(db, name: 'Krish');
      expect(facts.hasAnything, isFalse);
      expect(facts.daysOfBook, 0);
      expect(facts.entries, 0);
    });

    test('a lived-in book is read back correctly', () async {
      final now = DateTime(2026, 8, 18, 7);
      final accounts = await db.select(db.accounts).get();
      final account = accounts.isEmpty
          ? await db
                .into(db.accounts)
                .insert(
                  AccountsCompanion.insert(name: 'HDFC', kind: AccountKind.bank),
                )
          : accounts.first.id;
      for (var i = 0; i < 3; i++) {
        await db
            .into(db.txns)
            .insert(
              TxnsCompanion.insert(
                amountPaise: 500,
                type: TxnType.expense,
                accountId: account,
                title: 'Chai $i',
                at: now.subtract(Duration(days: 9 - i)),
              ),
            );
      }
      await db
          .into(db.daySeals)
          .insert(DaySealsCompanion.insert(date: '2026-08-17'));
      for (var i = 0; i < 5; i++) {
        await db
            .into(db.dayMarks)
            .insert(DayMarksCompanion.insert(date: '2026-08-17', kind: 'water'));
      }
      await db
          .into(db.focusSessions)
          .insert(
            FocusSessionsCompanion.insert(
              startedAt: now.subtract(const Duration(days: 1)),
              minutes: 25,
              kind: FocusKind.work,
              completed: const Value(true),
            ),
          );
      await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              date: '2026-08-17',
              body: const Value('a day'),
            ),
          );

      final facts = await gatherBirthdayFacts(db, name: 'Krish', now: now);
      expect(facts.hasAnything, isTrue);
      expect(facts.daysOfBook, 10, reason: 'first entry nine days ago');
      expect(facts.entries, 3);
      expect(facts.daysClosed, 1);
      expect(facts.glasses, 5);
      expect(facts.focusMinutes, 25);
      expect(facts.journalPages, 1);
    });
  });

  group('the ceremony', () {
    testWidgets('walks all five scenes and hands the day back',
        (tester) async {
      const facts = BirthdayFacts(
        name: 'Krish',
        daysOfBook: 200,
        entries: 412,
        daysClosed: 61,
        glasses: 380,
        focusMinutes: 900,
        journalPages: 44,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ledgerDayTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BirthdayPage(facts: facts),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      // Every scene staggers its lines on real timers, so each stop pumps
      // past the longest delay before reading the page.
      Future<void> settleScene() async {
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('open'));
      await settleScene();

      // Scene one: the date, recognised.
      expect(find.text('18 august.'), findsOneWidget);
      expect(find.text('I know this date.'), findsOneWidget);

      Future<void> turn() async {
        await tester.tapAt(const Offset(200, 200));
        await settleScene();
      }

      // Scene two: the seal that opens a day.
      await turn();
      expect(find.text('this one opens one.'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);

      // Scene three: the year read back, every non-zero fact on a line.
      await turn();
      expect(find.textContaining('day 200 of this book'), findsOneWidget);
      expect(find.text('412'), findsOneWidget);
      expect(find.text('entries, written by hand'), findsOneWidget);
      expect(find.text('days closed with the seal'), findsOneWidget);
      expect(find.text('glasses of water'), findsOneWidget);
      expect(find.text('minutes of held focus'), findsOneWidget);
      expect(find.text('pages of the journal'), findsOneWidget);

      // Scene four: the gift. The Lottie may or may not decode in a test —
      // the words beside it are the scene's spine either way.
      await turn();
      expect(
        find.text('so I kept it. all of it. turn the page.'),
        findsOneWidget,
      );

      // Scene five: the wish, signed, with the one door out.
      await turn();
      expect(find.text('happy birthday, krish.'), findsOneWidget);
      expect(
        find.text('— your book. and the brother inside it.'),
        findsOneWidget,
      );
      await tester.tap(find.text('keep the day'));
      await settleScene();
      expect(find.text('open'), findsOneWidget, reason: 'the page hands back');
    });

    testWidgets('a young book still gets a whole ceremony', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ledgerDayTheme(),
          home: const BirthdayPage(facts: BirthdayFacts()),
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      // No facts to count: the line about the year ahead stands in.
      expect(
        find.textContaining('the year ahead is ours'),
        findsOneWidget,
      );

      // Leave mid-ceremony on purpose — the page must fold away clean.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
