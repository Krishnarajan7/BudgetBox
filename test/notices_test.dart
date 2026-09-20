import 'package:budgetbox/core/notifications.dart';
import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/notice_repo.dart';
import 'package:budgetbox/features/kural/kural_page.dart';
import 'package:budgetbox/features/notices/notices_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every book's voice in one ledger — and the kural's day, which turns at
/// six in the morning rather than at midnight.
void main() {
  group('the kural day', () {
    test('turns at six in the morning, not at midnight', () {
      expect(kuralDay(DateTime(2026, 9, 20, 0, 30)), DateTime(2026, 9, 19));
      expect(kuralDay(DateTime(2026, 9, 20, 5, 59)), DateTime(2026, 9, 19));
      expect(kuralDay(DateTime(2026, 9, 20, 6, 0)), DateTime(2026, 9, 20));
      expect(kuralDay(DateTime(2026, 9, 20, 23, 30)), DateTime(2026, 9, 20));
    });

    test('rolls across a month and a year the same way', () {
      expect(kuralDay(DateTime(2026, 10, 1, 2)), DateTime(2026, 9, 30));
      expect(kuralDay(DateTime(2027, 1, 1, 3)), DateTime(2026, 12, 31));
    });
  });

  group('which book spoke', () {
    test('every lane of the id ledger names its book', () {
      expect(LedgerReminders.moduleFor(1), 'money'); // tonight
      expect(LedgerReminders.moduleFor(3), 'money'); // salary
      expect(LedgerReminders.moduleFor(25), 'money'); // standing evening
      expect(LedgerReminders.moduleFor(4), 'focus');
      expect(LedgerReminders.moduleFor(5), 'sky');
      expect(LedgerReminders.moduleFor(6), 'felt');
      expect(LedgerReminders.moduleFor(47), 'felt');
      expect(LedgerReminders.moduleFor(61), 'diet');
      expect(LedgerReminders.moduleFor(130), 'diet');
      expect(LedgerReminders.moduleFor(1042), 'calendar');
      expect(LedgerReminders.moduleFor(2007), 'money'); // a due
      expect(LedgerReminders.moduleFor(3009), 'alarm');
      expect(LedgerReminders.moduleFor(4003), 'work');
      expect(LedgerReminders.moduleFor(500012), 'calendar'); // an eve
      expect(
        LedgerReminders.moduleFor(500012, payload: 'alarm|12|9|gym'),
        'alarm', // a snooze in the shared lane
      );
      expect(LedgerReminders.moduleFor(1000042), 'notes');
    });
  });

  group('the ledger', () {
    late LedgerDb db;
    late NoticeRepo repo;

    setUp(() {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      repo = NoticeRepo(db);
    });
    tearDown(() => db.close());

    Future<void> lay(
      int id,
      String title,
      DateTime at, {
      String module = 'diet',
    }) =>
        repo.scheduled(id: id, module: module, title: title, body: '', at: at);

    test(
      're-saying a line replaces the unsaid copy, never stacks it',
      () async {
        final tonight = DateTime.now().add(const Duration(hours: 2));
        await lay(1, 'three lines to-day', tonight, module: 'money');
        await lay(1, 'four lines to-day', tonight, module: 'money');
        final rows = await repo.watch().first;
        expect(rows.length, 1);
        expect(rows.single.title, 'four lines to-day');
      },
    );

    test('a line already said stays when the same id is laid again', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await lay(61, 'lunch?', yesterday);
      await lay(61, 'lunch?', tomorrow);
      final rows = await repo.watch().first;
      expect(rows.length, 2);
    });

    test('cancelling strikes the future copy and keeps the record', () async {
      final past = DateTime.now().subtract(const Duration(hours: 3));
      final future = DateTime.now().add(const Duration(hours: 3));
      await lay(5, 'rain at four', past, module: 'sky');
      await lay(5, 'rain at nine', future, module: 'sky');
      await repo.cancelled(5);
      final rows = await repo.watch().first;
      expect(rows.map((n) => n.title), ['rain at four']);
    });

    test('a tap is remembered on the line that was said', () async {
      final past = DateTime.now().subtract(const Duration(minutes: 30));
      await lay(62, 'dinner?', past);
      await repo.opened(62);
      final rows = await repo.watch().first;
      expect(rows.single.openedAt, isNotNull);
    });

    test('the phone settles each past line: said, shown, or stuck', () async {
      final now = DateTime.now();
      final past = now.subtract(const Duration(hours: 2));
      await lay(61, 'lunch?', past); // gone from the phone: said
      await lay(62, 'dinner?', past); // sitting in the tray: shown
      await lay(5, 'rain', past, module: 'sky'); // still pending: stuck
      // Tonight's line was re-laid for to-morrow: its past copy was said,
      // and the pending id belongs to the new copy, not the old.
      await lay(1, 'last night', past, module: 'money');
      await lay(
        1,
        'to-night',
        now.add(const Duration(hours: 20)),
        module: 'money',
      );
      await repo.reconcile(pending: {5, 1}, active: {62});
      final rows = {for (final n in await repo.watch().first) n.title: n.fate};
      expect(rows['lunch?'], 'said');
      expect(rows['dinner?'], 'shown');
      expect(rows['rain'], 'stuck');
      expect(rows['last night'], 'said');
      expect(rows['to-night'], isNull);
    });

    test(
      'shown stays shown after the tray is cleared; stuck can be said later',
      () async {
        final past = DateTime.now().subtract(const Duration(hours: 2));
        await lay(62, 'dinner?', past);
        await lay(5, 'rain', past, module: 'sky');
        await repo.reconcile(pending: {5}, active: {62});
        await repo.reconcile(pending: {}, active: {});
        final rows = {
          for (final n in await repo.watch().first) n.title: n.fate,
        };
        expect(rows['dinner?'], 'shown');
        expect(rows['rain'], 'said');
      },
    );

    test('old rows are pruned, the recent month is not', () async {
      await lay(1, 'old', DateTime.now().subtract(const Duration(days: 70)));
      await lay(2, 'recent', DateTime.now().subtract(const Duration(days: 5)));
      expect(await repo.prune(), 1);
      expect(await db.select(db.notices).get(), hasLength(1));
    });
  });

  group('the page', () {
    late LedgerDb db;

    Widget host() => ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(theme: ledgerDayTheme(), home: const NoticesPage()),
    );

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    setUp(() => db = LedgerDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    testWidgets('an empty ledger says nothing was said', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('Nothing said yet.'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets(
      'lines from every book sit under their day, the next one on top',
      (tester) async {
        final repo = NoticeRepo(db);
        final now = DateTime.now();
        await repo.scheduled(
          id: 61,
          module: 'diet',
          title: 'lunch went unwritten',
          body: 'a plate, or a skip — either is fine.',
          at: now.subtract(const Duration(hours: 2)),
        );
        await repo.scheduled(
          id: 5,
          module: 'sky',
          title: 'rain by six',
          body: 'the ride home gets wet.',
          at: now.subtract(const Duration(days: 1)),
        );
        await repo.scheduled(
          id: 1,
          module: 'money',
          title: 'three lines to-day',
          body: 'the evening line.',
          at: now.add(const Duration(hours: 1)),
        );
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();

        expect(find.text('COMING UP'), findsOneWidget);
        expect(find.text('three lines to-day'), findsOneWidget);
        expect(find.text('TO-DAY'), findsOneWidget);
        expect(find.text('lunch went unwritten'), findsOneWidget);
        expect(find.text('YESTERDAY'), findsOneWidget);
        expect(find.text('rain by six'), findsOneWidget);

        // What the phone said became of them shows under each line.
        await repo.reconcile(pending: {5}, active: {61});
        await tester.pumpAndSettle();
        expect(find.text('diet · shown'), findsOneWidget);
        expect(find.text('sky · still waiting'), findsOneWidget);
        expect(find.textContaining('past its hour and still'), findsOneWidget);

        // Narrow to one book: the others leave the page.
        await tester.tap(find.byKey(const ValueKey('notice-chip-sky')));
        await tester.pumpAndSettle();
        expect(find.text('rain by six'), findsOneWidget);
        expect(find.text('lunch went unwritten'), findsNothing);
        expect(find.text('three lines to-day'), findsNothing);
        await unmount(tester);
      },
    );
  });
}
