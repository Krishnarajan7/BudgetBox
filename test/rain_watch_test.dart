import 'package:budgetbox/core/rain_watch.dart';
import 'package:budgetbox/core/weather.dart';
import 'package:flutter_test/flutter_test.dart';

/// When the sky is worth interrupting a day for, and — mostly — when it isn't.
///
/// [RainWatch.notice] is the whole decision, kept free of the notification
/// service so the judgement can be examined without a phone. A wrong "yes"
/// here is a notification about nothing, which is the fastest way to have
/// every notification from this app turned off.
void main() {
  final now = DateTime(2026, 8, 19, 9);

  Weather sky({
    DateTime? rainFrom,
    int? chance,
    int code = 2,
    DateTime? readAt,
  }) => Weather(
    nowC: 31,
    highC: 34,
    lowC: 26,
    code: code,
    at: readAt ?? now,
    rainFrom: rainFrom,
    rainChance: chance,
  );

  group('whether to say anything at all', () {
    test('a dry forecast is silence', () {
      expect(RainWatch.notice(sky(), now: now), isNull);
    });

    test('no reading at all is silence', () {
      expect(RainWatch.notice(null, now: now), isNull);
    });

    test('rain in three hours earns a word, three quarters of an hour ahead', () {
      final line = RainWatch.notice(
        sky(rainFrom: DateTime(2026, 8, 19, 12), chance: 85),
        now: now,
      );
      expect(line, isNotNull);
      expect(line!.at, DateTime(2026, 8, 19, 11, 15));
      expect(line.title, 'rain coming');
      expect(line.body, contains('rain by 12 pm'));
    });

    test('rain past the horizon is left for a later look', () {
      // Nine hours out: real, but a warning now is one you have forgotten by
      // the time the sky delivers. The next refresh will catch it.
      expect(
        RainWatch.notice(sky(rainFrom: DateTime(2026, 8, 19, 18)), now: now),
        isNull,
      );
    });

    test('rain too close to warn about is not warned about', () {
      // Twenty minutes out — the lead time has already passed, and a
      // notification timed for the past is one that never arrives.
      expect(
        RainWatch.notice(sky(rainFrom: DateTime(2026, 8, 19, 9, 20)), now: now),
        isNull,
      );
    });

    test('a stale reading does not get to warn about a stale hour', () {
      // Read four hours ago: its "rain at noon" may already have happened,
      // or been revised away. Say nothing and let the refresh decide.
      expect(
        RainWatch.notice(
          sky(
            rainFrom: DateTime(2026, 8, 19, 12),
            readAt: DateTime(2026, 8, 19, 5),
          ),
          now: now,
        ),
        isNull,
      );
    });
  });

  group('what it says', () {
    test('an uncertain forecast hedges, out loud', () {
      final line = RainWatch.notice(
        sky(rainFrom: DateTime(2026, 8, 19, 12), chance: 40),
        now: now,
      )!;
      expect(line.title, 'rain coming, they think');
      expect(line.body, contains('(40%)'));
    });

    test('a confident forecast does not hedge', () {
      final line = RainWatch.notice(
        sky(rainFrom: DateTime(2026, 8, 19, 12), chance: 90),
        now: now,
      )!;
      expect(line.title, 'rain coming');
      expect(line.body, isNot(contains('%')));
    });

    test('the body says what it is doing now, then what is coming', () {
      final line = RainWatch.notice(
        sky(rainFrom: DateTime(2026, 8, 19, 12), code: 0),
        now: now,
      )!;
      expect(line.body, startsWith('clear now — rain by 12 pm'));
    });

    test('half-past hours are said the way people say them', () {
      final line = RainWatch.notice(
        sky(rainFrom: DateTime(2026, 8, 19, 13, 30)),
        now: now,
      )!;
      expect(line.body, contains('rain by 1.30 pm'));
    });
  });
}
