import 'package:budgetbox/core/holidays.dart';
import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/core/widgets/motion.dart';
import 'package:budgetbox/core/widgets/pen_marks.dart';
import 'package:budgetbox/data/db.dart';
import 'package:drift/drift.dart' show Value;
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/event_repo.dart';
import 'package:budgetbox/data/repos/recurring_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/features/calendar/calendar_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Event _ev({
  int id = 1,
  String title = 'entry',
  required String date,
  int? timeMinutes,
  EventRepeat repeat = EventRepeat.none,
}) {
  return Event(
    id: id,
    title: title,
    date: date,
    timeMinutes: timeMinutes,
    repeat: repeat,
    createdAt: DateTime(2026, 1, 1),
    archived: false,
  );
}

Txn _txn({
  required int id,
  required DateTime at,
  required int paise,
  TxnType type = TxnType.expense,
}) {
  return Txn(
    id: id,
    amountPaise: paise,
    type: type,
    accountId: 1,
    toAccountId: type == TxnType.transfer ? 2 : null,
    title: 'line $id',
    at: at,
    createdAt: at,
  );
}

Recurring _bill({
  int id = 1,
  String title = 'Rent',
  int amountPaise = 1800000,
  int dayOfMonth = 5,
  int everyMonths = 1,
  RecurringKind kind = RecurringKind.bill,
}) {
  return Recurring(
    id: id,
    title: title,
    amountPaise: amountPaise,
    accountId: 1,
    kind: kind,
    everyMonths: everyMonths,
    dayOfMonth: dayOfMonth,
    nextDue: '2026-08-05',
    active: true,
  );
}

void main() {
  group('the money layer', () {
    test('a monthly charge lands once in every month of the window', () {
      final charges = chargesBetween(
        [_bill()],
        DateTime(2026, 8, 1),
        DateTime(2026, 11, 1),
      );
      expect(charges.map((c) => c.on), [
        DateTime(2026, 8, 5),
        DateTime(2026, 9, 5),
        DateTime(2026, 10, 5),
      ]);
      expect(charges.first.recurring.title, 'Rent');
    });

    test('a quarterly charge keeps its cadence, day clamped to the month', () {
      final charges = chargesBetween(
        [_bill(dayOfMonth: 31, everyMonths: 3)],
        DateTime(2026, 12, 1),
        DateTime(2027, 7, 1),
      );
      expect(charges.map((c) => c.on), [
        DateTime(2026, 12, 31),
        DateTime(2027, 3, 31),
        DateTime(2027, 6, 30),
      ]);
    });

    test('charges already past the window start are not dragged back', () {
      final charges = chargesBetween(
        [_bill()],
        DateTime(2026, 8, 20),
        DateTime(2026, 9, 30),
      );
      expect(charges.single.on, DateTime(2026, 9, 5));
    });

    test('day totals split what went out from what came in; transfers do '
        'neither', () {
      final money = moneyByDay([
        _txn(id: 1, at: DateTime(2026, 8, 1, 12), paise: 18000),
        _txn(id: 2, at: DateTime(2026, 8, 1, 20), paise: 2000),
        _txn(
          id: 3,
          at: DateTime(2026, 8, 1, 9),
          paise: 9200000,
          type: TxnType.income,
        ),
        _txn(
          id: 4,
          at: DateTime(2026, 8, 2, 9),
          paise: 500000,
          type: TxnType.transfer,
        ),
      ]);
      expect(money['2026-08-01'], (spent: 20000, earned: 9200000));
      expect(money['2026-08-02'], isNull);
    });
  });

  group('EventRepo', () {
    late LedgerDb db;
    late EventRepo repo;

    setUp(() {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      repo = EventRepo(db);
    });

    tearDown(() => db.close());

    test('create writes the entry as anchored, watchAll sees it', () async {
      final id = await repo.create(
        title: 'Chai with Amma',
        date: DateTime(2026, 8, 14),
        timeMinutes: 9 * 60 + 30,
        repeat: EventRepeat.yearly,
        note: 'bring jaggery',
      );

      final rows = await repo.watchAll().first;
      expect(rows, hasLength(1));
      final e = rows.single;
      expect(e.id, id);
      expect(e.title, 'Chai with Amma');
      expect(e.date, '2026-08-14');
      expect(e.timeMinutes, 570);
      expect(e.repeat, EventRepeat.yearly);
      expect(e.note, 'bring jaggery');
      expect(e.archived, isFalse);
    });

    test('all-day is the default: no time, no repeat', () async {
      await repo.create(title: 'Quiet day', date: DateTime(2026, 8, 1));
      final e = (await repo.watchAll().first).single;
      expect(e.timeMinutes, isNull);
      expect(e.repeat, EventRepeat.none);
    });

    test('an asked-for reminder survives, moves, and can be cleared',
        () async {
      final id = await repo.create(
        title: 'client meeting at Karaikal',
        date: DateTime(2026, 8, 19),
        timeMinutes: 10 * 60,
        remindMinutes: 8 * 60 + 30,
      );
      expect((await repo.watchAll().first).single.remindMinutes, 510);

      await repo.update(id, remindMinutes: const Value(9 * 60));
      expect((await repo.watchAll().first).single.remindMinutes, 540);

      // Value(null) clears; absent leaves alone.
      await repo.update(id, title: 'client meeting (moved)');
      expect((await repo.watchAll().first).single.remindMinutes, 540);
      await repo.update(id, remindMinutes: const Value(null));
      expect((await repo.watchAll().first).single.remindMinutes, isNull);
    });

    test('archive strikes the entry off the page', () async {
      final keep = await repo.create(title: 'keep', date: DateTime(2026, 8, 1));
      final gone = await repo.create(title: 'gone', date: DateTime(2026, 8, 2));

      await repo.archive(gone);

      final rows = await repo.watchAll().first;
      expect(rows.map((e) => e.id), [keep]);
    });
  });

  group('occurrencesInMonth', () {
    test('a yearly anchor from 2001 lands in august 2026', () {
      final birthday = _ev(
        date: '2001-08-14',
        repeat: EventRepeat.yearly,
        title: 'birthday',
      );
      final occ = EventRepo.occurrencesInMonth([birthday], DateTime(2026, 8));
      expect(occ, hasLength(1));
      expect(occ.single.on, DateTime(2026, 8, 14));
      expect(occ.single.event.title, 'birthday');
    });

    test('a none event outside the month stays off its pages', () {
      final e = _ev(date: '2026-07-20');
      expect(EventRepo.occurrencesInMonth([e], DateTime(2026, 8)), isEmpty);
      expect(
        EventRepo.occurrencesInMonth([e], DateTime(2026, 7)),
        hasLength(1),
      );
      expect(
        EventRepo.occurrencesInMonth([e], DateTime(2026, 7)).single.on,
        DateTime(2026, 7, 20),
      );
    });

    test('a none event does not repeat across years', () {
      final e = _ev(date: '2025-08-14');
      expect(EventRepo.occurrencesInMonth([e], DateTime(2026, 8)), isEmpty);
    });

    test('feb-29 anchor lands on feb-28 when the year is not leap', () {
      final leapling = _ev(date: '2000-02-29', repeat: EventRepeat.yearly);
      final nonLeap = EventRepo.occurrencesInMonth([
        leapling,
      ], DateTime(2027, 2));
      expect(nonLeap.single.on, DateTime(2027, 2, 28));

      final leap = EventRepo.occurrencesInMonth([leapling], DateTime(2028, 2));
      expect(leap.single.on, DateTime(2028, 2, 29));
    });
  });

  group('upcoming', () {
    test('respects the 60-day horizon', () {
      final near = _ev(id: 1, title: 'near', date: '2026-09-20');
      final far = _ev(id: 2, title: 'far', date: '2026-10-05');
      final up = EventRepo.upcoming([near, far], DateTime(2026, 7, 31));
      // 2026-09-20 is day 51; 2026-10-05 is day 66 — past the horizon.
      expect(up.map((o) => o.event.title), ['near']);
    });

    test('resolves yearly repeats across a year boundary', () {
      final newYear = _ev(
        id: 1,
        title: 'new year',
        date: '2000-01-05',
        repeat: EventRepeat.yearly,
      );
      final up = EventRepo.upcoming([newYear], DateTime(2026, 12, 20));
      expect(up, hasLength(1));
      expect(up.single.on, DateTime(2027, 1, 5));
    });

    test('caps the list at the limit, earliest first', () {
      final events = [
        for (var d = 1; d <= 7; d++)
          _ev(id: d, title: 'e$d', date: '2026-08-0$d'),
      ];
      final up = EventRepo.upcoming(events, DateTime(2026, 8, 1));
      expect(up, hasLength(5));
      expect(up.map((o) => o.event.title), ['e1', 'e2', 'e3', 'e4', 'e5']);
    });

    test('sorts by date, then time with all-day first', () {
      final evening = _ev(
        id: 1,
        title: 'evening',
        date: '2026-08-14',
        timeMinutes: 18 * 60,
      );
      final morning = _ev(
        id: 2,
        title: 'morning',
        date: '2026-08-14',
        timeMinutes: 60,
      );
      final allDay = _ev(id: 3, title: 'all day', date: '2026-08-14');
      final earlier = _ev(id: 4, title: 'earlier date', date: '2026-08-13');

      final up = EventRepo.upcoming([
        evening,
        morning,
        allDay,
        earlier,
      ], DateTime(2026, 8, 10));
      expect(up.map((o) => o.event.title), [
        'earlier date',
        'all day',
        'morning',
        'evening',
      ]);
    });
  });

  group('CalendarPage', () {
    testWidgets('the month is the window — next month stays next month',
        (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      final repo = EventRepo(db);
      final now = DateTime.now();
      final monthEnd = DateTime(now.year, now.month + 1);
      // One plan later this month, one a fortnight into the next.
      final thisMonth = now.day < 28
          ? DateTime(now.year, now.month, now.day + 1)
          : DateTime(now.year, now.month, now.day);
      await repo.create(title: 'Dentist, this month', date: thisMonth);
      await repo.create(
        title: 'Dentist, next month',
        date: DateTime(monthEnd.year, monthEnd.month, 14),
      );

      await _pumpCalendar(tester, db);

      expect(find.text('Dentist, this month'), findsOneWidget);
      expect(
        find.text('Dentist, next month'),
        findsNothing,
        reason: 'a 60-day horizon used to drag next month onto this page',
      );
      // The month says its own name, and where the list ends.
      expect(find.text('${_months[now.month - 1]} ${now.year}'), findsOneWidget);
      expect(
        find.textContaining('that is all of ${_months[now.month - 1]}'),
        findsOneWidget,
      );

      await _drain(tester, db);
    });


    testWidgets('the agenda names the day the country names', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      final book = await HolidayBook.load();
      // Whatever the next named day happens to be from wherever "now" lands
      // — Independence Day, Deepavali, Pongal — the agenda has to say it,
      // with no plan of his own on that date to carry it.
      final next = book.next(DateTime.now(), within: days60);

      await _pumpCalendar(tester, db);

      if (next == null) {
        await _drain(tester, db);
        return;
      }
      expect(find.textContaining(next.holiday.name), findsWidgets);
      expect(find.textContaining(next.holiday.phrase), findsWidgets);

      await _drain(tester, db);
    });

    testWidgets('renders the month and shows the written day', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      final repo = EventRepo(db);
      final now = DateTime.now();
      await repo.create(
        title: 'Chai with Amma',
        date: DateTime(now.year, now.month, now.day),
        timeMinutes: 9 * 60 + 30,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const CalendarPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The agenda spine shows the month sideways, to-day's number sits on
      // its paper chip, and the entry rides beside it with its hour.
      const months = [
        'january',
        'february',
        'march',
        'april',
        'may',
        'june',
        'july',
        'august',
        'september',
        'october',
        'november',
        'december',
      ];
      expect(find.text('${months[now.month - 1]} ${now.year}'), findsOneWidget);
      expect(find.text('${now.day}'), findsWidgets);
      expect(find.text('Chai with Amma'), findsOneWidget);
      expect(find.text('09:30'), findsOneWidget);

      // Drain drift's stream machinery so the binding sees no leaked timers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await db.close();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('swiping the week strip carries the agenda a week on', (
      tester,
    ) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      await _pumpCalendar(tester, db);

      final now = DateTime.now();
      final next = DateTime(now.year, now.month, now.day + 7);
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('${next.day} ${_months[next.month - 1]}'),
        findsOneWidget,
      );
      await _drain(tester, db);
    });

    testWidgets('flipping a month there and back mid-fade never crashes', (
      tester,
    ) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      await _pumpCalendar(tester, db);

      // Forward a month, then straight back while the spine caption and
      // the page are still animating: a day-keyed switcher would find the
      // same key twice in one stack and throw the duplicate-key assertion.
      final forward = find.byWidgetPredicate(
        (w) => w is RotatedBox && w.quarterTurns == 0 && w.child is PenChevron,
      );
      final back = find.byWidgetPredicate(
        (w) => w is RotatedBox && w.quarterTurns == 2 && w.child is PenChevron,
      );
      await tester.tap(forward);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(back);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(forward);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await _drain(tester, db);
    });

    testWidgets('the grid names its month, flips to the next, and peeks', (
      tester,
    ) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      await _pumpCalendar(tester, db);
      final now = DateTime.now();

      await tester.tap(find.byIcon(Icons.grid_on));
      await tester.pumpAndSettle();
      expect(
        find.text('${_months[now.month - 1]} ${now.year}'),
        findsOneWidget,
      );

      // A drag across the grid turns to the next month.
      await tester.fling(
        find.byType(SingleChildScrollView),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();
      final ahead = DateTime(now.year, now.month + 1);
      expect(
        find.text('${_months[ahead.month - 1]} ${ahead.year}'),
        findsOneWidget,
      );

      // A long press peeks at a day without leaving the month.
      await tester.longPress(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.text('15'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('write something here'), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await _drain(tester, db);
    });

    testWidgets('a bill due shares the page with the plans', (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final cash = await AccountRepo(db).create(
        name: 'Cash',
        kind: AccountKind.cash,
        openingBalancePaise: 5000000,
      );
      await RecurringRepo(db, TxnRepo(db)).create(
        title: 'Rent',
        amountPaise: 1800000,
        accountId: cash,
        dayOfMonth: tomorrow.day,
        kind: RecurringKind.bill,
      );
      await TxnRepo(db).addExpense(
        amountPaise: 18000,
        accountId: cash,
        title: 'Saravana Bhavan',
        at: DateTime(now.year, now.month, now.day, 12),
      );

      await _pumpCalendar(tester, db);

      // The bill lands on every due day inside the horizon, in mono;
      // to-day's page carries what the ledger already spent.
      expect(find.textContaining('Rent'), findsWidgets);
      expect(find.text('₹18,000'), findsWidgets);
      expect(find.text('₹180 out'), findsOneWidget);
      await _drain(tester, db);
    });

    testWidgets('the composer asks whether to remind, and keeps the answer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = LedgerDb.forTesting(NativeDatabase.memory());

      await _pumpCalendar(tester, db);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('should I remind you?'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        'client meeting at Karaikal',
      );
      // Give the plan its hour, then ask for the nudge: it offers an
      // hour's grace before the meeting by default.
      await tester.tap(find.text('pick a time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('remind me'));
      await tester.pumpAndSettle();
      expect(find.text('remind at 08:00'), findsOneWidget);
      expect(
        find.textContaining('heads-up the evening before'),
        findsOneWidget,
      );

      await tester.tap(find.text('Put it on the page'));
      await tester.pumpAndSettle();

      final e = (await db.select(db.events).get()).single;
      expect(e.title, 'client meeting at Karaikal');
      expect(e.timeMinutes, 9 * 60);
      expect(e.remindMinutes, 8 * 60);

      await _drain(tester, db);
    });

    testWidgets('the composer writes a monthly charge, not just plans', (
      tester,
    ) async {
      // A tall surface so the sheet's button stays hittable over the
      // test keyboard.
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = LedgerDb.forTesting(NativeDatabase.memory());
      await AccountRepo(db).create(
        name: 'Cash',
        kind: AccountKind.cash,
        openingBalancePaise: 100000,
      );

      await _pumpCalendar(tester, db);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      // Drift's account stream needs a beat before the sheet knows a
      // pocket exists — same courtesy _pumpCalendar extends.
      await tester.pump(const Duration(milliseconds: 400));

      // Flip the composer from plan to charge and fill the line.
      await tester.tap(find.text('a monthly charge'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'what charges? Netflix, rent…'),
        'Netflix',
      );
      await tester.enterText(find.widgetWithText(TextField, '0'), '649');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('subscription'));
      await tester.tap(find.text('subscription'));
      // The modal's hit-testing under the test binding is not what this
      // test guards; the save wiring is. Press the button by its handler.
      final save = tester.widget<Pressable>(
        find
            .ancestor(
              of: find.text('Add the charge'),
              matching: find.byType(Pressable),
            )
            .first,
      );
      save.onTap!();
      // Drift resolves the pocket on a timer; settle alone never fires it.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      final rows = await db.select(db.recurrings).get();
      expect(rows.length, 1);
      expect(rows.single.title, 'Netflix');
      expect(rows.single.amountPaise, 64900);
      expect(rows.single.kind, RecurringKind.subscription);
      expect(rows.single.dayOfMonth, DateTime.now().day);
      await _drain(tester, db);
    });
  });
}

const _months = [
  'january', 'february', 'march', 'april', 'may', 'june', //
  'july', 'august', 'september', 'october', 'november', 'december',
];

/// The agenda's horizon, in the argument shape `next` wants.
const days60 = 60;

Future<void> _pumpCalendar(WidgetTester tester, LedgerDb db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(theme: ledgerDayTheme(), home: const CalendarPage()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Drain drift's stream machinery so the binding sees no leaked timers.
Future<void> _drain(WidgetTester tester, LedgerDb db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await db.close();
  await tester.pump(const Duration(seconds: 1));
}
