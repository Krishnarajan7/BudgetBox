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

  test('the clock reads the way a person says it', () {
    expect(clock12(6 * 60 + 30), ('6:30', 'AM'));
    expect(clock12(0), ('12:00', 'AM'));
    expect(clock12(12 * 60), ('12:00', 'PM'));
    expect(clock12(21 * 60 + 5), ('9:05', 'PM'));
  });

  testWidgets('an empty page asks for the one alarm you actually need', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Nothing is set to wake you.'), findsOneWidget);
    expect(find.text('set an alarm'), findsOneWidget);
    // The big round add is there too.
    expect(find.byKey(const ValueKey('alarm-add')), findsOneWidget);

    await settle(tester);
  });

  testWidgets('the next wakeup leads, and every alarm is its own plate', (
    tester,
  ) async {
    // Writing an alarm also asks the operating system to ring it, and a
    // platform channel needs a real event loop — fake time never answers.
    await tester.runAsync(() async {
      final repo = AlarmRepo(db);
      await repo.create(minuteOfDay: 6 * 60 + 30, label: 'gym', days: 0x7F);
      await repo.create(minuteOfDay: 21 * 60, label: 'wind down');
    });

    await pump(tester);

    expect(find.text('next wakeup'), findsOneWidget);
    expect(find.text('all alarms'), findsOneWidget);
    // Both rows are on the page, each in its own hour. Whichever of the
    // two is next also stands in the hero, so either time can appear twice.
    expect(find.text('6:30'), findsWidgets);
    expect(find.text('9:00'), findsWidgets);
    expect(find.textContaining('gym'), findsWidgets);
    expect(find.textContaining('every day'), findsOneWidget);
    expect(find.textContaining('once'), findsOneWidget);
    // Two switches, both on.
    expect(find.byKey(const ValueKey('alarm-switch-true')), findsNWidgets(2));

    await settle(tester);
  });

  testWidgets('a switched-off alarm stays on the page, greyed', (tester) async {
    await tester.runAsync(() async {
      final repo = AlarmRepo(db);
      final id = await repo.create(minuteOfDay: 6 * 60, label: 'gym');
      await repo.update(id, enabled: false);
    });

    await pump(tester);

    expect(find.text('6:00'), findsOneWidget);
    expect(find.text('none set to ring'), findsOneWidget);
    expect(find.text('every alarm below is switched off'), findsOneWidget);
    expect(find.byKey(const ValueKey('alarm-switch-false')), findsOneWidget);

    await settle(tester);
  });

  testWidgets('the plus opens the dial, already on a sensible hour', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('set an alarm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('A new alarm'), findsOneWidget);
    expect(find.text('Set it'), findsOneWidget);
    expect(find.byKey(const ValueKey('dial-hours')), findsOneWidget);
    expect(find.byKey(const ValueKey('dial-minutes')), findsOneWidget);
    // 06:30 by default, and no days chosen means it rings once.
    expect(find.text('06'), findsWidgets);
    expect(find.text('30'), findsWidgets);
    expect(find.text('AM'), findsOneWidget);
    expect(
      find.textContaining('rings once, then switches itself off'),
      findsOneWidget,
    );

    // Tapping the meridiem flips it.
    await tester.tap(find.byKey(const ValueKey('dial-ampm')));
    await tester.pump();
    expect(find.text('PM'), findsOneWidget);

    await settle(tester);
  });
}
