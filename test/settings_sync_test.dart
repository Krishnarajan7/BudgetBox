import 'dart:convert';

import 'package:budgetbox/data/api/api_client.dart';
import 'package:budgetbox/data/api/api_config.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:budgetbox/data/sync/settings_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Preferences are the one thing that never travelled. A reinstall used to
/// bring the money back and lose the name on the cover.
void main() {
  LedgerDb freshDb() => LedgerDb.forTesting(NativeDatabase.memory());

  /// A stand-in server that keeps whatever it is told.
  ({BbxClient client, Map<String, String> store, List<String> calls}) fake([
    Map<String, String>? seed,
  ]) {
    final store = <String, String>{...?seed};
    final calls = <String>[];
    final client = BbxClient(
      const BbxConfig(baseUrl: 'https://x.test', token: 'bbx_x'),
      inner: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.method == 'GET') {
          return http.Response(jsonEncode(store), 200,
              headers: {'content-type': 'application/json'});
        }
        final key = req.url.pathSegments.last;
        store[key] = (jsonDecode(req.body) as Map)['value'] as String;
        return http.Response(jsonEncode(store), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    return (client: client, store: store, calls: calls);
  }

  test('a book that has set things pushes them up', () async {
    final db = freshDb();
    addTearDown(db.close);
    final repo = SettingsRepo(db);
    await repo.setName('Krish');
    await repo.setSalaryDay(7);
    await repo.setYearFrame('fy');

    final server = fake();
    await SettingsSync(db).run(server.client);

    expect(server.store['name'], 'Krish');
    expect(server.store['salaryDay'], '7');
    expect(server.store['yearFrame'], 'fy');
  });

  test('a fresh install takes back what the server kept', () async {
    final db = freshDb();
    addTearDown(db.close);
    final repo = SettingsRepo(db);

    final server = fake({
      'name': 'Krish',
      'salaryDay': '7',
      'themeMode': 'dark',
      'yearFrame': 'fy',
      'setupDone': 'true',
    });
    await SettingsSync(db).run(server.client);

    expect(await repo.name(), 'Krish');
    expect(await repo.salaryDay(), 7);
    expect(await repo.themeMode(), 'dark');
    expect(await repo.yearFrame(), 'fy');
    expect(await repo.setupDone(), isTrue);
  });

  test('the phone is the author — a live book is never overwritten',
      () async {
    final db = freshDb();
    addTearDown(db.close);
    final repo = SettingsRepo(db);
    await repo.setName('Krish');
    await repo.setSalaryDay(1);

    // The server still holds a stale salary day from another device.
    final server = fake({'name': 'Krish', 'salaryDay': '25'});
    await SettingsSync(db).run(server.client);

    expect(await repo.salaryDay(), 1, reason: 'local wins');
    expect(server.store['salaryDay'], '1', reason: 'and is pushed up');
  });

  test('unchanged preferences are not re-sent', () async {
    final db = freshDb();
    addTearDown(db.close);
    await SettingsRepo(db).setName('Krish');

    final server = fake({'name': 'Krish'});
    await SettingsSync(db).run(server.client);

    expect(server.calls.where((c) => c.startsWith('PUT')), isEmpty);
  });

  test('the PIN and the server address never leave the phone', () async {
    final db = freshDb();
    addTearDown(db.close);
    final repo = SettingsRepo(db);
    await repo.setName('Krish');
    await repo.setPin('1234');
    await repo.setServer('https://bbx.example.in', 'bbx_secret');

    final server = fake();
    await SettingsSync(db).run(server.client);

    expect(server.store.containsKey('pinHash'), isFalse);
    expect(server.store.containsKey('pinSalt'), isFalse);
    expect(server.store.containsKey('serverUrl'), isFalse);
    expect(server.store.containsKey('serverToken'), isFalse);
    expect(server.store['name'], 'Krish');
  });

  test('a server that tries to set a PIN or an address is ignored', () async {
    final db = freshDb();
    addTearDown(db.close);
    final repo = SettingsRepo(db);

    final server = fake({
      'name': 'Krish',
      'pinHash': 'deadbeef',
      'serverUrl': 'https://evil.test',
      'serverToken': 'bbx_evil',
    });
    await SettingsSync(db).run(server.client);

    expect(await repo.name(), 'Krish');
    expect(await repo.hasPin(), isFalse);
    expect((await repo.serverConfig()).wired, isFalse);
  });
}
