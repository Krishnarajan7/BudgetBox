import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/repos/vault_repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LedgerDb db;
  late VaultRepo vault;

  setUp(() {
    db = LedgerDb.forTesting(NativeDatabase.memory());
    // Low iterations: tests exercise correctness, not key-stretching cost.
    vault = VaultRepo(db, iterations: 100);
  });

  tearDown(() => db.close());

  test('starts un-set-up; setUp seals it', () async {
    expect(await vault.isSetUp(), isFalse);
    await vault.setUp('correct horse battery');
    expect(await vault.isSetUp(), isTrue);
  });

  test('right passphrase opens, wrong one does not', () async {
    await vault.setUp('correct horse battery');
    expect(await vault.unlock('correct horse battery'), isNotNull);
    expect(await vault.unlock('wrong horse'), isNull);
    expect(await vault.unlock(''), isNull);
  });

  test('round-trips items, ciphertext only at rest', () async {
    final key = await vault.setUp('correct horse battery');
    await vault.addItem(key, title: 'Aadhaar', body: '1234 5678 9012');
    await vault.addItem(key, title: 'Wifi', body: 'chai-at-ganeshs');

    final items = await vault.readAll(key);
    expect(items.map((i) => i.title), containsAll(['Aadhaar', 'Wifi']));
    expect(items.firstWhere((i) => i.title == 'Aadhaar').body,
        '1234 5678 9012');

    // Nothing legible in the database rows themselves.
    final rows = await db.select(db.vaultItems).get();
    for (final row in rows) {
      expect(row.cipher.contains('Aadhaar'), isFalse);
      expect(row.cipher.contains('1234'), isFalse);
      expect(row.nonce.contains('Wifi'), isFalse);
    }
  });

  test('update re-encrypts under a fresh nonce', () async {
    final key = await vault.setUp('correct horse battery');
    final id = await vault.addItem(key, title: 'card pin', body: '0000');
    final before = (await db.select(db.vaultItems).get()).single;

    await vault.updateItem(key, id, title: 'card pin', body: '9999');
    final after = (await db.select(db.vaultItems).get()).single;
    expect(after.nonce, isNot(before.nonce));
    expect(after.cipher, isNot(before.cipher));

    final items = await vault.readAll(key);
    expect(items.single.body, '9999');
  });

  test('delete burns the page', () async {
    final key = await vault.setUp('correct horse battery');
    final id = await vault.addItem(key, title: 'gone', body: 'soon');
    await vault.deleteItem(id);
    expect(await vault.readAll(key), isEmpty);
    expect(await db.select(db.vaultItems).get(), isEmpty);
  });

  test('a second repo instance with the same passphrase can read it all',
      () async {
    final key = await vault.setUp('correct horse battery');
    await vault.addItem(key, title: 'persists', body: 'across sessions');

    final again = VaultRepo(db, iterations: 100);
    final key2 = await again.unlock('correct horse battery');
    expect(key2, isNotNull);
    final items = await again.readAll(key2!);
    expect(items.single.title, 'persists');
  });
}
