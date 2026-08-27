import 'package:budgetbox/core/dates.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/felt_nudge.dart';
import 'package:budgetbox/data/repos/journal_repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The check-in's two rules, both of them Krish's words:
/// it must not ask on a day already answered, and it must ask the same way
/// every time.
void main() {
  group('the check-in only asks unanswered days', () {
    late LedgerDb db;
    late JournalRepo journal;
    final today = DateTime(2026, 8, 27, 20, 0);
    final key = LedgerDates.dayKey(today);

    setUp(() {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      journal = JournalRepo(db);
    });
    tearDown(() async {
      uninstallFeltVoice();
      await db.close();
    });

    test('an unnamed day is owed the question', () async {
      expect(await feltRecorded(db, now: today), isFalse);
    });

    test('a named day is not', () async {
      await journal.upsert(key, mood: 7, energy: 4, feelWord: 'settled');
      expect(await feltRecorded(db, now: today), isTrue);
    });

    test('a written page with no word is still unnamed', () async {
      // The body is not the answer: this is exactly the day the reminder
      // exists for — the page was opened, the feeling never named.
      await journal.upsert(key, body: 'long day, wrote it all down');
      expect(await feltRecorded(db, now: today), isFalse);
    });

    test('a point placed without choosing a word still counts', () async {
      // The field commits word and coordinates together, but a point can be
      // dropped without naming it, and that is an answer.
      await journal.upsert(key, mood: 5, energy: 5);
      expect(await feltRecorded(db, now: today), isTrue);
    });

    test('yesterday being named does not answer to-day', () async {
      final yesterday = today.subtract(const Duration(days: 1));
      await journal.upsert(
        LedgerDates.dayKey(yesterday),
        mood: 6,
        energy: 6,
        feelWord: 'steady',
      );
      expect(await feltRecorded(db, now: today), isFalse);
      expect(await feltRecorded(db, now: yesterday), isTrue);
    });

    test('naming the day re-lays the reminder, and only a felt write does',
        () async {
      var calls = 0;
      installFeltVoice((_, {DateTime? now}) async => calls++);

      // A body edit changes nothing about whether the day was named, and
      // bodies are written often — it must not wake the voice.
      await journal.upsert(key, body: 'first line');
      await journal.upsert(key, body: 'second line');
      expect(calls, 0);

      // The word arriving is what silences to-night's ask.
      await journal.upsert(key, mood: 7, energy: 4, feelWord: 'settled');
      expect(calls, 1);
    });
  });

  test('the wording never changes', () {
    // The evening nudge rotates on purpose; this one must not. A prompt that
    // reworded itself would be performing rather than asking.
    expect(feltNudgeTitle, 'how did to-day sit?');
    expect(feltNudgeBody, 'one word for it, before the page turns.');
  });

  test('the check-in comes after the evening nudge, not with it', () {
    // Nine o'clock closes the ledger; half past names the day. Two asks in
    // the same breath is one too many.
    expect(feltNudgeHour, 21);
    expect(feltNudgeMinute, 30);
  });
}
