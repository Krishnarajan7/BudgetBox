/// The diet book's reminders, and the rule that keeps them from being the
/// daily nag Krish asked never to get.
///
/// Three things make these different from a fixed "log your lunch" alarm:
///
/// **They only speak about a sitting that is genuinely missing.** Each is a
/// one-shot laid at the sitting's deadline (10:30 for breakfast, 15:00 for
/// lunch, 22:00 for dinner; an hour later at weekends), and writing anything
/// into that sitting — a dish, a skip — cancels it. Nothing decides at ring
/// time; the decision is made the moment the plate changes, the same way the
/// evening nudge in `tonight.dart` works.
///
/// **They read the evidence.** A food expense in the ledger with no dish
/// written against it is the cue research says works: the reminder arrives
/// *about* something ("₹180 at Saravana at 1:10 — what was it?") instead of
/// about a clock. The protein still owed to-day is the other fact worth
/// saying by dinner.
///
/// **They never say the same thing two days running.** Wording is chosen by
/// the date, so a Tuesday and a Wednesday differ, but relaunching the app
/// on the same day cannot change a line already scheduled.
library;

import 'package:drift/drift.dart';

import '../core/dates.dart';
import '../core/inr.dart';
import '../core/foods.dart';
import '../core/notifications.dart';
import '../features/diet/diet_math.dart';
import 'db.dart';
import 'repos/diet_repo.dart';
import 'repos/settings_repo.dart';

typedef MealCopy = ({String title, String body});

int _variant(DateTime day, int salt, int count) =>
    (DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
            Duration.millisecondsPerDay +
        salt) %
    count;

/// What the reminder for [slot] says on [day], given what the book can
/// see: a food expense with nothing written against it ([cueTitle],
/// [cuePaise], [cueAt]), and the protein still owed by evening.
MealCopy mealNudgeCopy(
  DateTime day,
  MealSlot slot, {
  String? cueTitle,
  int? cuePaise,
  DateTime? cueAt,
  double? proteinLeftG,
}) {
  final name = slotName(slot);
  if (cueTitle != null && cuePaise != null && cueAt != null) {
    final amount = Inr.format(cuePaise);
    final hh = cueAt.hour % 12 == 0 ? 12 : cueAt.hour % 12;
    final mm = cueAt.minute.toString().padLeft(2, '0');
    final clock = '$hh:$mm ${cueAt.hour < 12 ? 'am' : 'pm'}';
    final choices = <MealCopy>[
      (
        title: '$amount at $cueTitle, $clock',
        body: 'nothing written for $name — what was it?',
      ),
      (
        title: '$name went unwritten',
        body: 'the book saw $amount at $cueTitle at $clock. what was on the plate?',
      ),
      (
        title: 'what did $amount buy at $cueTitle?',
        body: '$name is still blank — one word is enough',
      ),
    ];
    return choices[_variant(day, slot.index, choices.length)];
  }
  if (slot == MealSlot.dinner && proteinLeftG != null && proteinLeftG >= 15) {
    final g = proteinLeftG.round();
    final choices = <MealCopy>[
      (
        title: '$g g of protein still to find',
        body: 'dinner is where it lands — write it when it does',
      ),
      (
        title: 'dinner, and $g g owed',
        body: 'the day is $g g of protein short — put it first on the plate',
      ),
    ];
    return choices[_variant(day, 7, choices.length)];
  }
  final choices = switch (slot) {
    MealSlot.breakfast => const <MealCopy>[
      (title: 'no breakfast on the page', body: 'ate something? one word. skipped it? say so — that counts too'),
      (title: 'the morning is blank', body: 'write what you ate, or mark it skipped — either is an answer'),
      (title: 'breakfast?', body: 'the book has nothing for the morning yet'),
      (title: 'was there a breakfast?', body: 'a word does it — idli, poha, chai — or tap skipped'),
    ],
    MealSlot.lunch => const <MealCopy>[
      (title: 'lunch went unwritten', body: 'what was it? a word is enough'),
      (title: 'the afternoon is blank', body: 'write lunch while it\'s still lunch'),
      (title: 'lunch?', body: 'nothing on the page since morning'),
      (title: 'what was lunch?', body: 'mess, tiffin, out — one word and the book can count it'),
    ],
    MealSlot.snack => const <MealCopy>[
      (title: 'snack?', body: 'anything between meals goes on the page too'),
    ],
    MealSlot.dinner => const <MealCopy>[
      (title: 'dinner isn\'t written', body: 'last sitting of the day — what was it?'),
      (title: 'the evening is blank', body: 'write dinner before the page turns'),
      (title: 'dinner?', body: 'nothing since lunch on the page'),
      (title: 'what was dinner?', body: 'a word closes the day\'s plate'),
    ],
  };
  return choices[_variant(day, slot.index, choices.length)];
}

/// What each sitting's reminder should say for to-day, keyed by slot — or
/// absent when there is nothing to ask: the sitting is written, skipped,
/// its deadline already passed, or the diet book was never set up.
Future<Map<MealSlot, ({MealCopy copy, DateTime at})>> mealLines(
  LedgerDb db, {
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final settings = SettingsRepo(db);
  if (await settings.dietProfileJson() == null) return const {};
  final repo = DietRepo(db, settings);
  final today = LedgerDates.dayKey(at);
  final rows = await (db.select(db.meals)..where((m) => m.date.equals(today))).get();
  final legacy = await (db.select(db.dayMarks)
        ..where((m) => m.kind.equals('meal') & m.date.equals(today)))
      .get();
  final entries = [
    for (final r in rows) DietRepo.entryOf(r),
    for (final m in legacy)
      MealEntry(markId: m.id, at: m.at, slot: slotFor(m.at), name: m.note ?? ''),
  ];
  final totals = totalsFor(today, entries);
  final profile = await repo.profile();
  final proteinTarget = profile == null
      ? null
      : targetOf(targetsFor(profile), Nutrient.protein).rda;
  final spend = await repo.foodSpend(at);

  final out = <MealSlot, ({MealCopy copy, DateTime at})>{};
  for (final slot in mainSlots) {
    if (totals.slotsEaten.contains(slot) || totals.slotsSkipped.contains(slot)) {
      continue;
    }
    final deadline = slotDeadline(slot, at);
    if (!deadline.isAfter(at)) continue;
    // A food expense inside this sitting's window, with nothing written.
    Txn? cue;
    for (final t in spend) {
      if (slotFor(t.at) == slot) cue = t;
    }
    final left = proteinTarget == null
        ? null
        : proteinTarget - totals.nutrients.protein;
    out[slot] = (
      copy: mealNudgeCopy(
        at,
        slot,
        cueTitle: cue?.title,
        cuePaise: cue?.amountPaise,
        cueAt: cue?.at,
        proteinLeftG: left,
      ),
      at: deadline,
    );
  }
  return out;
}

/// The hook the repos call, silent until the app installs the real voice —
/// the same arrangement as `bbxEveningVoice`, for the same reason: no
/// platform channel inside a unit test that writes a row.
typedef MealVoice = Future<void> Function(LedgerDb db, {DateTime? now});

Future<void> _silence(LedgerDb db, {DateTime? now}) async {}

MealVoice bbxMealVoice = _silence;

void installMealVoice(MealVoice voice) => bbxMealVoice = voice;

void uninstallMealVoice() => bbxMealVoice = _silence;

/// Re-lays to-day's three questions so they match the plate as it stands
/// this second. Idempotent; never throws.
Future<void> revoiceMeals(LedgerDb db, {DateTime? now}) async {
  try {
    if (await SettingsRepo(db).nudgeTime() == null) return;
    final lines = await mealLines(db, now: now);
    for (final slot in mainSlots) {
      final line = lines[slot];
      final idx = mainSlots.indexOf(slot);
      if (line == null) {
        await LedgerReminders.cancelMeal(idx);
      } else {
        await LedgerReminders.scheduleMeal(
          idx,
          line.copy.title,
          line.copy.body,
          line.at,
        );
      }
    }
  } on Object {
    // A reminder is not worth failing a write over.
  }
}

/// The fortnight of stand-ins from to-morrow, worded for their own day.
/// Only laid when the diet book is set up; otherwise the slots stay empty.
Future<void> layMealsStanding(LedgerDb db, {DateTime? now}) async {
  try {
    final at = now ?? DateTime.now();
    if (await SettingsRepo(db).dietProfileJson() == null) {
      await LedgerReminders.quietMeals();
      return;
    }
    final copies = <List<(String, String, DateTime)?>>[];
    for (var d = 1; d <= 14; d++) {
      final day = DateTime(at.year, at.month, at.day + d);
      copies.add([
        for (final slot in mainSlots)
          () {
            final c = mealNudgeCopy(day, slot);
            return (c.title, c.body, slotDeadline(slot, day));
          }(),
      ]);
    }
    await LedgerReminders.scheduleMealsStanding(copies);
  } on Object {
    // Silence beats a crash.
  }
}
