import 'dart:convert';
import 'dart:math';

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
  static const _pinLength = 'pinLength';
  static const _setupDone = 'setupDone';
  static const _intent = 'intent';
  static const _yearFrame = 'yearFrame';
  static const _birthday = 'birthday';
  static const _nudgeTime = 'nudgeTime';
  static const _kuralDay = 'kuralDay';
  static const _kuralPosition = 'kuralPosition';
  static const _kuralSeed = 'kuralSeed';
  // Read only as a migration fallback for books that used the old sequential
  // counter. New progress is written to [_kuralPosition].
  static const _kuralIndex = 'kuralIndex';
  static const _kuralStreak = 'kuralStreak';
  static const _birthdayBurstYear = 'birthdayBurstYear';
  static const _birthdaySurpriseYear = 'birthdaySurpriseYear';
  static const _serverUrl = 'serverUrl';
  static const _serverToken = 'serverToken';
  static const _waterBottleMl = 'waterBottleMl';
  static const _worthVeiled = 'worthVeiled';
  // The music shelf line — a cache of the server's overview, so the shelf
  // can speak ("412 hrs · 8,140 plays") without a network call.
  static const _musicLine = 'musicLine';
  // The slate's shelf line — same trick, same reason.
  static const _slateLine = 'slateLine';
  // The diet book's one setup answer: height, weight, born, activity, goal,
  // what he eats — one JSON string, because the six move together.
  static const dietProfileKey = 'dietProfile';

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
    _waterBottleMl,
    _worthVeiled,
    // The evening voice's hour, and whether it speaks at all. Losing it on a
    // reinstall turns a silenced book back on by itself, which is the one
    // way a preference can be wrong loudly.
    _nudgeTime,
    // Where he had reached in the 1330, and the streak behind it. Position
    // is the important half: without it a restored book starts the couplets
    // over and hands him ones he has already read.
    _kuralDay,
    _kuralPosition,
    _kuralSeed,
    _kuralIndex,
    _kuralStreak,
    // The once-a-year markers. Without them a reinstall lets a ceremony
    // that has already happened happen again.
    _birthdayBurstYear,
    _birthdaySurpriseYear,
    // The day the Daily page started watching — the clean streak's floor.
    // MarksRepo owns the key (it predates this repo knowing about it);
    // named here so it survives a reinstall like the marks themselves do.
    'marksSince',
    // Not a preference so much as a schema: without the habit definitions a
    // restored phone has every mark in `day_marks` and no idea that 'push'
    // means fifty push-ups. They live here because they are one JSON string
    // with no relationships — a table for them would carry nothing extra.
    habitsKey,
    // The diet targets are derived from this one answer; losing it on a
    // reinstall would ask the same six questions again and, until answered,
    // judge every meal against nothing.
    dietProfileKey,
    // The pin offers he waved away. Forgetting these would re-offer the
    // same rapido line the morning after a reinstall.
    pinPassedKey,
    // The habits he has called fine. Raising "rapido, 7 times" again after
    // a reinstall would be nagging.
    handsMutedKey,
    // The pot the last expense drew on — the add sheet's default, so a
    // reinstall does not start asking "salary or extra?" from scratch.
    lastSourceKey,
  ];

  static const pinPassedKey = 'pinPassed';

  /// Titles (lower-cased) he has said "not this" to on the pin offer.
  Future<Set<String>> pinPassed() async {
    final v = await _get(pinPassedKey);
    if (v == null || v.isEmpty) return {};
    return {
      for (final s in v.split('\n'))
        if (s.isNotEmpty) s,
    };
  }

  Future<void> passPin(String title) async {
    final cur = await pinPassed()
      ..add(title.trim().toLowerCase());
    await _set(pinPassedKey, cur.join('\n'));
  }

  static const lastSourceKey = 'lastSource';

  /// The income category the last expense drew on, if any.
  Future<int?> lastSourceId() async =>
      int.tryParse(await _get(lastSourceKey) ?? '');
  Future<void> setLastSourceId(int id) => _set(lastSourceKey, '$id');

  static const handsMutedKey = 'handsMuted';

  /// Habit keys (see `hands()` in insight_math) he has called fine.
  Future<Set<String>> handsMuted() async {
    final v = await _get(handsMutedKey);
    if (v == null || v.isEmpty) return {};
    return {
      for (final s in v.split('\n'))
        if (s.isNotEmpty) s,
    };
  }

  Future<void> muteHand(String key) async {
    final cur = await handsMuted()
      ..add(key);
    await _set(handsMutedKey, cur.join('\n'));
  }

  /// The diet book's setup, raw. [DietProfile.fromJson] in `diet_math.dart`
  /// gives it shape; this file stays ignorant of the diet module.
  Future<String?> dietProfileJson() => _get(dietProfileKey);
  Future<void> setDietProfileJson(String json) => _set(dietProfileKey, json);

  /// Where [HabitRepo] keeps the checklist. Named here because the sync list
  /// above has to reach it and this file must not import a repo.
  static const habitsKey = 'habits';

  Future<String?> _get(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String value) {
    return _db
        .into(_db.settings)
        .insertOnConflictUpdate(
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
  ///
  /// On by default at nine in the evening — the reminder to write the day
  /// down is most of why the book speaks at all, and a default that stays
  /// silent until found in a settings sheet was doing nobody any good.
  /// Turning it off stores an explicit 'off', so silence chosen once stays
  /// chosen.
  Future<(int hour, int minute)?> nudgeTime() async {
    final v = await _get(_nudgeTime);
    if (v == null) return (21, 0);
    if (v == 'off') return null;
    final parts = v.split(':');
    final h = int.tryParse(parts.first);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (h == null || m == null) return null;
    return (h, m);
  }

  Future<void> setNudgeTime(int hour, int minute) =>
      _set(_nudgeTime, '$hour:$minute');

  Future<void> clearNudge() => _set(_nudgeTime, 'off');

  /// Whether the phone has been asked, once, to allow notifications —
  /// the ask happens at a launch, not buried behind a toggle.
  Future<bool> nudgePermissionAsked() async => await _get('nudgeAsked') != null;

  Future<void> markNudgePermissionAsked() => _set('nudgeAsked', '1');

  // ————— the day's kural —————

  /// The day's water bottle, in millilitres. The glasses target maps onto
  /// this whole: eight glasses always make one bottle, whatever it holds —
  /// change the bottle and every glass quietly resizes with it.
  Future<int> waterBottleMl() async =>
      int.tryParse(await _get(_waterBottleMl) ?? '') ?? 750;

  Future<void> setWaterBottleMl(int ml) => _set(_waterBottleMl, '$ml');

  /// Whether the Worth page keeps its figures behind the eye. Synced since
  /// the restore audit: a book that was veiled should come back veiled —
  /// a reinstall is exactly the wrong moment to put the figures on show.
  Future<bool> worthVeiled() async => await _get(_worthVeiled) == 'true';

  Future<String?> slateLine() => _get(_slateLine);
  Future<void> setSlateLine(String value) => _set(_slateLine, value);

  Future<String?> musicLine() => _get(_musicLine);
  Future<void> setMusicLine(String value) => _set(_musicLine, value);

  Future<void> setWorthVeiled(bool veiled) => _set(_worthVeiled, '$veiled');

  Future<String?> kuralDay() => _get(_kuralDay);

  /// 0-based position inside the current shuffled cycle.
  Future<int> kuralPosition() async {
    final current = int.tryParse(await _get(_kuralPosition) ?? '');
    if (current != null) return current;
    return int.tryParse(await _get(_kuralIndex) ?? '') ?? 0;
  }

  /// Kept as a source-compatible name for older tests/callers. It is a
  /// position now, never the actual Kural number.
  Future<int> kuralIndex() => kuralPosition();

  /// Stable for a whole 1,330-Kural cycle. Creating the seed does not consume
  /// today's reading, so killing the app on the page reopens the same Kural.
  Future<int> kuralCycleSeed() async {
    final existing = int.tryParse(await _get(_kuralSeed) ?? '');
    if (existing != null && existing != 0) return existing;
    final seed = _newKuralSeed();
    await _set(_kuralSeed, '$seed');
    return seed;
  }

  int _newKuralSeed({int? excluding}) {
    int seed;
    do {
      seed = Random.secure().nextInt(0x7ffffffe) + 1;
    } while (seed == excluding);
    return seed;
  }

  Future<void> setKuralShown(String day, int nextIndex) async {
    await _set(_kuralDay, day);
    await _set(_kuralPosition, '$nextIndex');
  }

  int _nextStreak(String today, String? lastDay, int previous) {
    final t = DateTime.parse(today);
    final yesterday = DateTime(t.year, t.month, t.day - 1);
    final yKey =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    return lastDay == yKey ? previous + 1 : 1;
  }

  /// What the streak will become if today's page is completed. This is a
  /// preview only: opening the page earns and consumes nothing.
  Future<int> previewKuralStreak(String today, String? lastDay) async {
    final previous = int.tryParse(await _get(_kuralStreak) ?? '') ?? 0;
    return _nextStreak(today, lastDay, previous);
  }

  /// The single commit point behind “படித்தேன்”. Idempotent for a double tap
  /// and guarded by the expected position so an old page cannot consume a
  /// newer one. Finishing a cycle rotates the seed and starts a fresh shuffle.
  ///
  /// [advance] false marks the day read — streak and all — without moving
  /// the cycle: for the one page a year that steps outside the shuffle, so
  /// the verse standing at to-day's position simply waits for to-morrow.
  Future<int> completeDailyKural(
    String today, {
    required int expectedPosition,
    required int total,
    bool advance = true,
  }) {
    return _db.transaction(() async {
      final previous = int.tryParse(await _get(_kuralStreak) ?? '') ?? 0;
      final lastDay = await kuralDay();
      if (lastDay == today) return previous;

      final current = await kuralPosition();
      if (current != expectedPosition) return previous;

      final streak = _nextStreak(today, lastDay, previous);
      await _set(_kuralDay, today);
      await _set(_kuralStreak, '$streak');
      if (advance) {
        final next = expectedPosition + 1;
        if (next >= total) {
          await _set(_kuralPosition, '0');
          final oldSeed = int.tryParse(await _get(_kuralSeed) ?? '');
          final seed = _newKuralSeed(excluding: oldSeed);
          await _set(_kuralSeed, '$seed');
        } else {
          await _set(_kuralPosition, '$next');
        }
      }
      return streak;
    });
  }

  /// Consecutive reading days, today included: yesterday read → +1,
  /// otherwise the streak starts over at one.
  Future<int> bumpKuralStreak(String today, String? lastDay) async {
    final prev = int.tryParse(await _get(_kuralStreak) ?? '') ?? 0;
    final streak = _nextStreak(today, lastDay, prev);
    await _set(_kuralStreak, '$streak');
    return streak;
  }

  /// The confetti falls once a year — this remembers which year has had it.
  Future<bool> birthdayBurstDue(int year) async =>
      await _get(_birthdayBurstYear) != '$year';

  Future<void> markBirthdayBurst(int year) => _set(_birthdayBurstYear, '$year');

  /// The year the book last turned its owner's-day page. Separate from the
  /// Today burst on purpose: one is a shower on a screen, the other is a
  /// ceremony with the door shut.
  Future<String?> birthdaySurpriseYear() => _get(_birthdaySurpriseYear);

  Future<void> markBirthdaySurprise(int year) =>
      _set(_birthdaySurpriseYear, '$year');

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

  Future<void> clearServer() => (_db.delete(
    _db.settings,
  )..where((s) => s.key.isIn(const [_serverUrl, _serverToken]))).go();

  // ————— for the settings sync —————

  /// Every syncable preference this book has actually set.
  Future<Map<String, String>> syncableValues() async {
    final rows = await (_db.select(
      _db.settings,
    )..where((s) => s.key.isIn(syncableKeys))).get();
    return {for (final r in rows) r.key: r.value};
  }

  /// The day a kural reading belongs to, as a key. The book's day turns
  /// at six in the morning, not midnight (see `kuralDay` in the kural
  /// page): a verse read at half past twelve is still last night's.
  static String kuralDayKey(DateTime now) {
    final d = now.hour < 6 ? now.subtract(const Duration(hours: 6)) : now;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// The kural is progress, not a preference — and the phone-is-the-author
  /// rule gets it wrong on a reinstall: the day's verse greets the very
  /// first opening, before the server is even wired, and that reading
  /// writes a new seed, position 1 and streak 1, which would then win over
  /// the server's fortieth day. So the two copies are compared, and the
  /// one further into the cycle is the book. When the phone has already
  /// read to-day's verse, that day is kept and counted onto the server's
  /// streak rather than restarting it. Returns true when the server's copy
  /// was taken.
  Future<bool> adoptKuralIfFurther(
    Map<String, String> remote, {
    required String today,
  }) async {
    final remotePosition = int.tryParse(
      remote[_kuralPosition] ?? remote[_kuralIndex] ?? '',
    );
    final remoteSeed = remote[_kuralSeed];
    if (remotePosition == null || remoteSeed == null) return false;
    final localPosition = await kuralPosition();
    final localStreak = int.tryParse(await _get(_kuralStreak) ?? '') ?? 0;
    final remoteStreak = int.tryParse(remote[_kuralStreak] ?? '') ?? 0;
    final further =
        remotePosition > localPosition ||
        (remotePosition == localPosition && remoteStreak > localStreak);
    if (!further) return false;

    final localDay = await kuralDay();
    final remoteDay = remote[_kuralDay];
    await _db.transaction(() async {
      await _set(_kuralSeed, remoteSeed);
      await _set(_kuralPosition, '$remotePosition');
      if (localDay == today) {
        // To-day's page was already read here: the day stands, and the
        // streak continues the server's chain if that chain reached
        // yesterday — or starts over if it did not.
        await _set(_kuralDay, today);
        await _set(
          _kuralStreak,
          '${_nextStreak(today, remoteDay, remoteStreak)}',
        );
      } else {
        if (remoteDay != null) await _set(_kuralDay, remoteDay);
        await _set(_kuralStreak, '$remoteStreak');
      }
    });
    return true;
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
    await _set(_pinLength, '${pin.length}');
  }

  /// How many digits the cover should ask for. PINs set before the length
  /// was recorded were all four — the fallback keeps an old lock openable,
  /// which is the difference between an upgrade and a lockout.
  Future<int> pinLength() async =>
      int.tryParse(await _get(_pinLength) ?? '') ?? 4;

  Future<bool> checkPin(String pin) async {
    final hash = await _get(_pinHash);
    final salt = await _get(_pinSalt);
    if (hash == null || salt == null) return false;
    return _hash(pin, salt) == hash;
  }

  Future<void> clearPin() async {
    await (_db.delete(
      _db.settings,
    )..where((s) => s.key.isIn(const [_pinHash, _pinSalt, _pinLength]))).go();
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}
