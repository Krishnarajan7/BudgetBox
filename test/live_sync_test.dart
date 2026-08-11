import 'dart:convert';
import 'dart:io';

import 'package:budgetbox/data/api/api_config.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/data/sync/ids.dart';
import 'package:budgetbox/data/sync/sync_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The only test that proves the wiring end to end, against a real server.
///
/// Everything else in the suite talks to a fake http client, which will
/// happily agree with a payload the actual API would reject. This one writes
/// a transaction the way a screen does, syncs, and then asks the server what
/// it thinks happened.
///
/// It skips itself unless a server is configured, so it is free to leave in
/// the suite:
///
/// ```sh
/// BBX_DB_PATH=/tmp/bbx-dev.db uv run budgetbox serve   # in backend/
/// flutter test test/live_sync_test.dart \
///   --dart-define=BBX_URL=http://127.0.0.1:8000 \
///   --dart-define=BBX_TOKEN=bbx_...
/// ```
void main() {
  final config = BbxConfig.fromEnvironment();

  // Self-skipping: with no server configured this file costs nothing, so a
  // plain `flutter test` stays green on a laptop with no backend running.
  final needsServer = config.wired
      ? null
      : 'needs a backend: pass --dart-define=BBX_URL and BBX_TOKEN';

  liveRestore(config, needsServer);

  test('a written entry reaches the server, once', skip: needsServer, () async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final engine = SyncEngine(db: db, config: config)..install();
    addTearDown(engine.dispose);

    // The app writes an account and an entry exactly as the add sheet does.
    final accounts = AccountRepo(db);
    final accountId = await accounts.create(
      name: 'Live test ${DateTime.now().microsecondsSinceEpoch}',
      kind: AccountKind.cash,
    );
    final title = 'chai ${DateTime.now().microsecondsSinceEpoch}';
    await TxnRepo(db).addExpense(
      amountPaise: 2000,
      accountId: accountId,
      title: title,
      at: DateTime.now(),
    );

    await engine.syncNow();
    expect(engine.status.value.phase, SyncPhase.idle,
        reason: 'sync did not settle: ${engine.status.value.lastError}');

    // The server's own account of it.
    final remote = await _serverTxns(config);
    final matches = remote.where((t) => '${t['title']}' == title).toList();
    expect(matches, hasLength(1), reason: 'expected exactly one $title');
    expect(matches.single['amount_paise'], 2000);

    // Syncing again must not write it a second time.
    await engine.syncNow();
    final after = await _serverTxns(config);
    expect(after.where((t) => '${t['title']}' == title), hasLength(1));
  });

  test('the seeded categories are adopted, not duplicated',
      skip: needsServer, () async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final engine = SyncEngine(db: db, config: config)..install();
    addTearDown(engine.dispose);

    final before = (await _serverGet(config, '/v1/categories')).length;
    await engine.syncNow();
    final after = (await _serverGet(config, '/v1/categories')).length;

    expect(after, before,
        reason: 'the phone pushed its seed instead of adopting the server\'s');

    // And every local category now knows its upstream name.
    final mapped = await db.select(db.remoteIds).get();
    final categories = await db.select(db.categories).get();
    expect(
      mapped.where((m) => m.kind == SyncKinds.category).length,
      categories.length,
    );
  });

  test('preferences reach the server, and come back to a blank phone',
      skip: needsServer, () async {
    final stamp = '${DateTime.now().microsecondsSinceEpoch}';

    // A book with preferences set, synced the way the app syncs.
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final engine = SyncEngine(db: db, config: config)..install();
    addTearDown(engine.dispose);

    final repo = SettingsRepo(db);
    await repo.setName('Krish $stamp');
    await repo.setSalaryDay(7);
    await repo.setYearFrame('fy');
    await repo.setPin('4321');

    await engine.syncNow();
    expect(engine.status.value.phase, SyncPhase.idle,
        reason: engine.status.value.lastError ?? '');

    // A second, blank book on the same server: the restore case.
    final blank = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(blank.close);
    final restored = SyncEngine(db: blank, config: config)..install();
    addTearDown(restored.dispose);
    await restored.syncNow();

    final back = SettingsRepo(blank);
    expect(await back.name(), 'Krish $stamp');
    expect(await back.salaryDay(), 7);
    expect(await back.yearFrame(), 'fy');

    // The lock stayed on the device it guards.
    expect(await back.hasPin(), isFalse);
  });
}

Future<List<Map<String, dynamic>>> _serverTxns(BbxConfig config) =>
    _serverGet(config, '/v1/txns', {'limit': '200'});

Future<List<Map<String, dynamic>>> _serverGet(
  BbxConfig config,
  String path, [
  Map<String, dynamic>? query,
]) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(config.resolve(path, query));
    request.headers.set('authorization', 'Bearer ${config.token}');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (body.isEmpty) return const [];
    final decoded = jsonDecode(body);
    if (decoded is List) {
      return [for (final r in decoded) (r as Map).cast<String, dynamic>()];
    }
    if (decoded is Map && decoded['items'] is List) {
      return [
        for (final r in decoded['items'] as List)
          (r as Map).cast<String, dynamic>(),
      ];
    }
    return const [];
  } finally {
    client.close();
  }
}

/// The reinstall case, against the real server: one phone writes a book, a
/// second blank phone takes it back with nothing but an address and a token.
void liveRestore(BbxConfig config, String? needsServer) {
  test('a blank phone restores the whole book', skip: needsServer, () async {
    final stamp = '${DateTime.now().microsecondsSinceEpoch}';

    final first = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(first.close);
    final writing = SyncEngine(db: first, config: config)..install();
    addTearDown(writing.dispose);

    final accountId = await AccountRepo(first)
        .create(name: 'Restore $stamp', kind: AccountKind.cash);
    await TxnRepo(first).addExpense(
      amountPaise: 4200,
      accountId: accountId,
      title: 'restore $stamp',
      at: DateTime.now(),
    );
    await SettingsRepo(first).setName('Krish $stamp');
    await writing.syncNow();
    expect(writing.status.value.phase, SyncPhase.idle,
        reason: writing.status.value.lastError ?? '');

    // A brand new phone, exactly as the restore page leaves it.
    final blank = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(blank.close);
    expect(await blank.select(blank.txns).get(), isEmpty);

    final restoring = SyncEngine(db: blank, config: config)..install();
    addTearDown(restoring.dispose);
    await restoring.syncNow();

    final txns = await blank.select(blank.txns).get();
    final accounts = await blank.select(blank.accounts).get();
    expect(txns.map((t) => t.title), contains('restore $stamp'));
    expect(accounts.map((a) => a.name), contains('Restore $stamp'));
    expect(await SettingsRepo(blank).name(), 'Krish $stamp');
    expect(await SettingsRepo(blank).hasPin(), isFalse);
  });
}
