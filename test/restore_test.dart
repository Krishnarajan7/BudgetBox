import 'package:budgetbox/data/db.dart';
import 'package:drift/drift.dart' show Value;
import 'package:budgetbox/data/repos/settings_repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a reinstall must bring back.
///
/// Krish uninstalled and reinstalled, and found the kural streak and the
/// Worth chart gone. Both had the same shape of cause — something the phone
/// kept that the server was never asked to keep, or was never asked to give
/// back. These tests are the standing guard against the next one.
void main() {
  late LedgerDb db;
  late SettingsRepo settings;

  setUp(() {
    db = LedgerDb.forTesting(NativeDatabase.memory());
    settings = SettingsRepo(db);
  });
  tearDown(() => db.close());

  group('preferences survive a reinstall', () {
    test('the kural keeps its place and its streak', () async {
      // Position is the important half: without it a restored book starts
      // the 1330 over and hands back couplets already read.
      for (final key in ['kuralDay', 'kuralPosition', 'kuralSeed', 'kuralStreak']) {
        expect(
          SettingsRepo.syncableKeys,
          contains(key),
          reason: '$key is lost on uninstall',
        );
      }
    });

    test('the evening hour survives, so a silenced book stays silent', () {
      expect(SettingsRepo.syncableKeys, contains('nudgeTime'));
    });

    test('the veil survives', () {
      expect(SettingsRepo.syncableKeys, contains('worthVeiled'));
    });

    test('the daily streak keeps its floor', () {
      // Without it the clean streak restarts at the reinstall date even
      // though every mark came back.
      expect(SettingsRepo.syncableKeys, contains('marksSince'));
    });

    test('a ceremony that already happened does not happen again', () {
      expect(SettingsRepo.syncableKeys, contains('birthdaySurpriseYear'));
      expect(SettingsRepo.syncableKeys, contains('birthdayBurstYear'));
    });

    test('the lock and the server address deliberately do not travel', () {
      // The PIN's hash guards *this device* and would be a four-digit search
      // space to anyone who reached the server; the address and token cannot
      // live behind the connection they configure.
      for (final key in [
        'pinHash',
        'pinSalt',
        'pinLength',
        'serverUrl',
        'serverToken',
      ]) {
        expect(
          SettingsRepo.syncableKeys,
          isNot(contains(key)),
          reason: '$key must never leave the phone',
        );
      }
    });

    test('caches are not carried — they rebuild on first open', () {
      for (final key in ['musicLine', 'slateLine']) {
        expect(SettingsRepo.syncableKeys, isNot(contains(key)));
      }
    });

    test('only known keys are adopted from the server', () async {
      await settings.adoptRemote('pinHash', 'nope');
      await settings.adoptRemote('somethingInvented', 'nope');
      final values = await settings.syncableValues();
      expect(values.containsKey('pinHash'), isFalse);
      expect(values.containsKey('somethingInvented'), isFalse);
    });

    test('an adopted key reads back through its own getter', () async {
      // The round trip that matters: what the server hands over has to be
      // readable by the screen that asked for it, not just present as text.
      await settings.adoptRemote('kuralPosition', '312');
      await settings.adoptRemote('nudgeTime', '22:15');
      expect(await settings.kuralPosition(), 312);
      expect(await settings.nudgeTime(), (22, 15));
    });
  });

  group('the Worth page has readings to draw', () {
    test('a restored book seeds its snapshots', () async {
      // Standing in for the puller's seed: the shape the server hands back
      // (`/v1/networth/accounts` → points of date + value_paise) has to land
      // as rows the chart can read.
      final accountId = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(name: 'HDFC', kind: AccountKind.bank),
          );
      for (final (date, value) in [
        ('2026-08-25', 500000),
        ('2026-08-26', 512000),
        ('2026-08-27', 498000),
      ]) {
        await db
            .into(db.balanceSnapshots)
            .insertOnConflictUpdate(
              BalanceSnapshotsCompanion(
                accountId: Value(accountId),
                date: Value(date),
                balancePaise: Value(value),
              ),
            );
      }
      final rows = await db.select(db.balanceSnapshots).get();
      expect(rows, hasLength(3));
      // Re-running a pull replaces rather than doubles.
      await db
          .into(db.balanceSnapshots)
          .insertOnConflictUpdate(
            BalanceSnapshotsCompanion(
              accountId: Value(accountId),
              date: const Value('2026-08-27'),
              balancePaise: const Value(498000),
            ),
          );
      expect(await db.select(db.balanceSnapshots).get(), hasLength(3));
    });
  });
}
