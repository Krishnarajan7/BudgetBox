import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../api/api_config.dart';
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
  static const _intent = 'intent';
  static const _yearFrame = 'yearFrame';
  static const _birthday = 'birthday';
  static const _nudgeTime = 'nudgeTime';
  static const _kuralDay = 'kuralDay';
  static const _kuralIndex = 'kuralIndex';
  static const _kuralStreak = 'kuralStreak';
  static const _birthdayBurstYear = 'birthdayBurstYear';
  static const _serverUrl = 'serverUrl';
  static const _serverToken = 'serverToken';

  /// The preferences worth keeping on the server, so a reinstall comes back
  /// as the same book rather than a blank one.
  ///
  /// Everything omitted here is omitted on purpose. The PIN's hash and salt
  /// guard *this device* and would be a four-digit search space for anyone
  /// who reached the server; the server's own address and token can't live
  /// behind the connection they configure.
  static const syncableKeys = <String>[
    _name,
    _salaryDay,
    _themeMode,
    _setupDone,
    _intent,
    _yearFrame,
    _birthday,
  ];

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

  /// What the book was asked to watch for at setup: 'leaks', 'goal', or
  /// 'truth'. Reorders the Today page's modules.
  Future<String?> intent() => _get(_intent);
  Future<void> setIntent(String value) => _set(_intent, value);

  /// 'DD-MM', or null while the book doesn't know. The one date a year the
  /// book is allowed to celebrate.
  Future<(int day, int month)?> birthday() async {
    final v = await _get(_birthday);
    if (v == null) return null;
    final parts = v.split('-');
    final d = int.tryParse(parts.first);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (d == null || m == null) return null;
    return (d, m);
  }

  Future<void> setBirthday(int day, int month) =>
      _set(_birthday, '$day-$month');

  /// 'HH:MM' when the evening nudge is on; null when the book stays quiet.
  /// Device-local on purpose: notifications are a per-phone decision.
  Future<(int hour, int minute)?> nudgeTime() async {
    final v = await _get(_nudgeTime);
    if (v == null) return null;
    final parts = v.split(':');
    final h = int.tryParse(parts.first);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (h == null || m == null) return null;
    return (h, m);
  }

  Future<void> setNudgeTime(int hour, int minute) =>
      _set(_nudgeTime, '$hour:$minute');

  Future<void> clearNudge() =>
      (_db.delete(_db.settings)..where((s) => s.key.equals(_nudgeTime))).go();

  // ————— the day's kural —————

  Future<String?> kuralDay() => _get(_kuralDay);

  /// 0-based position of the NEXT kural to show.
  Future<int> kuralIndex() async =>
      int.tryParse(await _get(_kuralIndex) ?? '') ?? 0;

  Future<void> setKuralShown(String day, int nextIndex) async {
    await _set(_kuralDay, day);
    await _set(_kuralIndex, '$nextIndex');
  }

  /// Consecutive reading days, today included: yesterday read → +1,
  /// otherwise the streak starts over at one.
  Future<int> bumpKuralStreak(String today, String? lastDay) async {
    final prev = int.tryParse(await _get(_kuralStreak) ?? '') ?? 0;
    final t = DateTime.parse(today);
    final yesterday = DateTime(t.year, t.month, t.day - 1);
    final yKey =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    final streak = lastDay == yKey ? prev + 1 : 1;
    await _set(_kuralStreak, '$streak');
    return streak;
  }

  /// The confetti falls once a year — this remembers which year has had it.
  Future<bool> birthdayBurstDue(int year) async =>
      await _get(_birthdayBurstYear) != '$year';

  Future<void> markBirthdayBurst(int year) =>
      _set(_birthdayBurstYear, '$year');

  /// How the year is framed: 'calendar' or 'fy' (Apr–Mar).
  Future<String> yearFrame() async => await _get(_yearFrame) ?? 'calendar';
  Future<void> setYearFrame(String value) => _set(_yearFrame, value);

  // ————— the other half of the book —————

  /// Where this book syncs, and the token that opens it.
  ///
  /// What was typed in Settings wins; a `--dart-define` launch is the
  /// fallback, so a build that was already wired that way keeps working
  /// until something is typed over it.
  Future<BbxConfig> serverConfig() async {
    final env = BbxConfig.fromEnvironment();
    final url = await _get(_serverUrl);
    final token = await _get(_serverToken);
    return BbxConfig(
      baseUrl: (url == null || url.isEmpty) ? env.baseUrl : url,
      token: (token == null || token.isEmpty) ? env.token : token,
    );
  }

  /// True once the address was typed here rather than compiled in.
  Future<bool> hasStoredServer() async =>
      (await _get(_serverUrl))?.isNotEmpty ?? false;

  Future<void> setServer(String url, String token) async {
    // A trailing slash and a pasted space are the two things a person
    // reliably gets wrong; neither is worth an error message.
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _set(_serverUrl, clean);
    await _set(_serverToken, token.trim());
  }

  Future<void> clearServer() =>
      (_db.delete(_db.settings)
            ..where((s) => s.key.isIn(const [_serverUrl, _serverToken])))
          .go();

  // ————— for the settings sync —————

  /// Every syncable preference this book has actually set.
  Future<Map<String, String>> syncableValues() async {
    final rows = await (_db.select(_db.settings)
          ..where((s) => s.key.isIn(syncableKeys)))
        .get();
    return {for (final r in rows) r.key: r.value};
  }

  /// Write a preference that came down from the server. Unknown or
  /// non-syncable keys are ignored rather than trusted.
  Future<void> adoptRemote(String key, String value) async {
    if (!syncableKeys.contains(key)) return;
    await _set(key, value);
  }

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
