import 'dart:math' as math;

import 'package:drift/drift.dart' show InsertMode, Value;

import '../core/dates.dart';
import '../core/inr.dart';
import '../core/notifications.dart';
import 'db.dart';
import 'repos/recurring_repo.dart';
import 'repos/settings_repo.dart';
import 'repos/txn_repo.dart';

/// What the book says when the phone is face-down. [LedgerReminders] is the
/// plumbing; this is the voice — it reads the day's actual state and writes
/// tonight's line accordingly, plus the two mornings worth speaking on:
/// salary landing, and a charge asking for money to-morrow.
///
/// [resync] is cheap and idempotent, so it runs at every moment the state
/// may have moved: launch, the app going to the background (the last look
/// before evening), the day being sealed, the nudge toggle. The whole voice
/// hangs off one switch — the evening nudge hour in settings. No hour set,
/// no talking.
class Nudges {
  Nudges(this._db, this._settings, this._txns, this._recurring);

  final LedgerDb _db;
  final SettingsRepo _settings;
  final TxnRepo _txns;
  final RecurringRepo _recurring;

  /// Small counts in the book's hand: 'three', not '3'.
  static String _spelled(int n) {
    const words = [
      'two', 'three', 'four', 'five', 'six', 'seven', //
      'eight', 'nine', 'ten', 'eleven', 'twelve',
    ];
    return n == 1
        ? 'one'
        : (n >= 2 && n <= 12)
        ? words[n - 2]
        : '$n';
  }

  Future<void> resync() async {
    final now = DateTime.now();
    // The book keeps its own evenings regardless of whether it may speak.
    await _autoSeal(now);
    final at = await _settings.nudgeTime();
    if (at == null) {
      await LedgerReminders.quiet();
      return;
    }
    await _tonight(now, at.$1, at.$2);
    await LedgerReminders.scheduleStanding(at.$1, at.$2);
    await _salary(now);
    await _dues(now);
  }

  /// The book closes its own days: every written day before to-day, and
  /// to-day itself once ten at night has passed. The close-the-day button
  /// stays for closing early by hand — the ritual is offered, not owed.
  /// Quiet days are left unsealed; there is nothing on them to close, and
  /// the catch-up sheet may still write onto them.
  Future<void> _autoSeal(DateTime now) async {
    final from = DateTime(now.year, now.month, now.day - 60);
    final txns = await _txns
        .watchRange(from, DateTime(now.year, now.month, now.day + 1))
        .first;
    final written = <String>{for (final t in txns) LedgerDates.dayKey(t.at)};
    if (written.isEmpty) return;
    final cutoff = now.hour >= 22
        ? now
        : DateTime(now.year, now.month, now.day - 1);
    final rows = <DaySealsCompanion>[];
    for (
      var d = from;
      !d.isAfter(cutoff);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      final key = LedgerDates.dayKey(d);
      if (written.contains(key)) {
        rows.add(DaySealsCompanion(date: Value(key)));
      }
    }
    if (rows.isEmpty) return;
    await _db.batch(
      (b) => b.insertAll(_db.daySeals, rows, mode: InsertMode.insertOrIgnore),
    );
  }

  /// Tonight's line carries the day as it stood the last time the app was
  /// in hand. A sealed day cancels it — the ritual already happened.
  Future<void> _tonight(DateTime now, int hour, int minute) async {
    final sealed = await (_db.select(
      _db.daySeals,
    )..where((s) => s.date.equals(LedgerDates.dayKey(now)))).getSingleOrNull();
    if (sealed != null) {
      await LedgerReminders.cancelTonight();
      return;
    }
    final dayStart = DateTime(now.year, now.month, now.day);
    final txns = await _txns
        .watchRange(dayStart, dayStart.add(const Duration(days: 1)))
        .first;
    final expenses = txns.where((t) => t.type == TxnType.expense).toList();
    final paise = expenses.fold(0, (s, t) => s + t.amountPaise);
    if (expenses.isEmpty) {
      await LedgerReminders.scheduleTonight(
        'nothing written to-day',
        'was it truly ₹0? the page waits',
        hour,
        minute,
      );
    } else {
      final count = _spelled(expenses.length);
      final noun = expenses.length == 1 ? 'entry' : 'entries';
      await LedgerReminders.scheduleTonight(
        'the page is still open',
        '${Inr.format(paise)} across $count $noun — close it when the day is done',
        hour,
        minute,
      );
    }
  }

  Future<void> _salary(DateTime now) async {
    final day = await _settings.salaryDay();
    // Clamped so a day-31 salary still lands in February.
    DateTime morning(int year, int month) {
      final d = math.min(day, LedgerDates.daysInMonth(DateTime(year, month)));
      return DateTime(year, month, d, 9);
    }

    var lands = morning(now.year, now.month);
    if (!lands.isAfter(now)) lands = morning(now.year, now.month + 1);
    await LedgerReminders.scheduleSalary(
      'salary lands to-day',
      'the book opens a fresh page for it',
      lands,
    );
  }

  /// Each upcoming charge gets one warning, the evening before at eight.
  /// Anything already inside that window stays silent — the "coming up"
  /// card carries it from there.
  Future<void> _dues(DateTime now) async {
    final upcoming = await _recurring.watchUpcoming().first;
    final byId = <int, (String, String, DateTime)>{};
    for (final d in upcoming) {
      final eve = DateTime(
        d.due.year,
        d.due.month,
        d.due.day,
        20,
      ).subtract(const Duration(days: 1));
      if (!eve.isAfter(now)) continue;
      byId[d.recurring.id] = (
        '${d.recurring.title} asks ${Inr.format(d.recurring.amountPaise)} to-morrow',
        'stamp it paid when it goes',
        eve,
      );
    }
    await LedgerReminders.scheduleDues(byId);
  }
}
