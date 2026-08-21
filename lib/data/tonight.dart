/// Tonight's evening line, and the one rule that keeps it honest: **it is
/// re-voiced the moment the ledger changes.**
///
/// A local notification's words are fixed when it is scheduled, hours before
/// it speaks. The book used to compose them only on a lifecycle event —
/// launch, background, resume — which meant a page that was empty at breakfast
/// still said so at nine at night, and "a quiet money day? confirm the ₹0"
/// arrived on an evening with a dozen entries on it. A reminder that is wrong
/// about the day it is reminding you of is worse than no reminder: it teaches
/// you not to read it.
///
/// So this lives on its own, apart from the rest of [Nudges], because it is
/// the one piece that has to run on the write path: cheap enough to call after
/// every stamp (one settings read, one seal read, one day's entries) and free
/// of anything that would make that a bad idea.
library;

import 'package:drift/drift.dart';

import '../core/dates.dart';
import '../core/inr.dart';
import '../core/notifications.dart';
import 'db.dart';
import 'repos/settings_repo.dart';


/// What the book says at nine, given the day it can actually see.
///
/// Stable per date, so relaunching cannot change the sentence already
/// scheduled for an evening while consecutive nights do not sound copied.
typedef NudgeCopy = ({String title, String body});

int _variant(DateTime day, int count) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay %
    count;

NudgeCopy eveningNudgeCopy(
  DateTime day, {
  required int expenseCount,
  required int spentPaise,
}) {
  if (expenseCount == 0) {
    const choices = <NudgeCopy>[
      (
        title: 'nothing written today',
        body: 'was it truly ₹0? check once before closing',
      ),
      (
        title: 'today’s page is empty',
        body: 'if nothing was spent, the page is ready to close',
      ),
      (
        title: 'a quiet money day?',
        body: 'confirm the ₹0 day, then leave it complete',
      ),
    ];
    return choices[_variant(day, choices.length)];
  }
  final count = spelledCount(expenseCount);
  final noun = expenseCount == 1 ? 'entry' : 'entries';
  final amount = Inr.format(spentPaise);
  final choices = <NudgeCopy>[
    (
      title: '$count $noun on today’s page',
      body:
          '$amount written — check that nothing is missing, then close the day',
    ),
    (
      title: 'today holds $amount',
      body: '$count $noun so far — one last look before the page closes',
    ),
    (
      title: 'is today complete?',
      body: '$amount across $count $noun — seal it when the total is true',
    ),
    (
      title: 'the day has $count $noun',
      body: '$amount recorded — add anything forgotten, or close the page',
    ),
  ];
  return choices[_variant(day, choices.length)];
}

/// Small counts in the book's hand: 'three', not '3'.
String spelledCount(int n) {
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

/// What tonight's line *should* say about [now]'s page, or null when there
/// should be no line at all — the day is already sealed, so the ritual has
/// happened and nothing is owed.
///
/// Pure but for the two reads it needs, so the decision can be examined
/// without a notification service anywhere near it.
Future<NudgeCopy?> tonightsLine(LedgerDb db, {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final today = LedgerDates.dayKey(at);

  final sealed = await (db.select(
    db.daySeals,
  )..where((s) => s.date.equals(today))).getSingleOrNull();
  if (sealed != null) return null;

  final dayStart = DateTime(at.year, at.month, at.day);
  final rows =
      await (db.select(db.txns)..where(
            (t) =>
                t.at.isBiggerOrEqualValue(dayStart) &
                t.at.isSmallerThanValue(dayStart.add(const Duration(days: 1))) &
                t.type.equalsValue(TxnType.expense),
          ))
          .get();
  return eveningNudgeCopy(
    at,
    expenseCount: rows.length,
    spentPaise: rows.fold(0, (s, t) => s + t.amountPaise),
  );
}

/// The hook the ledger calls, and the reason it is a hook.
///
/// [TxnRepo] must stay usable — and testable — with no notification service
/// anywhere near it: a repo that reaches for a platform channel drags one
/// into every unit test that writes a row. So the write path calls this, it
/// is silent by default, and the app installs the real voice at launch. The
/// same arrangement, and for the same reason, as `bbxSync` in `sync/seam.dart`.
typedef EveningVoice = Future<void> Function(LedgerDb db, {DateTime? now});

Future<void> _silence(LedgerDb db, {DateTime? now}) async {}

/// Silent until an app installs [revoiceTonight] over it.
EveningVoice bbxEveningVoice = _silence;

void installEveningVoice(EveningVoice voice) => bbxEveningVoice = voice;

void uninstallEveningVoice() => bbxEveningVoice = _silence;

/// Re-lays tonight's notification so its words match the ledger as it stands
/// this second. Idempotent, and safe to call after every write: the id is
/// fixed, so re-scheduling replaces rather than stacks.
///
/// Never throws. This runs on the stamp path, and an entry that saved
/// correctly must not be reported as a failure because the phone declined to
/// schedule a reminder about it.
Future<void> revoiceTonight(LedgerDb db, {DateTime? now}) async {
  try {
    final hour = await SettingsRepo(db).nudgeTime();
    // The nudge is switched off entirely; [Nudges.resync] owns silencing the
    // rest of the book's voice, so there is nothing to do here.
    if (hour == null) return;
    final copy = await tonightsLine(db, now: now);
    if (copy == null) {
      await LedgerReminders.cancelTonight();
      return;
    }
    await LedgerReminders.scheduleTonight(
      copy.title,
      copy.body,
      hour.$1,
      hour.$2,
    );
  } on Object {
    // A reminder is not worth failing a write over.
  }
}
