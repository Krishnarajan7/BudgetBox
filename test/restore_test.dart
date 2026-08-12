import 'dart:convert';

import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/features/setup/restore_page.dart';
import 'package:budgetbox/features/setup/setup_flow.dart';
import 'package:budgetbox/data/api/api_config.dart';
import 'package:budgetbox/data/sync/sync_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Reinstalling used to mean walking the ritual again and hoping the account
/// names matched. These cover the other door.
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the ritual offers the door on a real first launch',
      (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ledgerDayTheme(),
        home: const SetupFlow(real: true),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('I already have a book'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('the preview from Settings does not offer it', (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(theme: ledgerDayTheme(), home: const SetupFlow()),
    ));
    await tester.pumpAndSettle();

    // A harmless preview must never re-point a live book at another server.
    expect(find.text('I already have a book'), findsNothing);
    await drain(tester);
  });

  testWidgets('the door opens onto the restore page', (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ledgerDayTheme(),
        home: const SetupFlow(real: true),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('I already have a book'));
    await tester.pumpAndSettle();

    expect(find.text('Where does it live?'), findsOneWidget);
    expect(find.text('Bring it back'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('an address with no token is refused before anything is saved',
      (tester) async {
    final handle = tester.ensureSemantics();
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(theme: ledgerDayTheme(), home: const RestorePage()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField).first, 'https://bbx.example.in');
    await tester.pump();
    await tester.tap(find.text('Bring it back'));
    await tester.pumpAndSettle();

    expect(find.textContaining('both the address and the token'),
        findsOneWidget);
    expect((await SettingsRepo(db).serverConfig()).wired, isFalse,
        reason: 'nothing should be written until the door is proven');
    expect(tester.takeException(), isNull);
    handle.dispose();
    await drain(tester);
  });

  test('a blank phone pulls a whole book down from the server', () async {
    // The restore path end to end, minus the widgets: a fresh database, a
    // server that holds a book, one sync.
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await db.select(db.txns).get(), isEmpty);
    expect(await db.select(db.accounts).get(), isEmpty);

    final engine = _restoringEngine(db);
    addTearDown(engine.dispose);
    await engine.syncNow();

    final accounts = await db.select(db.accounts).get();
    final txns = await db.select(db.txns).get();
    expect(accounts.map((a) => a.name), contains('HDFC salary'));
    expect(txns.map((t) => t.title), contains('chai'));

    // And the preferences came with it.
    final settings = SettingsRepo(db);
    expect(await settings.name(), 'Krish');
    expect(await settings.salaryDay(), 7);
    // But not the lock.
    expect(await settings.hasPin(), isFalse);
  });
}

/// A server holding one small book, answered over a fake client.
SyncEngine _restoringEngine(LedgerDb db) {
  const accountId = '019fcce6-0000-7000-8000-00000000a001';
  const txnId = '019fcce6-0000-7000-8000-00000000t001';
  final now = DateTime.now().toUtc().toIso8601String();

  return SyncEngine(
    db: db,
    config: const BbxConfig(baseUrl: 'https://x.test', token: 'bbx_x'),
    httpClient: MockClient((req) async {
      final path = req.url.path;
      dynamic body;
      if (path == '/v1/changes') {
        // The cursor-log shape: one page holding the whole small book.
        final after = int.parse(req.url.queryParameters['after'] ?? '0');
        body = {
          'server_time': now,
          'items': after >= 2
              ? const <dynamic>[]
              : [
                  {'sequence': 1, 'resource': 'accounts',
                   'resource_id': accountId, 'operation': 'upsert'},
                  {'sequence': 2, 'resource': 'txns',
                   'resource_id': txnId, 'operation': 'upsert'},
                ],
          'next_cursor': 2,
          'has_more': false,
        };
      } else if (path == '/v1/accounts') {
        body = [
          {'id': accountId, 'name': 'HDFC salary', 'kind': 'bank',
           'sort_order': 0, 'archived': false},
        ];
      } else if (path == '/v1/txns/$txnId') {
        body = {
          'id': txnId, 'amount_paise': 2000, 'type': 'expense',
          'account_id': accountId, 'title': 'chai', 'at': now,
        };
      } else if (path == '/v1/settings') {
        body = {'name': 'Krish', 'salaryDay': '7'};
      } else if (path == '/v1/categories') {
        body = <dynamic>[];
      } else {
        body = <dynamic>[];
      }
      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json'});
    }),
  );
}
