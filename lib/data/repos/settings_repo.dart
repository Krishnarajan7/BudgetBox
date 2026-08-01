import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../db.dart';

/// The box's own facts: whose book this is, when salary lands, how it looks,
/// and the PIN that guards it. One row per key in the settings table.
class SettingsRepo {
  SettingsRepo(this._db);

  final LedgerDb _db;

  static const _name = 'name';
  static const _salaryDay = 'salaryDay';
  static const _themeMode = 'themeMode';
  static const _pinHash = 'pinHash';
  static const _pinSalt = 'pinSalt';
  static const _setupDone = 'setupDone';

  Future<String?> _get(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String value) {
    return _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion(key: Value(key), value: Value(value)),
        );
  }

  Future<String> name() async => await _get(_name) ?? 'Krish';
  Future<void> setName(String value) => _set(_name, value);

  Future<int> salaryDay() async =>
      int.tryParse(await _get(_salaryDay) ?? '') ?? 1;
  Future<void> setSalaryDay(int day) => _set(_salaryDay, '$day');

  Future<String?> themeMode() => _get(_themeMode);
  Future<void> setThemeMode(String mode) => _set(_themeMode, mode);

  Future<bool> setupDone() async => await _get(_setupDone) == 'true';
  Future<void> markSetupDone() => _set(_setupDone, 'true');

  // ————— the lock —————

  Future<bool> hasPin() async => await _get(_pinHash) != null;

  Future<void> setPin(String pin) async {
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await _set(_pinSalt, salt);
    await _set(_pinHash, _hash(pin, salt));
  }

  Future<bool> checkPin(String pin) async {
    final hash = await _get(_pinHash);
    final salt = await _get(_pinSalt);
    if (hash == null || salt == null) return false;
    return _hash(pin, salt) == hash;
  }

  Future<void> clearPin() async {
    await (_db.delete(_db.settings)
          ..where((s) => s.key.isIn(const [_pinHash, _pinSalt])))
        .go();
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}
