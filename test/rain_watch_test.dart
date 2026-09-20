import 'package:budgetbox/core/rain_watch.dart';
import 'package:budgetbox/core/weather.dart';
import 'package:budgetbox/data/rain_context.dart';
import 'package:flutter_test/flutter_test.dart';

/// When the sky is worth interrupting a day for, and — mostly — when it
/// isn't; and, when it is, that the line is about *his* day.
///
/// [RainWatch.notice] is the whole decision, kept free of the notification
/// service so the judgement can be examined without a phone. A wrong "yes"
/// here is a notification about nothing, which is the fastest way to have
/// every notification from this app turned off.
void main() {
  final now = DateTime(2026, 8, 19, 9);

  Weather sky({
    DateTime? rainFrom,
    DateTime? rainUntil,
    double? mm,
    int? chance,
    int code = 2,
    DateTime? readAt,
    DateTime? sunset,
  }) => Weather(
    nowC: 31,
    highC: 34,
    lowC: 26,
    code: code,
    at: readAt ?? now,
    rainFrom: rainFrom,
    rainUntil: rainUntil,
    rainMm: mm,
    rainChance: chance,
    sunset: sunset,
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
      expect(line.title, contains('12 pm'));
      expect('${line.title} ${line.body}', contains('rain'));
    });

    test('rain past the horizon is left for a later look', () {
      expect(
        RainWatch.notice(sky(rainFrom: DateTime(2026, 8, 19, 18)), now: now),
        isNull,
      );
    });

    test('rain too close to warn about is not warned about', () {
      expect(
        RainWatch.notice(sky(rainFrom: DateTime(2026, 8, 19, 9, 20)), now: now),
        isNull,
      );
    });

    test('a stale reading does not get to warn about a stale hour', () {
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

    test('rain in the small hours waits for the alarm, or stays quiet', () {
      final late = DateTime(2026, 8, 19, 23, 30);
      final small = sky(
        rainFrom: DateTime(2026, 8, 20, 3),
        rainUntil: DateTime(2026, 8, 20, 9),
        readAt: late,
      );
      // No alarm: nobody is told at 2.15 am.
      expect(RainWatch.notice(small, now: late), isNull);
      // An alarm at 7:30 with the rain still on: the line waits for it.
      final line = RainWatch.notice(
        small,
        now: late,
        context: RainContext(wakeAt: DateTime(2026, 8, 20, 7, 30)),
      );
      expect(line, isNotNull);
      expect(line!.at, DateTime(2026, 8, 20, 7, 20));
    });
  });

  group('what it says', () {
    test('an uncertain forecast hedges, out loud', () {
      final line = RainWatch.notice(
        sky(rainFrom: DateTime(2026, 8, 19, 12), chance: 40),
        now: now,
      )!;
      expect(line.title, contains('they think'));
    });

    test('a confident forecast does not hedge', () {
      final line = RainWatch.notice(
        sky(rainFrom: DateTime(2026, 8, 19, 12), chance: 90),
        now: now,
      )!;
      expect(line.title, isNot(contains('they think')));
    });

    test('the morning ride is named when the rain crosses it', () {
      final line = RainWatch.notice(
        sky(
          rainFrom: DateTime(2026, 8, 19, 12),
          rainUntil: DateTime(2026, 8, 19, 14),
          mm: 3,
        ),
        now: now,
        context: RainContext(leavesAt: DateTime(2026, 8, 19, 12, 30)),
      )!;
      expect('${line.title} ${line.body}', contains('12.30 pm'));
      expect('${line.title} ${line.body}', contains('ride'));
    });

    test('the evening line is about the ride home', () {
      final evening = DateTime(2026, 8, 19, 15);
      final line = RainWatch.notice(
        sky(
          rainFrom: DateTime(2026, 8, 19, 18),
          rainUntil: DateTime(2026, 8, 19, 20),
          mm: 6,
          readAt: evening,
          sunset: DateTime(2026, 8, 19, 18, 50),
        ),
        now: evening,
      )!;
      final said = '${line.title} ${line.body}'.toLowerCase();
      expect(said, anyOf(contains('home'), contains('evening'), contains('dark')));
      expect(said, contains('6 pm'));
    });

    test('a short shower is called one, and heavy rain is called heavy', () {
      final shower = RainWatch.notice(
        sky(
          rainFrom: DateTime(2026, 8, 19, 12),
          rainUntil: DateTime(2026, 8, 19, 13),
          mm: 1.5,
        ),
        now: now,
      )!;
      expect('${shower.title} ${shower.body}', contains('shower'));
      final downpour = RainWatch.notice(
        sky(
          rainFrom: DateTime(2026, 8, 19, 12),
          rainUntil: DateTime(2026, 8, 19, 15),
          mm: 24,
        ),
        now: now,
      )!;
      expect('${downpour.title} ${downpour.body}', contains('heavy'));
      expect('${downpour.title} ${downpour.body}', contains('24 mm'));
    });

    test('two days in a row are not worded the same', () {
      final a = RainWatch.notice(
        sky(rainFrom: DateTime(2026, 8, 19, 12)),
        now: now,
      )!;
      final tomorrow = DateTime(2026, 8, 20, 9);
      final b = RainWatch.notice(
        sky(rainFrom: DateTime(2026, 8, 20, 12), readAt: tomorrow),
        now: tomorrow,
      )!;
      expect(a.title == b.title && a.body == b.body, isFalse);
      // And the same day, re-laid, says exactly what it said before.
      final again = RainWatch.notice(
        sky(rainFrom: DateTime(2026, 8, 19, 12)),
        now: now,
      )!;
      expect(again.title, a.title);
    });
  });

  group('what the book knows about the morning', () {
    test('the usual leaving time is the middle of the weekday first rides', () {
      final rides = [
        DateTime(2026, 9, 14, 8, 50), // Mon
        DateTime(2026, 9, 14, 18, 10), // home — ignored
        DateTime(2026, 9, 15, 9, 5),
        DateTime(2026, 9, 16, 9, 20),
        DateTime(2026, 9, 19, 11, 0), // Saturday — ignored
      ];
      final leaves = usualLeaving(rides, DateTime(2026, 9, 21));
      expect(leaves, DateTime(2026, 9, 21, 9, 5));
    });

    test('two mornings is not a habit', () {
      expect(
        usualLeaving([DateTime(2026, 9, 14, 9), DateTime(2026, 9, 15, 9)], DateTime(2026, 9, 21)),
        isNull,
      );
    });
  });

  group('reading the stretch', () {
    test('the parse finds how long the rain lasts and how much falls', () {
      const body = '''
{"current":{"temperature_2m":30,"weather_code":2,"apparent_temperature":33,"relative_humidity_2m":70},
 "hourly":{"time":["2026-08-19T09:00","2026-08-19T10:00","2026-08-19T11:00","2026-08-19T12:00","2026-08-19T13:00","2026-08-19T14:00","2026-08-19T15:00"],
           "weather_code":[2,2,61,63,61,2,2],
           "precipitation_probability":[10,20,80,90,70,20,10],
           "precipitation":[0,0,1.2,4.5,2.1,0,0]},
 "daily":{"time":["2026-08-19"],"temperature_2m_max":[34],"temperature_2m_min":[26],"weather_code":[61],
          "sunrise":["2026-08-19T06:10"],"sunset":["2026-08-19T18:50"]}}
''';
      final w = WeatherRepo.parse(body, at: DateTime(2026, 8, 19, 9))!;
      expect(w.rainFrom, DateTime(2026, 8, 19, 11));
      expect(w.rainUntil, DateTime(2026, 8, 19, 14));
      expect(w.rainMm, closeTo(7.8, 0.01));
      expect(w.rainChance, 80);
      // And it survives the trip through the settings table.
      final back = Weather.fromJson(w.toJson())!;
      expect(back.rainUntil, w.rainUntil);
      expect(back.rainMm, w.rainMm);
    });
  });
}
