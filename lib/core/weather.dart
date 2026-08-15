import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../data/db.dart';
import '../data/providers.dart';

/// A reading of the sky: what it is now, what the day is bracketed by, and
/// when it was taken. The book would rather show an hour-old reading with
/// its age on it than a spinner.
class Weather {
  const Weather({
    required this.nowC,
    required this.highC,
    required this.lowC,
    required this.code,
    required this.at,
    this.rainLater = false,
    this.sunrise,
    this.sunset,
  });

  final double nowC;
  final double highC;
  final double lowC;

  /// WMO weather code — the one number Open-Meteo speaks in.
  final int code;
  final DateTime at;

  /// To-day's sunrise and sunset in local wall-clock time, as the service
  /// computed them for wherever the phone is. Null only when a reading came
  /// back without them.
  final DateTime? sunrise;
  final DateTime? sunset;

  /// True when rain shows up later in the day but isn't falling now — the
  /// only forecast worth acting on before leaving the house.
  final bool rainLater;

  /// "33° · light rain by evening" — the whole reading in one line.
  String get line {
    final rounded = nowC.round();
    final sky = rainLater && !describe(code).contains('rain')
        ? 'rain later'
        : describe(code);
    return '$rounded° · $sky';
  }

  /// Is it dark out at [now]?
  ///
  /// The sun does not keep office hours: it sets at 17:50 in Chennai in
  /// December and after 20:00 in London in June, so a fixed "after seven is
  /// night" draws a moon over a bright evening. This follows the real
  /// sunrise and sunset the service returned for this place; only a reading
  /// that arrived without them falls back to a rough guess, and a reading
  /// from another day is honest enough to fall back too rather than compare
  /// against yesterday's sun.
  bool isNight(DateTime now) {
    final up = sunrise;
    final down = sunset;
    if (up != null && down != null && _sameDay(up, now)) {
      return now.isBefore(up) || !now.isBefore(down);
    }
    return now.hour < 6 || now.hour >= 19;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// The next turn of the light: "sunset 18:24" while it is up, "sunrise
  /// 06:03" once it is down. Null when the reading didn't carry them.
  String? sunLine(DateTime now) {
    final up = sunrise;
    final down = sunset;
    if (up == null || down == null || !_sameDay(up, now)) return null;
    final next = isNight(now) ? up : down;
    final label = isNight(now) ? 'sunrise' : 'sunset';
    return '$label ${next.hour.toString().padLeft(2, '0')}:'
        '${next.minute.toString().padLeft(2, '0')}';
  }

  /// "high 35 · low 26" — the day's bracket, for the second line.
  String get bracket => 'high ${highC.round()}° · low ${lowC.round()}°';

  /// How old the reading is, said plainly. Null while it's fresh enough to
  /// need no apology.
  String? staleness(DateTime now) {
    final age = now.difference(at);
    if (age.inMinutes < 90) return null;
    if (age.inHours < 24) return 'as of ${age.inHours}h ago';
    return 'as of ${age.inDays}d ago';
  }

  Map<String, Object?> toJson() => {
    'now': nowC,
    'high': highC,
    'low': lowC,
    'code': code,
    'at': at.toIso8601String(),
    'rainLater': rainLater,
    if (sunrise != null) 'sunrise': sunrise!.toIso8601String(),
    if (sunset != null) 'sunset': sunset!.toIso8601String(),
  };

  static Weather? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['at']}');
    final now = raw['now'];
    final high = raw['high'];
    final low = raw['low'];
    final code = raw['code'];
    if (at == null || now is! num || high is! num || low is! num) return null;
    return Weather(
      nowC: now.toDouble(),
      highC: high.toDouble(),
      lowC: low.toDouble(),
      code: code is num ? code.toInt() : 0,
      at: at,
      rainLater: raw['rainLater'] == true,
      sunrise: DateTime.tryParse('${raw['sunrise']}'),
      sunset: DateTime.tryParse('${raw['sunset']}'),
    );
  }

  /// WMO code → plain English, in this book's register: no "scattered
  /// precipitation", no exclamation, nothing a person wouldn't say.
  static String describe(int code) => switch (code) {
    0 => 'clear',
    1 => 'mostly clear',
    2 => 'part cloud',
    3 => 'overcast',
    45 || 48 => 'fog',
    51 || 53 || 55 => 'drizzle',
    56 || 57 => 'freezing drizzle',
    61 || 63 => 'rain',
    65 => 'heavy rain',
    66 || 67 => 'freezing rain',
    71 || 73 || 75 || 77 => 'snow',
    80 || 81 => 'showers',
    82 => 'violent showers',
    85 || 86 => 'snow showers',
    95 => 'thunderstorm',
    96 || 99 => 'thunderstorm, hail',
    _ => 'unsettled',
  };

  /// One word for the top bar, where there is room for one word. The fuller
  /// phrase lives in [describe] and in the tooltip.
  static String shortLabel(int code) => switch (code) {
    0 || 1 => 'clear',
    2 => 'part cloud',
    3 => 'overcast',
    45 || 48 => 'fog',
    51 || 53 || 55 || 56 || 57 => 'drizzle',
    61 || 63 || 65 || 66 || 67 => 'rain',
    71 || 73 || 75 || 77 || 85 || 86 => 'snow',
    80 || 81 || 82 => 'showers',
    95 || 96 || 99 => 'storm',
    _ => 'cloud',
  };

  /// Codes that mean water is falling out of the sky.
  static bool isWet(int code) =>
      (code >= 51 && code <= 67) || (code >= 80 && code <= 99);
}

/// Fetches a URL and returns its body — the seam tests replace so nothing
/// in this file needs a network to be proved right.
typedef WeatherFetcher = Future<String> Function(Uri url);

/// Where the phone is, in degrees. Also a seam: the plugin only exists on a
/// real device, and the reading is the only part this file needs.
typedef WhereAmI = Future<({double lat, double lon})?> Function();

Future<String> _httpGet(Uri url) async {
  final response = await http.get(url).timeout(const Duration(seconds: 8));
  if (response.statusCode != 200) {
    throw http.ClientException('${response.statusCode}', url);
  }
  return response.body;
}

/// Asks the operating system where we are, once, gently: if permission was
/// refused, it stays refused — the book never nags for it twice in a day.
Future<({double lat, double lon})?> _deviceLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return null;
  }
  // Last known first: it costs nothing and is plenty for a temperature.
  final last = await Geolocator.getLastKnownPosition();
  final position =
      last ??
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
  return (lat: position.latitude, lon: position.longitude);
}

/// The sky, kept in the settings table between readings.
///
/// Open-Meteo needs no key and no account, which is the only reason weather
/// is in this app at all — a personal book shouldn't have to sign up to
/// anything to know it might rain. Everything fails quietly: no signal, no
/// permission, no service means no line on the page, never an error.
class WeatherRepo {
  WeatherRepo(
    this._db, {
    WeatherFetcher fetcher = _httpGet,
    this.locate = _deviceLocation,
  }) : _fetch = fetcher;

  static const _key = 'weather';

  /// A reading older than this is worth replacing when the page opens.
  static const freshFor = Duration(minutes: 45);

  final LedgerDb _db;
  final WeatherFetcher _fetch;

  /// Where the phone is — replaceable so the repo can be proved without a
  /// device, a permission dialog or a sky.
  final WhereAmI locate;

  Future<Weather?> cached() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(_key))).getSingleOrNull();
    if (row == null) return null;
    try {
      return Weather.fromJson(jsonDecode(row.value));
    } on FormatException {
      return null;
    }
  }

  /// The reading to show: what's stored if it's fresh, otherwise a new one,
  /// otherwise what's stored however old it is. Only a book that has never
  /// once seen the sky returns null.
  Future<Weather?> read({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final stored = await cached();
    if (stored != null && at.difference(stored.at) < freshFor) return stored;
    final fresh = await refresh(now: at);
    return fresh ?? stored;
  }

  /// Goes and looks. Returns null on any failure — no signal, no permission,
  /// a shape the service changed — and leaves the old reading in place.
  Future<Weather?> refresh({DateTime? now}) async {
    try {
      final where = await locate();
      if (where == null) return null;
      final body = await _fetch(endpoint(where.lat, where.lon));
      final reading = parse(body, at: now ?? DateTime.now());
      if (reading == null) return null;
      await _db
          .into(_db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion(
              key: const Value(_key),
              value: Value(jsonEncode(reading.toJson())),
            ),
          );
      return reading;
    } on Object {
      return null;
    }
  }

  static Uri endpoint(double lat, double lon) =>
      Uri.parse('https://api.open-meteo.com/v1/forecast').replace(
        queryParameters: {
          'latitude': lat.toStringAsFixed(3),
          'longitude': lon.toStringAsFixed(3),
          'current': 'temperature_2m,weather_code,is_day',
          'hourly': 'weather_code',
          'daily':
              'temperature_2m_max,temperature_2m_min,weather_code,'
              'sunrise,sunset',
          'timezone': 'auto',
          'forecast_days': '1',
        },
      );

  /// Reads Open-Meteo's answer. A missing field means no reading rather than
  /// a guessed one.
  static DateTime? _firstTime(Object? list) {
    if (list is! List || list.isEmpty) return null;
    return DateTime.tryParse('${list.first}');
  }

  static Weather? parse(String body, {required DateTime at}) {
    final raw = jsonDecode(body);
    if (raw is! Map) return null;
    final current = raw['current'];
    final daily = raw['daily'];
    if (current is! Map || daily is! Map) return null;
    final nowC = current['temperature_2m'];
    final highs = daily['temperature_2m_max'];
    final lows = daily['temperature_2m_min'];
    if (nowC is! num || highs is! List || lows is! List) return null;
    if (highs.isEmpty || lows.isEmpty) return null;
    final code = current['weather_code'];
    final nowCode = code is num ? code.toInt() : 0;

    // Rain that hasn't started yet: the rest of to-day's hourly codes.
    var rainLater = false;
    final hourly = raw['hourly'];
    if (!Weather.isWet(nowCode) && hourly is Map && hourly['weather_code'] is List) {
      // Strictly later hours: the hour you are standing in is "now", and
      // "rain later" that means "rain this minute" would be a lie.
      final rest = (hourly['weather_code'] as List).skip(at.hour + 1);
      rainLater = rest.any((c) => c is num && Weather.isWet(c.toInt()));
    }

    // The sun's own hours for this place, to-day. `timezone=auto` means
    // these come back as local wall time, which is the only form the icon
    // and the tooltip care about.
    final sunUp = _firstTime(daily['sunrise']);
    final sunDown = _firstTime(daily['sunset']);

    return Weather(
      nowC: nowC.toDouble(),
      highC: (highs.first as num).toDouble(),
      lowC: (lows.first as num).toDouble(),
      code: nowCode,
      at: at,
      rainLater: rainLater,
      sunrise: sunUp,
      sunset: sunDown,
    );
  }
}

final weatherRepoProvider = Provider<WeatherRepo>(
  (ref) => WeatherRepo(ref.watch(dbProvider)),
);

/// The reading for the page. Never throws, never blocks the page: a null
/// here simply means the strip has nothing to say about the sky.
final weatherProvider = FutureProvider.autoDispose<Weather?>(
  (ref) => ref.watch(weatherRepoProvider).read(),
);
