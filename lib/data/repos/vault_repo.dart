import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db.dart';
import '../providers.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';

/// The sealed book. True encryption: AES-GCM-256 under a key derived from a
/// vault passphrase (PBKDF2-SHA256). Rows are ciphertext; titles and bodies
/// exist only in memory while the vault is open; the key lives in widget
/// state and dies with the page. A forgotten passphrase is permanent loss —
/// that is the point, and Krish chose it.
class VaultRepo {
  VaultRepo(this._db, {this.iterations = 150000});

  final LedgerDb _db;

  /// PBKDF2 rounds — lowered only in tests.
  final int iterations;

  static const _saltKey = 'vaultSalt';
  static const _checkNonceKey = 'vaultCheckNonce';
  static const _checkCipherKey = 'vaultCheckCipher';
  static const _checkPlain = 'budgetbox-vault-ok';

  final _aes = AesGcm.with256bits();

  Pbkdf2 get _kdf => Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      );

  // ————— sealing & unlocking —————

  Future<bool> isSetUp() async => await _setting(_saltKey) != null;

  /// First seal: mints a salt, derives the key, and stores an encrypted
  /// check value so a wrong passphrase can be told from a right one.
  Future<SecretKey> setUp(String passphrase) async {
    final salt = _aes.newNonce(); // 12 random bytes is plenty of salt
    await _putSetting(_saltKey, base64Encode(salt));
    final key = await _derive(passphrase, salt);
    final box = await _aes.encrypt(utf8.encode(_checkPlain), secretKey: key);
    await _putSetting(_checkNonceKey, base64Encode(box.nonce));
    await _putSetting(_checkCipherKey,
        base64Encode([...box.cipherText, ...box.mac.bytes]));
    return key;
  }

  /// Returns the key when the passphrase is right, null when it isn't.
  Future<SecretKey?> unlock(String passphrase) async {
    final saltB64 = await _setting(_saltKey);
    final nonceB64 = await _setting(_checkNonceKey);
    final cipherB64 = await _setting(_checkCipherKey);
    if (saltB64 == null || nonceB64 == null || cipherB64 == null) return null;

    final key = await _derive(passphrase, base64Decode(saltB64));
    try {
      final plain = await _open(
        nonceB64: nonceB64,
        cipherB64: cipherB64,
        key: key,
      );
      return utf8.decode(plain) == _checkPlain ? key : null;
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  Future<SecretKey> _derive(String passphrase, List<int> salt) {
    return _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  // ————— items —————

  Future<int> addItem(SecretKey key,
      {required String title, required String body}) async {
    final sealed = await _seal(title: title, body: body, key: key);
    return _db.transaction(() async {
      final id = await _db.into(_db.vaultItems).insert(
            VaultItemsCompanion.insert(
              nonce: sealed.nonceB64,
              cipher: sealed.cipherB64,
            ),
          );
      // Only the nonce and the ciphertext ever leave: the queue carries the
      // same opaque blob the table holds, and the passphrase never moves.
      await bbxSync.upsert(SyncKinds.vault, id);
      return id;
    });
  }

  Future<void> updateItem(SecretKey key, int id,
      {required String title, required String body}) async {
    final sealed = await _seal(title: title, body: body, key: key);
    await _db.transaction(() async {
      await (_db.update(_db.vaultItems)..where((v) => v.id.equals(id))).write(
        VaultItemsCompanion(
          nonce: Value(sealed.nonceB64),
          cipher: Value(sealed.cipherB64),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await bbxSync.upsert(SyncKinds.vault, id);
    });
  }

  Future<void> deleteItem(int id) {
    return _db.transaction(() async {
      await (_db.delete(_db.vaultItems)..where((v) => v.id.equals(id))).go();
      await bbxSync.remove(SyncKinds.vault, id);
    });
  }

  /// Decrypts everything (vaults are small). Throws on a wrong key — which
  /// cannot happen through [unlock]'s front door.
  Future<List<VaultOpenItem>> readAll(SecretKey key) async {
    final rows = await (_db.select(_db.vaultItems)
          ..orderBy([(v) => OrderingTerm.desc(v.updatedAt)]))
        .get();
    final out = <VaultOpenItem>[];
    for (final row in rows) {
      final plain = await _open(
        nonceB64: row.nonce,
        cipherB64: row.cipher,
        key: key,
      );
      final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      out.add(VaultOpenItem(
        id: row.id,
        title: json['t'] as String? ?? '',
        body: json['b'] as String? ?? '',
        updatedAt: row.updatedAt,
      ));
    }
    return out;
  }

  Future<({String nonceB64, String cipherB64})> _seal({
    required String title,
    required String body,
    required SecretKey key,
  }) async {
    final plain = utf8.encode(jsonEncode({'t': title, 'b': body}));
    final box = await _aes.encrypt(plain, secretKey: key);
    return (
      nonceB64: base64Encode(box.nonce),
      cipherB64: base64Encode([...box.cipherText, ...box.mac.bytes]),
    );
  }

  Future<List<int>> _open({
    required String nonceB64,
    required String cipherB64,
    required SecretKey key,
  }) {
    final blob = base64Decode(cipherB64);
    final mac = Mac(blob.sublist(blob.length - 16));
    final cipherText = blob.sublist(0, blob.length - 16);
    return _aes.decrypt(
      SecretBox(cipherText, nonce: base64Decode(nonceB64), mac: mac),
      secretKey: key,
    );
  }

  // ————— settings plumbing —————

  Future<String?> _setting(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _putSetting(String key, String value) {
    return _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion(key: Value(key), value: Value(value)),
        );
  }
}

/// A decrypted item — exists only in memory, only while the vault is open.
class VaultOpenItem {
  const VaultOpenItem({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String body;
  final DateTime updatedAt;
}

final vaultRepoProvider =
    Provider<VaultRepo>((ref) => VaultRepo(ref.watch(dbProvider)));
