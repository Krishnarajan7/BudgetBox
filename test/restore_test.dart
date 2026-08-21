import 'dart:convert';

import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/habit_repo.dart';
import 'package:budgetbox/data/repos/marks_repo.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/data/sync/ids.dart';
import 'package:budgetbox/data/sync/seam.dart';
import 'package:budgetbox/data/sync/wire.dart';
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

  test('the streak and the mornings come back too', () async {
    // Day marks, habit definitions and alarms were device-local until v14,
    // which meant a reinstall lost the clean streak and every alarm — the
    // two things in this book that cannot be reconstructed from memory.
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final engine = _dailyLifeEngine(db);
    addTearDown(engine.dispose);
    await engine.syncNow();

    final marks = await db.select(db.dayMarks).get();
    expect(marks, hasLength(3));
    expect(
      marks.map((m) => '${m.date}/${m.kind}'),
      containsAll(['2026-08-17/bath', '2026-08-18/slip', '2026-08-18/meal']),
    );
    expect(marks.firstWhere((m) => m.kind == 'meal').note, 'curd rice');

    final alarms = await db.select(db.alarms).get();
    expect(alarms, hasLength(1));
    expect(alarms.single.label, 'gym');
    expect(alarms.single.minuteOfDay, 330);
    expect(alarms.single.days, 31, reason: 'weekdays, as the mask says');
    expect(alarms.single.snoozeMinutes, 9);

    // And the definitions that make the marks mean anything: without these a
    // restored phone has a row saying 'push' and no idea it meant fifty.
    final habits = await HabitRepo(db).load();
    expect(habits.map((h) => h.kind), contains('push'));
    expect(habits.firstWhere((h) => h.kind == 'push').target, 50);
  });

  test('a mark written on the phone is owed to the server', () async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    installSyncSeam(OutboxSeam.on(db));
    addTearDown(uninstallSyncSeam);

    await MarksRepo(db).toggle(DateTime(2026, 8, 19), 'bath');
    final queued = await db.select(db.outbox).get();
    expect(queued.single.kind, 'mark');
    expect(queued.single.op, OutboxOp.put);
    expect(queued.single.payload, contains('"kind":"bath"'));
    expect(queued.single.payload, contains('"date":"2026-08-19"'));
    // And it knows where to send it.
    expect(
      SyncWire.pathFor('mark', queued.single.remoteId),
      '/v1/marks/${queued.single.remoteId}',
    );
  });

  test('un-ticking a habit is owed as a deletion, not forgotten', () async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    installSyncSeam(OutboxSeam.on(db));
    addTearDown(uninstallSyncSeam);

    final marks = MarksRepo(db);
    await marks.toggle(DateTime(2026, 8, 19), 'bath');
    // Pretend the first write already landed: stamp the mapping as synced
    // and clear the queue. Without that the un-tick is right to forget the
    // row outright — there would be nothing upstream to take back.
    final written = (await db.select(db.dayMarks).get()).single;
    await SyncIds(db).stamp('mark', written.id, DateTime.now());
    await db.delete(db.outbox).go();

    await marks.toggle(DateTime(2026, 8, 19), 'bath');
    expect(await db.select(db.dayMarks).get(), isEmpty);
    final queued = await db.select(db.outbox).get();
    expect(queued.single.op, OutboxOp.delete);
    expect(queued.single.kind, 'mark');
  });
}

/// A server holding a week of daily life: three marks, one alarm, and the
/// habit definitions that give the marks their meaning.
SyncEngine _dailyLifeEngine(LedgerDb db) {
  const bath = '019fcce6-0000-7000-8000-00000000m001';
  const slip = '019fcce6-0000-7000-8000-00000000m002';
  const meal = '019fcce6-0000-7000-8000-00000000m003';
  const alarm = '019fcce6-0000-7000-8000-00000000a101';
  final now = DateTime.now().toUtc().toIso8601String();

  return SyncEngine(
    db: db,
    config: const BbxConfig(baseUrl: 'https://x.test', token: 'bbx_x'),
    httpClient: MockClient((req) async {
      final path = req.url.path;
      dynamic body;
      if (path == '/v1/changes') {
        final after = int.parse(req.url.queryParameters['after'] ?? '0');
        body = {
          'server_time': now,
          'items': after >= 4
              ? const <dynamic>[]
              : [
                  for (final (i, id) in [bath, slip, meal].indexed)
                    {'sequence': i + 1, 'resource': 'day_marks',
                     'resource_id': id, 'operation': 'upsert'},
                  {'sequence': 4, 'resource': 'alarms',
                   'resource_id': alarm, 'operation': 'upsert'},
                ],
          'next_cursor': 4,
          'has_more': false,
        };
      } else if (path == '/v1/marks') {
        body = [
          {'id': bath, 'date': '2026-08-17', 'kind': 'bath', 'note': null,
           'at': '2026-08-17T02:30:00Z'},
          {'id': slip, 'date': '2026-08-18', 'kind': 'slip', 'note': null,
           'at': '2026-08-18T14:00:00Z'},
          {'id': meal, 'date': '2026-08-18', 'kind': 'meal',
           'note': 'curd rice', 'at': '2026-08-18T07:30:00Z'},
        ];
      } else if (path == '/v1/alarms') {
        body = [
          {'id': alarm, 'label': 'gym', 'minute_of_day': 330, 'days': 31,
           'enabled': true, 'snooze_minutes': 9, 'vibrate': true},
        ];
      } else if (path == '/v1/settings') {
        body = {
          'habits': jsonEncode([
            {'kind': 'push', 'name': 'Push-ups', 'target': 50, 'unit': 'reps'},
          ]),
        };
      } else {
        body = <dynamic>[];
      }
      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json'});
    }),
  );
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
