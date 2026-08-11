import 'dart:convert';

import 'package:budgetbox/data/api/api_config.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/account_repo.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/data/sync/seam.dart';
import 'package:budgetbox/data/sync/sync_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The address used to be compiled in. These cover it living in the book.
void main() {
  LedgerDb freshDb() => LedgerDb.forTesting(NativeDatabase.memory());

  group('stored server config', () {
    test('an unwired book reports itself as such', () async {
      final db = freshDb();
      addTearDown(db.close);
      final cfg = await SettingsRepo(db).serverConfig();
      expect(cfg.wired, isFalse);
    });

    test('what is typed is what comes back', () async {
      final db = freshDb();
      addTearDown(db.close);
      final repo = SettingsRepo(db);
      await repo.setServer('https://bbx.example.in', 'bbx_abc');
      final cfg = await repo.serverConfig();
      expect(cfg.baseUrl, 'https://bbx.example.in');
      expect(cfg.token, 'bbx_abc');
      expect(cfg.wired, isTrue);
      expect(await repo.hasStoredServer(), isTrue);
    });

    test('a trailing slash and stray spaces are forgiven', () async {
      final db = freshDb();
      addTearDown(db.close);
      final repo = SettingsRepo(db);
      await repo.setServer('  https://bbx.example.in///  ', '  bbx_abc  ');
      final cfg = await repo.serverConfig();
      expect(cfg.baseUrl, 'https://bbx.example.in');
      expect(cfg.token, 'bbx_abc');
      // And the resolver still builds a sane URL from it.
      expect(cfg.resolve('/v1/ping').toString(),
          'https://bbx.example.in/v1/ping');
    });

    test('clearing it puts the book back to syncing with nothing', () async {
      final db = freshDb();
      addTearDown(db.close);
      final repo = SettingsRepo(db);
      await repo.setServer('https://bbx.example.in', 'bbx_abc');
      await repo.clearServer();
      expect((await repo.serverConfig()).wired, isFalse);
      expect(await repo.hasStoredServer(), isFalse);
    });

    test('host reads without the scheme or the token', () {
      expect(
        const BbxConfig(baseUrl: 'https://bbx.example.in', token: 't').host,
        'bbx.example.in',
      );
      expect(
        const BbxConfig(baseUrl: 'http://10.0.0.4:8787', token: 't').host,
        '10.0.0.4:8787',
      );
    });
  });

  group('re-pointing a running engine', () {
    test('wiring installs the seam; unwiring removes it', () async {
      final db = freshDb();
      addTearDown(db.close);
      final engine = SyncEngine(db: db, config: BbxConfig.none)..install();
      addTearDown(engine.dispose);

      expect(engine.wired, isFalse);
      expect(bbxSync, isA<InertSeam>());

      engine.reconfigure(
        const BbxConfig(baseUrl: 'https://bbx.example.in', token: 'bbx_x'),
      );
      expect(engine.wired, isTrue);
      expect(bbxSync, isA<OutboxSeam>());

      engine.reconfigure(BbxConfig.none);
      expect(engine.wired, isFalse);
      expect(bbxSync, isA<InertSeam>());
    });

    test('a book written before wiring still walks upstream', () async {
      final db = freshDb();
      addTearDown(db.close);

      // Unwired: the ritual's account is written with nothing queued.
      final engine = SyncEngine(db: db, config: BbxConfig.none)..install();
      await AccountRepo(db).create(
        name: 'Cash',
        kind: AccountKind.cash,
        openingBalancePaise: 0,
      );
      expect(await db.select(db.outbox).get(), isEmpty);
      engine.dispose();

      // Wired later: the catch-up sweep carries it up on the first round.
      final seen = <String>[];
      final wired = SyncEngine(
        db: db,
        config: const BbxConfig(baseUrl: 'https://x.test', token: 'bbx_x'),
        httpClient: MockClient((req) async {
          seen.add('${req.method} ${req.url.path}');
          if (req.url.path == '/v1/changes') {
            return http.Response(
              jsonEncode({'now': DateTime.now().toUtc().toIso8601String(),
                          'changed': <String, dynamic>{}}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(jsonEncode(<String, dynamic>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
      )..install();
      addTearDown(wired.dispose);

      await wired.syncNow();
      expect(seen.any((s) => s.startsWith('PUT /v1/accounts/')), isTrue,
          reason: 'the pre-existing account should have been swept up');
    });
  });
}
