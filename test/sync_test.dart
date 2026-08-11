import 'dart:convert';

import 'package:budgetbox/data/api/api_config.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/txn_repo.dart';
import 'package:budgetbox/data/sync/ids.dart';
import 'package:budgetbox/data/sync/outbox.dart';
import 'package:budgetbox/data/sync/puller.dart';
import 'package:budgetbox/data/sync/seam.dart';
import 'package:budgetbox/data/sync/sync_engine.dart';
import 'package:budgetbox/data/sync/wire.dart';
import 'package:budgetbox/data/api/api_client.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One recorded request, in the order it went out.
class _Call {
  _Call(this.method, this.path, this.body);

  final String method;
  final String path;
  final Map<String, dynamic> body;

  @override
  String toString() => '$method $path';
}

/// A stand-in server. [answer] decides what each request gets back; anything
/// it does not name is a plain 200.
class _Server {
  _Server(this.answer);

  final http.Response Function(_Call call) answer;
  final calls = <_Call>[];

  http.Client get client => MockClient((request) async {
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : (jsonDecode(request.body) as Map).cast<String, dynamic>();
        final call = _Call(
          request.method,
          request.url.path,
          body,
        );
        calls.add(call);
        return answer(call);
      });

  List<String> get trace => [for (final c in calls) '${c.method} ${c.path}'];
}

http.Response _ok([Object? json]) =>
    http.Response(jsonEncode(json ?? const <String, dynamic>{}), 200,
        headers: {'content-type': 'application/json'});

http.Response _problem(int status, String slug) => http.Response(
      jsonEncode({
        'type': 'urn:budgetbox:problem:$slug',
        'title': slug,
        'detail': 'nope',
      }),
      status,
      headers: {'content-type': 'application/problem+json'},
    );

const _wired = BbxConfig(baseUrl: 'http://book.test', token: 'bbx_test');

void main() {
  late LedgerDb db;
  late SyncOutbox outbox;
  late TxnRepo txns;
  late AccountRepo accounts;
  late int hdfc;
  late int food;

  setUp(() async {
    db = LedgerDb.forTesting(NativeDatabase.memory());
    outbox = SyncOutbox(db);
    installSyncSeam(OutboxSeam(outbox));
    txns = TxnRepo(db);
    accounts = AccountRepo(db);
    hdfc = await accounts.create(name: 'HDFC salary', kind: AccountKind.bank);
    final cats = await db.select(db.categories).get();
    food = cats.firstWhere((c) => c.name == 'Food & chai').id;
  });

  tearDown(() async {
    uninstallSyncSeam();
    await db.close();
  });

  Future<List<OutboxData>> queue() =>
      (db.select(db.outbox)..orderBy([(o) => OrderingTerm.asc(o.id)])).get();

  // ————— minting —————

  group('uuid7', () {
    test('is version 7, variant 10, and time-ordered', () {
      final a = newUuid7(at: DateTime.utc(2026, 1, 1));
      final b = newUuid7(at: DateTime.utc(2026, 8, 1));
      expect(isUuid7(a), isTrue, reason: a);
      expect(isUuid7(b), isTrue, reason: b);
      expect(a.compareTo(b), lessThan(0), reason: 'earlier sorts first');
    });

    test('never repeats inside one millisecond', () {
      final at = DateTime.utc(2026, 8, 1);
      final minted = {for (var i = 0; i < 500; i++) newUuid7(at: at)};
      expect(minted, hasLength(500));
      final sorted = minted.toList()..sort();
      expect(sorted, equals(minted.toList()..sort()));
    });

    test('bridges day-keyed rows both ways', () {
      expect(SyncIds.localIdForDay('2026-08-01'), 20260801);
      expect(SyncIds.dayForLocalId(20260801), '2026-08-01');
    });
  });

  // ————— the repo seam —————

  test('a local write queues exactly one txn row, carrying a uuid7', () async {
    final id = await txns.addExpense(
      amountPaise: 12000,
      accountId: hdfc,
      categoryId: food,
      title: 'Filter coffee',
      at: DateTime(2026, 8, 1, 9),
    );

    final rows = await queue();
    final forTxn = rows.where((r) => r.kind == SyncKinds.txn).toList();
    expect(forTxn, hasLength(1));
    expect(forTxn.single.op, OutboxOp.put);
    expect(forTxn.single.localId, id);
    expect(isUuid7(forTxn.single.remoteId), isTrue);

    final body = jsonDecode(forTxn.single.payload!) as Map<String, dynamic>;
    expect(body['amount_paise'], 12000);
    expect(body['type'], 'expense');
    expect(body['title'], 'Filter coffee');
    expect(isUuid7('${body['account_id']}'), isTrue);
    expect(isUuid7('${body['category_id']}'), isTrue);
    expect('${body['at']}', endsWith('Z'), reason: 'instants are UTC ISO-8601');
  });

  test('the account a txn names is queued ahead of it', () async {
    await txns.addExpense(
      amountPaise: 500,
      accountId: hdfc,
      categoryId: food,
      title: 'Auto',
    );
    final kinds = [for (final r in await queue()) r.kind];
    expect(kinds.indexOf(SyncKinds.account),
        lessThan(kinds.indexOf(SyncKinds.txn)));
    expect(kinds.indexOf(SyncKinds.category),
        lessThan(kinds.indexOf(SyncKinds.txn)));
  });

  test('several edits of one row collapse to the newest payload', () async {
    final id = await txns.addExpense(
      amountPaise: 500,
      accountId: hdfc,
      title: 'Chai',
      at: DateTime(2026, 8, 1),
    );
    for (final amount in [600, 700, 800]) {
      await txns.updateTxn(
        id,
        amountPaise: amount,
        categoryId: null,
        accountId: hdfc,
        title: 'Chai',
        at: DateTime(2026, 8, 1),
      );
    }

    final forTxn =
        (await queue()).where((r) => r.kind == SyncKinds.txn).toList();
    expect(forTxn, hasLength(1), reason: 'four writes, one request owed');
    final body = jsonDecode(forTxn.single.payload!) as Map<String, dynamic>;
    expect(body['amount_paise'], 800);
  });

  test('a balance correction travels as an anchor, not a column', () async {
    await accounts.setBalance(hdfc, 4500000);
    await accounts.setBalance(hdfc, 4600000);

    final anchors =
        (await queue()).where((r) => r.kind == SyncKinds.anchor).toList();
    expect(anchors, hasLength(1));
    final body = jsonDecode(anchors.single.payload!) as Map<String, dynamic>;
    expect(body['balance_paise'], 4600000);
  });

  // ————— draining —————

  test('draining sends an idempotent PUT to the right path and clears it',
      () async {
    await txns.addExpense(
      amountPaise: 12000,
      accountId: hdfc,
      categoryId: food,
      title: 'Filter coffee',
    );
    final txnRow =
        (await queue()).firstWhere((r) => r.kind == SyncKinds.txn);

    final server = _Server((_) => _ok());
    final wire = SyncWire(BbxClient(_wired, inner: server.client));
    final outcome = await outbox.drain(wire);

    expect(outcome.stop, DrainStop.done);
    expect(await queue(), isEmpty);
    expect(server.trace, contains('PUT /v1/txns/${txnRow.remoteId}'));
    expect(server.trace, contains('PUT /v1/accounts/${await outbox.ids
        .remoteFor(SyncKinds.account, hdfc)}'));
    expect(
      server.trace.indexOf('PUT /v1/accounts/${await outbox.ids.remoteFor(SyncKinds.account, hdfc)}'),
      lessThan(server.trace.indexOf('PUT /v1/txns/${txnRow.remoteId}')),
      reason: 'a txn never lands before the account it names',
    );

    final mapping = await outbox.ids.entry(SyncKinds.txn, txnRow.localId);
    expect(mapping!.syncedAt, isNotNull, reason: 'agreed with the server');
  });

  test('BbxOffline leaves the queue intact and burns no attempt', () async {
    await txns.addExpense(
      amountPaise: 500,
      accountId: hdfc,
      title: 'Chai',
    );
    final before = await queue();

    final server = _Server((_) => http.Response('bad gateway', 502));
    final wire = SyncWire(BbxClient(_wired, inner: server.client));
    final outcome = await outbox.drain(wire);

    expect(outcome.stop, DrainStop.offline);
    expect(outcome.sent, 0);
    final after = await queue();
    expect(after.map((r) => r.id), equals(before.map((r) => r.id)));
    expect(after.every((r) => r.attempts == 0), isTrue,
        reason: 'a tunnel is not the write\'s fault');
    expect(server.calls, hasLength(1), reason: 'it stops where it stands');
  });

  test('a refused write parks without blocking the one behind it', () async {
    await txns.addExpense(
      amountPaise: 500,
      accountId: hdfc,
      title: 'Poison',
    );
    final poison = (await queue()).firstWhere((r) => r.kind == SyncKinds.txn);

    await txns.addExpense(
      amountPaise: 900,
      accountId: hdfc,
      title: 'Perfectly fine',
    );
    final good = (await queue()).lastWhere((r) => r.kind == SyncKinds.txn);

    final server = _Server((call) =>
        call.path.endsWith(poison.remoteId) ? _problem(422, 'bad-amount') : _ok());
    final wire = SyncWire(BbxClient(_wired, inner: server.client));

    // Four passes: each one steps over the poisoned row, sends what it can,
    // and burns exactly one attempt on the refusal.
    for (var i = 0; i < SyncOutbox.maxAttempts; i++) {
      final outcome = await outbox.drain(wire);
      expect(outcome.stop, DrainStop.done);
    }

    final left = await queue();
    expect(left, hasLength(1), reason: 'only the poisoned write survives');
    expect(left.single.remoteId, poison.remoteId);
    expect(left.single.attempts, SyncOutbox.maxAttempts);
    expect(left.single.lastError, contains('bad-amount'));
    expect(await outbox.pendingCount(), 0);
    expect(await outbox.parkedCount(), 1);

    // And the good write behind it went out on the very first pass.
    expect(server.trace.take(3), contains('PUT /v1/txns/${good.remoteId}'));
  });

  test('a bad token steps back instead of burning every row', () async {
    await txns.addExpense(amountPaise: 500, accountId: hdfc, title: 'Chai');
    final server = _Server((_) => _problem(401, 'unauthorized'));
    final wire = SyncWire(BbxClient(_wired, inner: server.client));

    final outcome = await outbox.drain(wire);
    expect(outcome.stop, DrainStop.unauthorized);
    expect(server.calls, hasLength(1));
    expect((await queue()).every((r) => r.attempts == 0), isTrue);
  });

  test('deleting a row the server never saw sends nothing at all', () async {
    final id = await txns.addExpense(
      amountPaise: 500,
      accountId: hdfc,
      title: 'Mistake',
    );
    await txns.deleteTxn(id);

    final left = await queue();
    expect(left.where((r) => r.kind == SyncKinds.txn), isEmpty);
    expect(await outbox.ids.remoteFor(SyncKinds.txn, id), isNull);
  });

  // ————— pulling —————

  test('a pull inserts a new remote row and maps it', () async {
    const remoteCash = '01916f10-0000-7000-8000-000000000abc';
    final server = _Server((call) {
      if (call.path == '/v1/changes') {
        return _ok({
          'now': '2026-08-01T12:00:00Z',
          'changed': {
            'accounts': [remoteCash]
          },
        });
      }
      if (call.path == '/v1/accounts') {
        return _ok([
          {
            'id': remoteCash,
            'name': 'Pocket cash',
            'kind': 'cash',
            'sort_order': 3,
            'archived': false,
            'balance_paise': 250000,
            'as_of': '2026-08-01T11:00:00Z',
            'created_at': '2026-08-01T11:00:00Z',
            'updated_at': '2026-08-01T11:00:00Z',
          }
        ]);
      }
      return _ok();
    });

    final wire = SyncWire(BbxClient(_wired, inner: server.client));
    final puller = SyncPuller(db, outbox);
    final outcome = await puller.pull(wire, queueEmpty: true);

    expect(outcome.offline, isFalse);
    expect(outcome.applied, greaterThanOrEqualTo(1));

    final localId = await outbox.ids.localFor(SyncKinds.account, remoteCash);
    expect(localId, isNotNull);
    final row = await (db.select(db.accounts)
          ..where((a) => a.id.equals(localId!)))
        .getSingle();
    expect(row.name, 'Pocket cash');
    expect(row.kind, AccountKind.cash);
    expect(row.balancePaise, 250000);

    // The watermark moved to the server's clock, not the phone's.
    expect((await puller.watermark()).toUtc(),
        DateTime.utc(2026, 8, 1, 12));
  });

  test('a pull never clobbers a row the phone still owes', () async {
    await accounts.setBalance(hdfc, 1); // makes sure the account is queued
    final remoteHdfc =
        await outbox.ids.remoteFor(SyncKinds.account, hdfc) ??
            await outbox.ids.claim(SyncKinds.account, hdfc);
    await (db.update(db.accounts)..where((a) => a.id.equals(hdfc)))
        .write(const AccountsCompanion(name: Value('HDFC salary — mine')));
    await outbox.upsert(SyncKinds.account, hdfc);

    final server = _Server((call) {
      if (call.path == '/v1/changes') {
        return _ok({
          'now': '2026-08-01T12:00:00Z',
          'changed': {
            'accounts': [remoteHdfc]
          },
        });
      }
      if (call.path == '/v1/accounts') {
        return _ok([
          {
            'id': remoteHdfc,
            'name': 'STALE NAME FROM THE SERVER',
            'kind': 'bank',
            'sort_order': 0,
            'archived': true,
            'balance_paise': 999,
            'as_of': null,
            'created_at': '2026-07-01T00:00:00Z',
            'updated_at': '2026-07-01T00:00:00Z',
          }
        ]);
      }
      return _ok();
    });

    final wire = SyncWire(BbxClient(_wired, inner: server.client));
    await SyncPuller(db, outbox).pull(wire, queueEmpty: false);

    final row = await (db.select(db.accounts)..where((a) => a.id.equals(hdfc)))
        .getSingle();
    expect(row.name, 'HDFC salary — mine',
        reason: 'an unsent local write outranks anything downloaded');
    expect(row.archived, isFalse);
  });

  // ————— the conductor —————

  test('the engine pushes before it pulls, once at a time', () async {
    await txns.addExpense(amountPaise: 500, accountId: hdfc, title: 'Chai');

    final server = _Server((call) {
      if (call.path == '/v1/changes') {
        return _ok({'now': '2026-08-01T12:00:00Z', 'changed': {}});
      }
      return _ok();
    });
    final engine = SyncEngine(
      db: db,
      config: _wired,
      httpClient: server.client,
    );
    addTearDown(engine.dispose);
    engine.install();

    await Future.wait([engine.syncNow(), engine.syncNow()]);

    final changesAt = server.trace.indexOf('GET /v1/changes');
    expect(changesAt, greaterThan(0));
    // Everything before the pull is either a write being pushed or the
    // one-time adoption probe that looks for rows both sides already have.
    const adoptionProbe = ['GET /v1/categories', 'GET /v1/accounts'];
    expect(
      server.trace.take(changesAt).where((c) => !adoptionProbe.contains(c)),
      everyElement(startsWith('PUT')),
    );
    expect(server.trace.where((t) => t == 'GET /v1/changes'), hasLength(1),
        reason: 'the second call was dropped, not stacked');
    expect(engine.status.value.phase, SyncPhase.idle);
    expect(engine.status.value.pending, 0);
    expect(engine.status.value.lastSyncedAt, isNotNull);
  });

  test('the engine reports offline and keeps everything owed', () async {
    await txns.addExpense(amountPaise: 500, accountId: hdfc, title: 'Chai');
    final server = _Server((_) => http.Response('down', 503));
    final engine = SyncEngine(
      db: db,
      config: _wired,
      httpClient: server.client,
    );
    addTearDown(engine.dispose);

    await engine.syncNow();
    expect(engine.status.value.phase, SyncPhase.offline);
    expect(engine.status.value.pending, greaterThan(0));
    expect((await queue()).every((r) => r.attempts == 0), isTrue);
  });

  test('a failed adoption sends nothing at all', () async {
    // Pushing before the two sides have recognised each other is what
    // duplicates the seeded categories, so a refused adoption must end the
    // round with an untouched queue rather than pressing on.
    await txns.addExpense(amountPaise: 500, accountId: hdfc, title: 'Chai');

    final server = _Server((call) {
      if (call.path == '/v1/categories' && call.method == 'GET') {
        return http.Response('nope', 503);
      }
      return _ok();
    });
    final engine = SyncEngine(
      db: db,
      config: _wired,
      httpClient: server.client,
    );
    addTearDown(engine.dispose);
    engine.install();

    await engine.syncNow();

    expect(engine.status.value.phase, SyncPhase.offline);
    expect(server.trace.where((c) => c.startsWith('PUT')), isEmpty,
        reason: 'nothing may be pushed before adoption succeeds');
    expect(await db.select(db.outbox).get(), isNotEmpty,
        reason: 'the queue must survive a refused adoption');
  });

  test('an unconfigured app is completely inert', () async {
    // No seam installed at all — exactly how the app boots when no
    // --dart-define was given.
    uninstallSyncSeam();
    await db.delete(db.outbox).go();
    await db.delete(db.remoteIds).go();

    final id = await accounts.create(name: 'Cash', kind: AccountKind.cash);
    await txns.addExpense(amountPaise: 500, accountId: id, title: 'Chai');
    await accounts.setBalance(id, 90000);

    expect(await db.select(db.outbox).get(), isEmpty);
    expect(await db.select(db.remoteIds).get(), isEmpty);

    final server = _Server((_) => throw StateError('must not reach the wire'));
    final engine = SyncEngine(
      db: db,
      config: const BbxConfig(baseUrl: '', token: ''),
      httpClient: server.client,
    );
    addTearDown(engine.dispose);
    engine.install();
    await engine.syncNow();

    expect(server.calls, isEmpty);
    expect(engine.status.value.phase, SyncPhase.idle);
    expect(await db.select(db.outbox).get(), isEmpty);
  });
}
