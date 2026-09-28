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
  _bodilessErrors();

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
          return http.Response(
            jsonEncode(store),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        final key = req.url.pathSegments.last;
        store[key] = (jsonDecode(req.body) as Map)['value'] as String;
        return http.Response(
          jsonEncode(store),
          200,
          headers: {'content-type': 'application/json'},
        );
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

  group('the kural after a reinstall', () {
    String key(DateTime d) => SettingsRepo.kuralDayKey(d);
    final now = DateTime(2026, 9, 27, 9);
    final today = key(now);
    final yesterday = key(now.subtract(const Duration(days: 1)));

    test(
      'a reinstall that read to-day\'s verse before wiring keeps the server\'s place and streak',
      () async {
        final db = freshDb();
        addTearDown(db.close);
        final repo = SettingsRepo(db);
        // The first opening: a new seed, to-day's verse read, streak 1.
        await repo.kuralCycleSeed();
        await repo.completeDailyKural(today, expectedPosition: 0, total: 1330);
        expect(await repo.kuralPosition(), 1);

        final server = fake({
          'kuralSeed': '777',
          'kuralPosition': '40',
          'kuralDay': yesterday,
          'kuralStreak': '39',
        });
        await SettingsSync(db).run(server.client, now: now);

        // The server's cycle continues here; to-day counts as its fortieth.
        expect(await repo.kuralPosition(), 40);
        expect(await repo.kuralDay(), today);
        // The stored streak is 40: to-morrow's page would make it 41.
      final tomorrow = key(now.add(const Duration(days: 1)));
      expect(await repo.previewKuralStreak(tomorrow, today), 41);
        expect(server.store['kuralSeed'], '777');
        expect(server.store['kuralPosition'], '40');
        expect(server.store['kuralStreak'], '40');
        expect(server.store['kuralDay'], today);
      },
    );

    test('a broken chain on the server does not invent a streak', () async {
      final db = freshDb();
      addTearDown(db.close);
      final repo = SettingsRepo(db);
      await repo.kuralCycleSeed();
      await repo.completeDailyKural(today, expectedPosition: 0, total: 1330);
      final server = fake({
        'kuralSeed': '777',
        'kuralPosition': '40',
        'kuralDay': key(now.subtract(const Duration(days: 4))),
        'kuralStreak': '12',
      });
      await SettingsSync(db).run(server.client, now: now);
      expect(await repo.kuralPosition(), 40);
      expect(server.store['kuralStreak'], '1');
      expect(server.store['kuralDay'], today);
    });

    test('a book further along never yields to an older server copy', () async {
      final db = freshDb();
      addTearDown(db.close);
      final repo = SettingsRepo(db);
      await repo.adoptRemote('kuralSeed', '555');
      await repo.adoptRemote('kuralPosition', '50');
      await repo.adoptRemote('kuralDay', yesterday);
      await repo.adoptRemote('kuralStreak', '10');
      final server = fake({
        'kuralSeed': '777',
        'kuralPosition': '40',
        'kuralDay': yesterday,
        'kuralStreak': '39',
      });
      await SettingsSync(db).run(server.client, now: now);
      expect(await repo.kuralPosition(), 50);
      expect(server.store['kuralSeed'], '555');
      expect(server.store['kuralStreak'], '10');
    });

    test(
      'a fresh phone that has not read yet simply takes the server\'s place',
      () async {
        final db = freshDb();
        addTearDown(db.close);
        final repo = SettingsRepo(db);
        final server = fake({
          'kuralSeed': '777',
          'kuralPosition': '40',
          'kuralDay': yesterday,
          'kuralStreak': '39',
        });
        await SettingsSync(db).run(server.client, now: now);
        expect(await repo.kuralPosition(), 40);
        expect(await repo.kuralDay(), yesterday);
        expect(await repo.previewKuralStreak(today, yesterday), 40);
      },
    );
  });

  test('the phone is the author — a live book is never overwritten', () async {
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

/// A bodiless error used to read as a successful empty response, which is the
/// worst possible failure for a puller: it would conclude the server holds
/// nothing and carry on agreeing with that.
void _bodilessErrors() {
  BbxClient clientFor(int status) => BbxClient(
    const BbxConfig(baseUrl: 'https://x.test', token: 'bbx_x'),
    inner: MockClient((_) async => http.Response('', status)),
  );

  test('an empty 400 is a refusal, not an empty answer', () async {
    await expectLater(
      clientFor(400).get('/v1/changes'),
      throwsA(isA<BbxProblem>()),
    );
  });

  test('an empty 502 is treated as offline, so the queue survives', () async {
    await expectLater(
      clientFor(502).get('/v1/changes'),
      throwsA(isA<BbxOffline>()),
    );
  });

  test('an empty 204 is still a perfectly good nothing', () async {
    expect(await clientFor(204).get('/v1/changes'), isNull);
  });
}
