import 'dart:math' as math;

import 'package:drift/drift.dart' show InsertMode, Value;

import '../core/dates.dart';
import '../core/inr.dart';
import '../core/notifications.dart';
import 'db.dart';
import 'repos/recurring_repo.dart';
import 'repos/settings_repo.dart';
import 'repos/txn_repo.dart';
import 'tonight.dart';

// Tonight's line is composed in `tonight.dart` because it is the one part of
// the book's voice that must also run on the write path — see the note there.
export 'tonight.dart'
    show NudgeCopy, eveningNudgeCopy, spelledCount, tonightsLine;

int _variant(DateTime day, int count) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay %
    count;

/// The fortnight of fallbacks behind tonight's line: one per evening, worded
/// so it never claims a total. Tonight's own line knows what the day wrote;
/// these stand in for the evenings the book has not seen yet, and a stand-in
/// that guessed at a figure would be exactly the lie this file exists to
/// avoid.
///
/// Stable daily rotation: relaunching cannot change the sentence already
/// scheduled for a date, while consecutive evenings do not sound copied.
NudgeCopy standingNudgeCopy(DateTime day) {
  const choices = <NudgeCopy>[
    (
      title: 'is the page complete?',
      body: 'take a minute to check today, then close it if everything is in',
    ),
    (
      title: 'before the day rests',
      body: 'one last look for anything unwritten, then seal the page',
    ),
    (
      title: 'today is waiting to be closed',
      body: 'check the day once; a complete page can carry its seal',
    ),
    (
      title: 'a final look at today',
      body: 'add what is missing, or close the day if the page is true',
    ),
  ];
  return choices[_variant(day, choices.length)];
}

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

  /// Small counts in the book's hand: 'three', not '3'. Kept here as well as
  /// in `tonight.dart` because half the book already says `Nudges.spelled`.
  static String spelled(int n) => spelledCount(n);

  Future<void> resync() async {
    final now = DateTime.now();
    final at = await _settings.nudgeTime();
    if (at == null) {
      await LedgerReminders.quiet();
      // The book still keeps its own evenings when it is not allowed to speak.
      await _autoSeal(now);
      return;
    }
    // Tonight's line goes first, before the sixty-day sweep below it. This
    // method is called as the app is being backgrounded, which on a modern
    // phone is a race against the process being frozen — so the one piece
    // with a deadline on it does not queue behind the one without.
    //
    // Nothing is lost by the order: [_autoSeal] can only seal *to-day* after
    // ten at night, by which time tonight's nine o'clock has already gone and
    // the schedule is a no-op either way.
    await revoiceTonight(_db, now: now);
    await _autoSeal(now);
    await LedgerReminders.scheduleStanding(at.$1, at.$2, [
      for (var i = 1; i <= 14; i++)
        switch (standingNudgeCopy(DateTime(now.year, now.month, now.day + i))) {
          (:final title, :final body) => (title, body),
        },
    ]);
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
