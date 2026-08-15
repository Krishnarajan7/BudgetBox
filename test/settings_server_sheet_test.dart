import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/features/settings/settings_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server sheet, opened with the semantics tree live — which is what a
/// debug build on a device does, and what a screen reader would do.
void main() {
  Future<void> openSettings(WidgetTester tester, LedgerDb db) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(theme: ledgerDayTheme(), home: const SettingsPage()),
    ));
    await tester.pumpAndSettle();
  }

  /// The server row sits near the foot of a long page.
  Future<void> tapServer(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Server'), 220,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Server'));
    await tester.pumpAndSettle();
    // The row opens the server's own page; the sheet is its address door.
    await tester.tap(find.text('change the address or token'));
    await tester.pumpAndSettle();
  }

  testWidgets('opening the server sheet builds a sound semantics tree',
      (tester) async {
    final handle = tester.ensureSemantics();
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await openSettings(tester, db);

    await tapServer(tester);

    expect(find.text('The other half of the book.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('typing and closing the server sheet stays sound',
      (tester) async {
    final handle = tester.ensureSemantics();
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await openSettings(tester, db);

    await tapServer(tester);

    await tester.enterText(
        find.byType(TextField).first, 'https://bbx.example.in');
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'bbx_abc');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final cfg = await SettingsRepo(db).serverConfig();
    expect(cfg.baseUrl, 'https://bbx.example.in');
    expect(cfg.token, 'bbx_abc');
    handle.dispose();
  });

  testWidgets('a wired book can stop syncing from the sheet', (tester) async {
    final handle = tester.ensureSemantics();
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await SettingsRepo(db).setServer('https://bbx.example.in', 'bbx_abc');
    await openSettings(tester, db);

    await tapServer(tester);
    await tester.tap(find.text('Stop syncing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect((await SettingsRepo(db).serverConfig()).wired, isFalse);
    handle.dispose();
  });
}
