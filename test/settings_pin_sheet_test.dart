import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/features/settings/settings_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Setting a PIN opens a sheet holding an autofocused TextField. The sheet's
/// future resolves the moment the route is popped — the reverse transition is
/// still playing and the field is still building against its controller.
/// Anything that frees the controller on that boundary tears the field down
/// mid-frame.
void main() {
  Future<void> openSettings(WidgetTester tester, LedgerDb db) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(theme: ledgerDayTheme(), home: const SettingsPage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('closing the PIN sheet with a saved PIN does not tear down',
      (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await openSettings(tester, db);

    await tester.scrollUntilVisible(find.text('PIN'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Six digits. Only your book, only you.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '432156');
    await tester.pump();

    await tester.tap(find.text('Lock it down'));
    // Pump *through* the sheet's 280ms exit rather than settling past it:
    // the failure lives inside that window.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await SettingsRepo(db).hasPin(), isTrue);
  });

  testWidgets('dismissing the PIN sheet without saving does not tear down',
      (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await openSettings(tester, db);

    await tester.scrollUntilVisible(find.text('PIN'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('PIN'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '12');
    await tester.pump();

    // Drag the sheet away, the way a thumb dismisses it.
    await tester.drag(find.byType(TextField), const Offset(0, 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await SettingsRepo(db).hasPin(), isFalse);
  });

  testWidgets('removing an existing PIN does not tear down', (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await SettingsRepo(db).setPin('1234');
    await openSettings(tester, db);

    await tester.scrollUntilVisible(find.text('PIN'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('PIN'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove the PIN instead'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await SettingsRepo(db).hasPin(), isFalse);
  });
}
