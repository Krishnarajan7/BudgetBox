/// The check-in's reminder: one line, once an evening, on the days the day
/// went unnamed.
///
/// Two rules Krish set, and both are load-bearing:
///
/// **It must not speak on a day already answered.** Notifications are laid
/// down in advance, so nothing can decide at ring time whether it is still
/// wanted — the decision has to be made when the answer arrives. So the word
/// being written *cancels* that evening's alert, and every resync re-lays the
/// horizon from what the book actually holds. A repeating platform alarm
/// cannot do this at all, which is why this is a rolling fortnight of
/// one-shots, the same shape the evening nudge uses.
///
/// **The words never change.** The evening nudge rotates its phrasing on
/// purpose, because a line that reads the ledger has something new to say
/// each night. This one has nothing new to say — it asks the same question
/// every day, and asking it the same way is what turns it into a ritual
/// instead of a notification. A prompt that reworded itself would be
/// performing.
library;

import 'db.dart';
import '../core/dates.dart';
import '../core/notifications.dart';

/// The one wording, for every evening it is ever shown.
const feltNudgeTitle = 'how did to-day sit?';
const feltNudgeBody = 'one word for it, before the page turns.';

/// Half past nine: after the evening nudge's nine o'clock, so closing the
/// ledger and naming the day never arrive in the same breath.
const feltNudgeHour = 21;
const feltNudgeMinute = 30;

/// Has to-day been named? The word is the record — a page can carry a body
/// and still be unnamed, and that is the case this reminder exists for.
Future<bool> feltRecorded(LedgerDb db, {DateTime? now}) async {
  final today = LedgerDates.dayKey(now ?? DateTime.now());
  final row = await (db.select(
    db.journalEntries,
  )..where((e) => e.date.equals(today))).getSingleOrNull();
  if (row == null) return false;
  // The field commits word and coordinates together, so either one standing
  // alone still means the day was answered.
  return row.feelWord != null || row.mood != null;
}

/// The hook the book calls, and the reason it is a hook.
///
/// [JournalRepo] must stay usable — and testable — with no notification
/// service anywhere near it. Same arrangement as `bbxEveningVoice`.
typedef FeltVoice = Future<void> Function(LedgerDb db, {DateTime? now});

Future<void> _silence(LedgerDb db, {DateTime? now}) async {}

/// Silent until an app installs [revoiceFelt] over it.
FeltVoice bbxFeltVoice = _silence;

void installFeltVoice(FeltVoice voice) => bbxFeltVoice = voice;

void uninstallFeltVoice() => bbxFeltVoice = _silence;

/// Re-lays the check-in so it matches the book as it stands this second.
/// Idempotent and safe to call after every write: the ids are fixed, so
/// re-scheduling replaces rather than stacks.
Future<void> revoiceFelt(LedgerDb db, {DateTime? now}) async {
  try {
    final at = now ?? DateTime.now();
    if (await feltRecorded(db, now: at)) {
      // Answered. To-day's alert goes; to-morrow's horizon stays standing,
      // because to-morrow has not been answered yet.
      await LedgerReminders.cancelFelt();
    } else {
      await LedgerReminders.scheduleFelt(
        feltNudgeTitle,
        feltNudgeBody,
        feltNudgeHour,
        feltNudgeMinute,
      );
    }
    await LedgerReminders.scheduleFeltStanding(
      feltNudgeTitle,
      feltNudgeBody,
      feltNudgeHour,
      feltNudgeMinute,
    );
  } on Object {
    // A reminder is not worth failing a write over.
  }
}
