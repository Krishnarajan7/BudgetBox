import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/alarm_repo.dart';
import 'package:budgetbox/features/alarm/alarm_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LedgerDb db;

  setUp(() => db = LedgerDb.forTesting(NativeDatabase.memory()));

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(theme: ledgerNightTheme(), home: const AlarmPage()),
      ),
    );
    // Drift hands over its first rows on a timer. Never pumpAndSettle on
    // this page: the countdown under the hero ticks forever by design, so
    // "settled" is a state it is never going to reach.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await db.close();
  }

  testWidgets('an empty page asks for the one alarm you actually need',
      (tester) async {
    await pump(tester);

    expect(find.text('Nothing is set to wake you.'), findsOneWidget);
    expect(find.text('set an alarm'), findsOneWidget);

    await settle(tester);
  });

  testWidgets('the next ring leads, and every alarm reads as a timetable',
      (tester) async {
    // Writing an alarm also asks the operating system to ring it, and a
    // platform channel needs a real event loop — fake time never answers.
    await tester.runAsync(() async {
      final repo = AlarmRepo(db);
      await repo.create(minuteOfDay: 6 * 60 + 30, label: 'gym', days: 0x7F);
      await repo.create(minuteOfDay: 21 * 60, label: 'wind down');
    });

    await pump(tester);

    expect(find.text('next alarm'), findsOneWidget);
    // Both rows are on the page, each in its own hour.
    // Whichever of the two is next also stands in the hero, so both times
    // can legitimately appear twice depending on the hour this test runs.
    expect(find.text('06:30'), findsWidgets);
    expect(find.text('21:00'), findsWidgets);
    expect(find.textContaining('gym'), findsWidgets);
    expect(find.textContaining('every day'), findsOneWidget);
    expect(find.textContaining('once'), findsOneWidget);

    await settle(tester);
  });

  testWidgets('a switched-off alarm stays on the page, greyed', (tester) async {
    await tester.runAsync(() async {
      final repo = AlarmRepo(db);
      final id = await repo.create(minuteOfDay: 6 * 60, label: 'gym');
      await repo.update(id, enabled: false);
    });

    await pump(tester);

    expect(find.text('06:00'), findsOneWidget);
    expect(find.text('none set to ring'), findsOneWidget);
    expect(find.text('every alarm below is switched off'), findsOneWidget);

    await settle(tester);
  });

  testWidgets('the plus opens the wheels, already on a sensible hour',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('set an alarm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('A new alarm'), findsOneWidget);
    expect(find.text('Set it'), findsOneWidget);
    // 06:30 by default, and no days chosen means it rings once.
    expect(
      find.textContaining('rings once, then switches itself off'),
      findsOneWidget,
    );

    await settle(tester);
  });
}
