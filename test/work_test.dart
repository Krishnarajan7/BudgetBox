import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/data/repos/work_repo.dart';
import 'package:budgetbox/features/work/work_math.dart';
import 'package:budgetbox/features/work/work_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Project _project({
  ProjectKind kind = ProjectKind.oneTime,
  int quote = 5000000,
  int? day,
  DateTime? started,
  ProjectStatus status = ProjectStatus.active,
}) => Project(
  id: 1,
  clientId: 1,
  name: 'Website',
  kind: kind,
  quotePaise: quote,
  billingDay: day,
  status: status,
  startedAt: started ?? DateTime(2026, 7, 3),
  createdAt: DateTime(2026, 7, 3),
);

ProjectLine _line(int id, LinkRole role, int paise, DateTime at, {bool billable = false}) =>
    ProjectLine(
      link: ProjectLink(
        id: id,
        projectId: 1,
        txnId: id,
        role: role,
        billable: billable,
        at: at,
      ),
      txn: Txn(
        id: id,
        amountPaise: paise,
        type: role == LinkRole.received ? TxnType.income : TxnType.expense,
        accountId: 1,
        title: 'line $id',
        at: at,
        createdAt: at,
      ),
    );

QuoteRevision _rev(int id, int paise, DateTime at, [String? reason]) =>
    QuoteRevision(id: id, projectId: 1, paise: paise, reason: reason, at: at);

void main() {
  final now = DateTime(2026, 9, 19, 10);

  group('a one-time project', () {
    test('the balance of the quote is what is owed, plus costs to pass on', () {
      final s = summarise(
        _project(),
        [_rev(1, 5000000, DateTime(2026, 7, 3), 'first quote')],
        [
          _line(1, LinkRole.received, 2000000, DateTime(2026, 7, 5)),
          _line(2, LinkRole.cost, 106000, DateTime(2026, 8, 17)),
          _line(3, LinkRole.cost, 360000, DateTime(2026, 8, 18), billable: true),
        ],
        now,
      );
      expect(s.receivedPaise, 2000000);
      expect(s.costPaise, 466000);
      expect(s.billableCostPaise, 360000);
      expect(s.owedPaise, 3000000 + 360000);
      expect(s.marginPaise, 2000000 - 466000);
      expect(s.fraction, closeTo(0.4, 0.001));
      expect(s.months, isEmpty);
    });

    test('a quote that moved is told from where it started', () {
      final s = summarise(
        _project(quote: 4000000),
        [
          _rev(1, 5000000, DateTime(2026, 7, 3), 'first quote'),
          _rev(2, 4000000, DateTime(2026, 9, 12), 'scope cut'),
        ],
        [_line(1, LinkRole.received, 4000000, DateTime(2026, 9, 15))],
        now,
      );
      expect(s.firstQuotePaise, 5000000);
      expect(s.quotePaise, 4000000);
      expect(s.owedPaise, 0);
      final lines = clientLines(s, now);
      expect(lines, contains('quote moved from ₹50,000 to ₹40,000'));
      expect(lines.any((l) => l.contains('still to come')), isFalse);
    });

    test('the client lines say the balance and the pass-ons plainly', () {
      final s = summarise(
        _project(),
        const [],
        [
          _line(1, LinkRole.received, 2000000, DateTime(2026, 7, 5)),
          _line(3, LinkRole.cost, 360000, DateTime(2026, 8, 18), billable: true),
        ],
        now,
      );
      final lines = clientLines(s, now);
      expect(lines.first, '₹30,000 of the ₹50,000 quote still to come');
      expect(lines.last, '₹3,600 of costs outside the quote to pass on');
    });

    test('settled in full says so', () {
      final s = summarise(
        _project(),
        const [],
        [_line(1, LinkRole.received, 5000000, DateTime(2026, 7, 5))],
        now,
      );
      expect(clientLines(s, now), ['settled in full, nothing to pass on']);
    });
  });

  group('a retainer', () {
    test('every month since it started is a row, paid or not', () {
      final s = summarise(
        _project(kind: ProjectKind.monthly, quote: 1000000, day: 5, started: DateTime(2026, 7, 10)),
        const [],
        [
          _line(1, LinkRole.received, 1000000, DateTime(2026, 7, 6)),
          _line(2, LinkRole.received, 1000000, DateTime(2026, 8, 4)),
        ],
        now,
      );
      expect(s.months.map((m) => m.month.month), [7, 8, 9]);
      expect(s.months.map((m) => m.paidPaise), [1000000, 1000000, 0]);
      // September's 5th has passed unpaid: one month owed.
      expect(s.owedPaise, 1000000);
      expect(s.fraction, closeTo(2 / 3, 0.001));
      expect(clientLines(s, now).first, 'September\'s retainer of ₹10,000 is unpaid');
    });

    test('a month whose day has not come is upcoming, not owed', () {
      final early = DateTime(2026, 9, 2);
      final s = summarise(
        _project(kind: ProjectKind.monthly, quote: 1000000, day: 5, started: DateTime(2026, 8, 1)),
        const [],
        [_line(1, LinkRole.received, 1000000, DateTime(2026, 8, 5))],
        early,
      );
      expect(s.owedPaise, 0);
      expect(retainersDue([s], early), isEmpty);
      expect(retainersDue([s], DateTime(2026, 9, 5, 10)).length, 1);
    });

    test('the billing day is clamped to the month', () {
      final p = _project(kind: ProjectKind.monthly, quote: 1000000, day: 31);
      expect(retainerDue(p, DateTime(2026, 9, 1)).day, 30);
      expect(retainerDue(p, DateTime(2026, 2, 1)).day, 28);
    });
  });

  group('the repo', () {
    late LedgerDb db;
    late WorkRepo repo;
    late int cash;

    setUp(() async {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      repo = WorkRepo(db, TxnRepo(db));
      cash = await AccountRepo(db).create(
        name: 'Cash',
        kind: AccountKind.cash,
        openingBalancePaise: 1000000,
      );
    });
    tearDown(() => db.close());

    test('a project opens with its first quote in the history, and a revision keeps both', () async {
      final client = await repo.createClient('Ghouthia');
      final id = await repo.createProject(
        clientId: client,
        name: 'Website',
        kind: ProjectKind.oneTime,
        quotePaise: 5000000,
      );
      await repo.reviseQuote(id, 4000000, reason: 'scope cut');
      final revs = await repo.watchRevisions(id).first;
      expect(revs.map((r) => r.paise), [5000000, 4000000]);
      expect(revs.last.reason, 'scope cut');
      final p = await repo.watchProject(id).first;
      expect(p!.quotePaise, 4000000);
    });

    test('receiving and spending write real ledger lines and claim them', () async {
      final client = await repo.createClient('Ghouthia');
      final id = await repo.createProject(
        clientId: client,
        name: 'Website',
        kind: ProjectKind.oneTime,
        quotePaise: 5000000,
      );
      await repo.receive(id, amountPaise: 2000000, accountId: cash, title: 'advance');
      await repo.spend(id, amountPaise: 106000, accountId: cash, title: 'domain', billable: true);
      final lines = await repo.watchLines(id).first;
      expect(lines.length, 2);
      expect(lines.where((l) => l.received).single.txn.amountPaise, 2000000);
      expect(lines.where((l) => l.cost).single.link.billable, isTrue);
      // The ledger moved the pocket like any other line.
      final account = (await db.select(db.accounts).get()).single;
      expect(account.balancePaise, 1000000 + 2000000 - 106000);
      // Unclaimed lines exclude the claimed ones.
      await TxnRepo(db).addExpense(amountPaise: 5000, accountId: cash, title: 'chai');
      final free = await repo.unclaimed(TxnType.expense);
      expect(free.map((t) => t.title), ['chai']);
      await repo.attach(id, free.single.id, role: LinkRole.cost);
      expect(await repo.unclaimed(TxnType.expense), isEmpty);
    });
  });

  group('the page', () {
    late LedgerDb db;

    Widget host() => ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(theme: ledgerDayTheme(), home: const WorkPage()),
    );

    Future<void> settleAndUnmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    setUp(() => db = LedgerDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    testWidgets('an empty book offers the first project', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('work-first')), findsOneWidget);
      await settleAndUnmount(tester);
    });

    testWidgets('a project shows what is owed and what to pass on', (tester) async {
      final repo = WorkRepo(db, TxnRepo(db));
      final cash = await AccountRepo(db).create(
        name: 'Cash',
        kind: AccountKind.cash,
        openingBalancePaise: 1000000,
      );
      final client = await repo.createClient('Ghouthia');
      final id = await repo.createProject(
        clientId: client,
        name: 'Website',
        kind: ProjectKind.oneTime,
        quotePaise: 5000000,
      );
      await repo.receive(id, amountPaise: 2000000, accountId: cash, title: 'advance');
      await repo.spend(id, amountPaise: 360000, accountId: cash, title: 'domain', billable: true);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('Website'), findsOneWidget);
      expect(find.textContaining('Ghouthia'), findsOneWidget);
      expect(find.textContaining('₹20,000 of ₹50,000 received'), findsOneWidget);
      expect(find.textContaining('₹3,600 to pass on'), findsOneWidget);
      // Owed: the ₹30,000 balance plus the pass-on — in the tile and on
      // the plate.
      expect(find.text('₹33,600'), findsAtLeastNWidgets(1));
      await settleAndUnmount(tester);
    });
  });
}
