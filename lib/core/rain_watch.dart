import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications.dart';
import 'weather.dart';

/// The one thing the sky is worth interrupting a day for: rain that hasn't
/// started yet.
///
/// There is no background worker in this app and this file does not pretend
/// otherwise. The warning is laid down whenever the book is open and looks at
/// the sky — at launch, on coming back to the front, on a pull-to-refresh —
/// and the operating system holds it from there, so the phone can be face
/// down in a bag when it speaks. The honest limit is that a forecast which
/// appears while the app has not been opened all day is a forecast nobody
/// hears; opening the book once is the whole subscription.
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

  /// The words, given a reading. Null when there is nothing to say — which is
  /// most days, and is the point.
  ///
  /// Separated from the scheduling so the sentence can be proved without a
  /// notification service anywhere in sight.
  static ({String title, String body, DateTime at})? notice(
    Weather? sky, {
    required DateTime now,
  }) {
    final from = sky?.rainFrom;
    if (sky == null || from == null) return null;

    // A reading taken hours ago has a forecast to match. Rather than warn
    // about an hour that may already have come and gone, say nothing and let
    // the next refresh — which the same call sites trigger — do it properly.
    if (now.difference(sky.at) > const Duration(hours: 3)) return null;

    final speakAt = from.subtract(lead);
    if (!speakAt.isAfter(now)) return null;
    if (speakAt.difference(now) > speakWithin) return null;

    final chance = sky.rainChance;
    final hedge = chance != null && chance < 70 ? ', they think' : '';
    return (
      title: 'rain coming$hedge',
      // The hour, said the way the strip says it, and the one instruction
      // that follows from it. No exclamation, no "Don't forget!".
      body: '${Weather.describe(sky.code)} now — '
          '${sky.rainLine ?? 'rain later'}. Take the cover.',
      at: speakAt,
    );
  }

  /// Reads the sky (refreshing it if the stored reading has gone off) and
  /// lays down — or takes back — the warning accordingly.
  ///
  /// Never throws and never blocks anything: no signal, no permission and no
  /// notification plugin all end the same quiet way.
  Future<void> resync(WeatherRepo repo, {DateTime? now}) async {
    try {
      final at = now ?? DateTime.now();
      final sky = await repo.read(now: at);
      await lay(sky, now: at);
    } on Object {
      // The sky is never worth an error on any screen.
    }
  }

  /// Lays down the warning for an already-read [sky]. Split out so a manual
  /// refresh, which has the fresh reading in hand, does not fetch twice.
  Future<void> lay(Weather? sky, {DateTime? now}) async {
    final line = notice(sky, now: now ?? DateTime.now());
    if (line == null) {
      // The forecast changed its mind, or the rain has arrived: either way a
      // warning still standing for it would now be wrong.
      await LedgerReminders.cancelRain();
      return;
    }
    await LedgerReminders.scheduleRain(line.title, line.body, line.at);
  }
}

final rainWatchProvider = Provider<RainWatch>((ref) => const RainWatch());
