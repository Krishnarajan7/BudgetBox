import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications.dart';
import 'weather.dart';

/// The one thing the sky is worth interrupting a day for: rain that hasn't
/// started yet — said about *his* day, not the sky's.
///
/// There is no background worker in this app and this file does not pretend
/// otherwise. The warning is laid down whenever the book is open and looks at
/// the sky — at launch, on coming back to the front, on a pull-to-refresh —
/// and the operating system holds it from there, so the phone can be face
/// down in a bag when it speaks. The honest limit is that a forecast which
/// appears while the app has not been opened all day is a forecast nobody
/// hears; opening the book once is the whole subscription.
///
/// What makes the line worth reading is what it knows besides the sky: when
/// he usually leaves in the morning (the book has watched the Rapido lines),
/// when his alarm is set, when the sun goes down, how long the rain lasts and
/// how much of it there is. "Rain coming" is a weather app; "rain across
/// your 9 o'clock ride, done by 11" is this book.
///
/// Everything here is idempotent. The same reading laid down five times is
/// one notification, because the id is fixed and re-scheduling replaces.
class RainWatch {
  const RainWatch();

  /// How far ahead of the first wet hour to speak. Long enough to put the
  /// washing in, take the cover, or decide to leave now; not so long that the
  /// warning has gone stale by the time the sky delivers.
  static const lead = Duration(minutes: 45);

  /// Rain further off than this is left alone for now — a later look at the
  /// sky will catch it when it is close enough to act on, and a warning eight
  /// hours early is one you have forgotten by the time it matters.
  static const speakWithin = Duration(hours: 6);

  /// The words, given a reading and what the book knows about the day. Null
  /// when there is nothing to say — which is most days, and is the point.
  ///
  /// Separated from the scheduling so the sentence can be proved without a
  /// notification service anywhere in sight.
  static ({String title, String body, DateTime at})? notice(
    Weather? sky, {
    required DateTime now,
    RainContext context = const RainContext(),
  }) {
    final from = sky?.rainFrom;
    if (sky == null || from == null) return null;

    // A reading taken hours ago has a forecast to match. Rather than warn
    // about an hour that may already have come and gone, say nothing and let
    // the next refresh — which the same call sites trigger — do it properly.
    if (now.difference(sky.at) > const Duration(hours: 3)) return null;

    var speakAt = from.subtract(lead);
    // Rain that begins while he is asleep is not news at four in the
    // morning. With an alarm set before the rain lets up, the line waits for
    // the alarm; without one, it stays quiet.
    final wake = context.wakeAt;
    final small = from.hour < 6 || from.hour >= 23;
    if (small) {
      if (wake == null || !wake.isAfter(now)) return null;
      final until = sky.rainUntil;
      if (until != null && !until.isAfter(wake)) return null;
      speakAt = wake.subtract(const Duration(minutes: 10));
    }
    if (!speakAt.isAfter(now)) return null;
    // Waiting for the alarm is a deliberate wait; the six-hour rule is
    // about not warning too early, not about a night's sleep.
    if (!small && speakAt.difference(now) > speakWithin) return null;

    final words = _copy(sky, now: now, context: context, from: from);
    return (title: words.title, body: words.body, at: speakAt);
  }

  /// One sentence a day, never the same one two days running. The variant
  /// is chosen by the date so a relaunch cannot rewrite a line already laid
  /// down, while to-morrow's is worded afresh.
  static ({String title, String body}) _copy(
    Weather sky, {
    required DateTime now,
    required RainContext context,
    required DateTime from,
  }) {
    final chance = sky.rainChance;
    final unsure = chance != null && chance < 70;
    final hedge = unsure ? ', they think' : '';
    final until = sky.rainUntil;
    final hours = until == null ? null : until.difference(from).inMinutes / 60;
    final mm = sky.rainMm;
    final heavy = mm != null && hours != null && hours > 0 && mm / hours >= 4;
    final light = mm != null && hours != null && hours > 0 && mm / hours < 1;
    final short = hours != null && hours <= 1.01;
    final long = hours != null && hours >= 4;
    final at = _clock(from);
    final done = until == null ? null : _clock(until);
    final v = _variant(from, 3);

    // What kind of rain: the word the body leads with.
    final kind = heavy
        ? 'heavy rain'
        : light
        ? 'drizzle'
        : short
        ? 'a short shower'
        : 'rain';
    final span = done == null
        ? 'from $at'
        : short
        ? 'around $at, over by $done'
        : 'from $at to $done';
    final amount = mm != null && mm >= 2
        ? ' · about ${mm.round()} mm'
        : '';

    // 1. Across the morning ride.
    final leaves = context.leavesAt;
    if (leaves != null &&
        _sameDay(leaves, from) &&
        !leaves.isBefore(from.subtract(const Duration(minutes: 20))) &&
        (until == null || leaves.isBefore(until))) {
      final ride = _clock(leaves);
      return switch (v) {
        0 => (
          title: '$kind across your $ride ride$hedge',
          body: '$span$amount — leave before $at or take the cover',
        ),
        1 => (
          title: 'wet by $at, still wet at $ride$hedge',
          body: heavy
              ? 'the ride will be a soaked one — leave early or wait it out'
              : 'the ride will be a wet one — the cover goes with you',
        ),
        _ => (
          title: 'the $ride ride meets the rain$hedge',
          body: '$span$amount — an early start beats it',
        ),
      };
    }

    // 2. The evening: home from work, sunset or after.
    final evening = from.hour >= 17 && from.hour < 23;
    if (evening) {
      final sunset = sky.sunset;
      final dark = sunset != null && !from.isBefore(sunset);
      return switch (v) {
        0 => (
          title: '$kind by $at$hedge',
          body: done == null
              ? 'the ride home is the wet one$amount — leave early if you can'
              : 'the ride home is the wet one — $span$amount',
        ),
        1 => (
          title: dark ? 'rain after dark, $at$hedge' : 'an evening shower, $at$hedge',
          body: done == null
              ? 'take the cover if you\'re out$amount'
              : short
              ? 'over by $done — wait it out with a chai'
              : 'through to $done$amount — not the evening for the bike',
        ),
        _ => (
          title: 'wet evening ahead$hedge',
          body: '$span$amount — leave before $at or after $done',
        ),
      };
    }

    // 3. Everything else: the day, said with what is known.
    final nowWord = Weather.describe(sky.code);
    return switch (v) {
      0 => (
        title: '$kind by $at$hedge',
        body: '$nowWord now — $span$amount. Take the cover.',
      ),
      1 => (
        title: long ? 'a wet ${_partOfDay(from)}$hedge' : '$kind at $at$hedge',
        body: done == null
            ? '$nowWord now, $kind from $at$amount — plan around it'
            : short
            ? '$span — not worth changing a plan for'
            : '$span$amount — anything outdoors goes before $at',
      ),
      _ => (
        title: '$kind, $at$hedge',
        body: chance != null && unsure
            ? '$chance% by $at — $nowWord now, so the cover is a maybe'
            : '$nowWord now, $span$amount — the cover goes with you',
      ),
    };
  }

  static int _variant(DateTime day, int count) =>
      DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay %
      count;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _partOfDay(DateTime t) => t.hour < 12
      ? 'morning'
      : t.hour < 17
      ? 'afternoon'
      : 'evening';

  /// '4 pm', '1.30 pm' — the way the strip says it.
  static String _clock(DateTime at) {
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final half = at.minute == 0 ? '' : '.${at.minute.toString().padLeft(2, '0')}';
    return '$hour$half ${at.hour < 12 ? 'am' : 'pm'}';
  }

  /// Reads the sky (refreshing it if the stored reading has gone off) and
  /// lays down — or takes back — the warning accordingly.
  ///
  /// Never throws and never blocks anything: no signal, no permission and no
  /// notification plugin all end the same quiet way.
  Future<void> resync(
    WeatherRepo repo, {
    DateTime? now,
    RainContext context = const RainContext(),
  }) async {
    try {
      final at = now ?? DateTime.now();
      final sky = await repo.read(now: at);
      await lay(sky, now: at, context: context);
    } on Object {
      // The sky is never worth an error on any screen.
    }
  }

  /// Lays down the warning for an already-read [sky]. Split out so a manual
  /// refresh, which has the fresh reading in hand, does not fetch twice.
  Future<void> lay(
    Weather? sky, {
    DateTime? now,
    RainContext context = const RainContext(),
  }) async {
    final line = notice(sky, now: now ?? DateTime.now(), context: context);
    if (line == null) {
      // The forecast changed its mind, or the rain has arrived: either way a
      // warning still standing for it would now be wrong.
      await LedgerReminders.cancelRain();
      return;
    }
    await LedgerReminders.scheduleRain(line.title, line.body, line.at);
  }
}

/// What the book knows about the day the rain lands on.
class RainContext {
  const RainContext({this.leavesAt, this.wakeAt});

  /// When he usually sets off in the morning — read from the ride lines
  /// (Rapido, auto, bus) the book has watched. Null until there are enough
  /// of them to trust.
  final DateTime? leavesAt;

  /// The next alarm, if one is set.
  final DateTime? wakeAt;
}

final rainWatchProvider = Provider<RainWatch>((ref) => const RainWatch());
