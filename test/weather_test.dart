import 'package:budgetbox/core/weather.dart';
import 'package:budgetbox/data/db.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _body = '''
{
  "current": {"temperature_2m": 32.7, "weather_code": 2},
  "hourly": {"weather_code": [2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,61,61,61,3,3,3]},
  "daily": {
    "temperature_2m_max": [35.1],
    "temperature_2m_min": [26.4],
    "weather_code": [61],
    "sunrise": ["2026-08-14T06:03"],
    "sunset": ["2026-08-14T18:24"]
  }
}
''';

void main() {
  group('reading Open-Meteo', () {
    test('a reading is taken apart correctly', () {
      final at = DateTime(2026, 8, 14, 9);
      final sky = WeatherRepo.parse(_body, at: at)!;
      expect(sky.nowC, 32.7);
      expect(sky.highC, 35.1);
      expect(sky.lowC, 26.4);
      expect(sky.code, 2);
      expect(sky.at, at);
    });

    test('rain later in the day is spotted, and said', () {
      // At 09:00 the wet codes at 18:00 are still ahead.
      final morning = WeatherRepo.parse(_body, at: DateTime(2026, 8, 14, 9))!;
      expect(morning.rainLater, isTrue);
      expect(morning.line, '33° · rain later');

      // By 20:00 the wet hours (18–20) are behind; nothing more is promised.
      final night = WeatherRepo.parse(_body, at: DateTime(2026, 8, 14, 20))!;
      expect(night.rainLater, isFalse);
      expect(night.line, '33° · part cloud');
    });

    test('a shape it doesn\'t recognise is no reading, not a wrong one', () {
      expect(WeatherRepo.parse('{"current": {}}', at: DateTime(2026)), isNull);
      expect(WeatherRepo.parse('[]', at: DateTime(2026)), isNull);
    });

    test('codes become words a person would use', () {
      expect(Weather.describe(0), 'clear');
      expect(Weather.describe(65), 'heavy rain');
      expect(Weather.describe(95), 'thunderstorm');
      expect(Weather.describe(4242), 'unsettled');
      expect(Weather.isWet(61), isTrue);
      expect(Weather.isWet(2), isFalse);
    });

    test('the endpoint asks for exactly what the strip shows', () {
      final url = WeatherRepo.endpoint(13.0827, 80.2707);
      expect(url.host, 'api.open-meteo.com');
      expect(url.queryParameters['latitude'], '13.083');
      expect(
        url.queryParameters['current'],
        'temperature_2m,weather_code,is_day',
      );
      // The sun's own hours, for this place, to-day.
      expect(url.queryParameters['daily'], contains('sunrise,sunset'));
      expect(url.queryParameters['timezone'], 'auto');
      // Eight days: the strip reads the first, the sky page the rest.
      expect(url.queryParameters['forecast_days'], '8');
    });

    test('the week ahead is read out of the daily columns, and survives '
        'the cache', () {
      const body = '''
      {
        "current": {"temperature_2m": 30.2, "weather_code": 3},
        "daily": {
          "time": ["2026-08-16", "2026-08-17", "2026-08-18"],
          "temperature_2m_max": [33.4, 31.0, 29.8],
          "temperature_2m_min": [26.1, 25.3, 24.9],
          "weather_code": [3, 61, 95],
          "sunrise": ["2026-08-16T05:57"],
          "sunset": ["2026-08-16T18:31"]
        }
      }
      ''';
      final sky = WeatherRepo.parse(body, at: DateTime(2026, 8, 16, 9))!;
      expect(sky.days, hasLength(3));
      expect(sky.days.first.date, DateTime(2026, 8, 16));
      expect(sky.days[1].code, 61);
      expect(sky.days[1].highC, 31.0);
      expect(sky.days[2].lowC, 24.9);

      // The round trip through the settings table loses nothing.
      final kept = Weather.fromJson(sky.toJson())!;
      expect(kept.days, hasLength(3));
      expect(kept.days[2].code, 95);
      expect(kept.days.first.date, DateTime(2026, 8, 16));
    });

    test('a reading without daily columns simply has no week', () {
      final sky = WeatherRepo.parse(_body, at: DateTime(2026, 8, 14, 9))!;
      expect(sky.days, isEmpty);
      expect(Weather.fromJson(sky.toJson())!.days, isEmpty);
    });

    test('an old reading wears its age', () {
      final sky = WeatherRepo.parse(_body, at: DateTime(2026, 8, 14, 9))!;
      expect(sky.staleness(DateTime(2026, 8, 14, 9, 30)), isNull);
      expect(sky.staleness(DateTime(2026, 8, 14, 14)), 'as of 5h ago');
      expect(sky.staleness(DateTime(2026, 8, 16, 9)), 'as of 2d ago');
    });
  });

  group('the repo', () {
    late LedgerDb db;

    setUp(() => db = LedgerDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    WeatherRepo repoWith({
      required List<Uri> calls,
      String body = _body,
      bool located = true,
      bool throws = false,
    }) => WeatherRepo(
      db,
      locate: () async => located ? (lat: 13.08, lon: 80.27) : null,
      fetcher: (url) async {
        calls.add(url);
        if (throws) throw StateError('no signal');
        return body;
      },
    );

    test('a fresh reading is kept and reused without asking again', () async {
      final calls = <Uri>[];
      final repo = repoWith(calls: calls);
      final at = DateTime(2026, 8, 14, 9);
      final first = await repo.read(now: at);
      expect(first!.nowC, 32.7);
      expect(calls.length, 1);

      // Ten minutes later the stored reading is still good.
      final again = await repo.read(now: at.add(const Duration(minutes: 10)));
      expect(again!.nowC, 32.7);
      expect(calls.length, 1, reason: 'no second look while it is fresh');

      // An hour on, it goes and looks again.
      await repo.read(now: at.add(const Duration(hours: 1)));
      expect(calls.length, 2);
    });

    test('no signal keeps the last reading rather than blanking the line',
        () async {
      final at = DateTime(2026, 8, 14, 9);
      await repoWith(calls: []).read(now: at);

      final broken = repoWith(calls: [], throws: true);
      final stale = await broken.read(now: at.add(const Duration(hours: 4)));
      expect(stale, isNotNull);
      expect(stale!.staleness(at.add(const Duration(hours: 4))), 'as of 4h ago');
    });

    test('a refused location is silence, not an error', () async {
      final repo = repoWith(calls: [], located: false);
      expect(await repo.read(now: DateTime(2026, 8, 14, 9)), isNull);
    });

    test('a corrupted stored reading is discarded quietly', () async {
      final calls = <Uri>[];
      final repo = repoWith(calls: calls, body: 'not json');
      expect(await repo.read(now: DateTime(2026, 8, 14, 9)), isNull);
      expect(await repo.cached(), isNull);
    });
  });

  group('following the sun', () {
    Weather reading({String body = _body}) =>
        WeatherRepo.parse(body, at: DateTime(2026, 8, 14, 9))!;

    test('sunrise and sunset come off the reading, in local wall time', () {
      final sky = reading();
      expect(sky.sunrise, DateTime(2026, 8, 14, 6, 3));
      expect(sky.sunset, DateTime(2026, 8, 14, 18, 24));
    });

    test('night is decided by the sun, not by the clock striking seven', () {
      final sky = reading();
      // 18:40 is dark here even though a fixed rule would call it day…
      expect(sky.isNight(DateTime(2026, 8, 14, 18, 40)), isTrue);
      // …and 18:10 is still light even though it is past six.
      expect(sky.isNight(DateTime(2026, 8, 14, 18, 10)), isFalse);
      expect(sky.isNight(DateTime(2026, 8, 14, 5, 30)), isTrue);
      expect(sky.isNight(DateTime(2026, 8, 14, 6, 30)), isFalse);
      // The boundaries themselves: sunrise is day, sunset is night.
      expect(sky.isNight(DateTime(2026, 8, 14, 6, 3)), isFalse);
      expect(sky.isNight(DateTime(2026, 8, 14, 18, 24)), isTrue);
    });

    test('yesterday\'s sun is not asked about to-day', () {
      final sky = reading();
      // A cached reading from another day falls back rather than comparing
      // against a sunset that has already happened.
      expect(sky.isNight(DateTime(2026, 8, 16, 18, 40)), isFalse);
      expect(sky.isNight(DateTime(2026, 8, 16, 20, 0)), isTrue);
    });

    test('a reading with no sun in it still guesses sensibly', () {
      const noSun = """
      {
        "current": {"temperature_2m": 30, "weather_code": 0},
        "daily": {"temperature_2m_max": [33], "temperature_2m_min": [25]}
      }
      """;
      final sky = reading(body: noSun);
      expect(sky.sunrise, isNull);
      expect(sky.isNight(DateTime(2026, 8, 14, 22)), isTrue);
      expect(sky.isNight(DateTime(2026, 8, 14, 12)), isFalse);
      expect(sky.sunLine(DateTime(2026, 8, 14, 12)), isNull);
    });

    test('the tooltip names the next turn of the light', () {
      final sky = reading();
      expect(sky.sunLine(DateTime(2026, 8, 14, 9)), 'sunset 18:24');
      expect(sky.sunLine(DateTime(2026, 8, 14, 20)), 'sunrise 06:03');
    });

    test('the sun survives being stored and read back', () {
      final sky = reading();
      final again = Weather.fromJson(sky.toJson())!;
      expect(again.sunrise, sky.sunrise);
      expect(again.sunset, sky.sunset);
      expect(again.isNight(DateTime(2026, 8, 14, 19)), isTrue);
    });
  });
}
