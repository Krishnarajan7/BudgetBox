import '../../tables.dart';
import '../api_client.dart';
import 'wire.dart';

/// The long view. History is a rebuildable cache of daily balance readings —
/// the last ninety days re-derive on every run, so a corrected transaction
/// fixes the past instead of leaving a kink in the line.
class NetworthApi {
  const NetworthApi(this._c);

  final BbxClient _c;

  Future<NetWorthNow> current() async =>
      NetWorthNow.fromJson(wireObject(await _c.get('/v1/networth/current')));

  /// The line. Pass [accountId] to narrow it to one account.
  Future<SeriesOut> series({
    NetWorthRange range = NetWorthRange.sixMonths,
    String? accountId,
  }) async =>
      SeriesOut.fromJson(
        wireObject(
          await _c.get('/v1/networth/series', {
            'range': netWorthRangeWire.toWire(range),
            'account_id': accountId,
          }),
        ),
      );

  /// One row per account with its own sparkline — the Worth page in a call.
  Future<List<AccountSpark>> accounts({int points = 30}) async => wireList(
        await _c.get('/v1/networth/accounts', {'points': points}),
        AccountSpark.fromJson,
      );
}

/// How far back the line goes. `fy` is the Indian financial year, April to
/// March — the one that matters here.
enum NetWorthRange { oneMonth, sixMonths, fy, all }

final netWorthRangeWire = WireEnum<NetWorthRange>('net worth range', const {
  '1m': NetWorthRange.oneMonth,
  '6m': NetWorthRange.sixMonths,
  'fy': NetWorthRange.fy,
  'all': NetWorthRange.all,
});

class NetWorthNow {
  const NetWorthNow({
    required this.day,
    required this.assetsPaise,
    required this.liabilitiesPaise,
    required this.netWorthPaise,
  });

  /// 'yyyy-MM-dd' the reading is as of.
  final String day;
  final int assetsPaise;

  /// Positive paise owed.
  final int liabilitiesPaise;

  /// Assets minus liabilities; negative is a real answer.
  final int netWorthPaise;

  factory NetWorthNow.fromJson(Map<String, dynamic> json) => NetWorthNow(
        day: json.day('day'),
        assetsPaise: json.whole('assets_paise'),
        liabilitiesPaise: json.whole('liabilities_paise'),
        netWorthPaise: json.whole('net_worth_paise'),
      );
}

class SeriesPoint {
  const SeriesPoint({required this.date, required this.valuePaise});

  /// 'yyyy-MM-dd'.
  final String date;
  final int valuePaise;

  factory SeriesPoint.fromJson(Map<String, dynamic> json) => SeriesPoint(
        date: json.day('date'),
        valuePaise: json.whole('value_paise'),
      );
}

/// The line plus the few numbers worth saying out loud beside it. Every
/// nullable field here is null when there is no history to draw on — silence
/// rather than a zero pretending to be a reading.
class SeriesOut {
  const SeriesOut({
    required this.range,
    required this.points,
    required this.firstPaise,
    required this.lastPaise,
    required this.deltaPaise,
    required this.peakDate,
    required this.peakPaise,
    required this.allTimePeakDate,
    required this.allTimePeakPaise,
  });

  /// Echoed back as the wire spelling — '1m', '6m', 'fy', 'all'.
  final String range;
  final List<SeriesPoint> points;
  final int? firstPaise;
  final int? lastPaise;

  /// Last minus first; zero when there is nothing to compare.
  final int deltaPaise;

  /// 'yyyy-MM-dd' of the high inside this range.
  final String? peakDate;
  final int? peakPaise;

  /// The high across all of it, however far back the window reaches.
  final String? allTimePeakDate;
  final int? allTimePeakPaise;

  factory SeriesOut.fromJson(Map<String, dynamic> json) => SeriesOut(
        range: json.text('range'),
        points: json.objects('points', SeriesPoint.fromJson),
        firstPaise: json.wholeOrNull('first_paise'),
        lastPaise: json.wholeOrNull('last_paise'),
        deltaPaise: json.whole('delta_paise'),
        peakDate: json.dayOrNull('peak_date'),
        peakPaise: json.wholeOrNull('peak_paise'),
        allTimePeakDate: json.dayOrNull('all_time_peak_date'),
        allTimePeakPaise: json.wholeOrNull('all_time_peak_paise'),
      );
}

/// One Worth row: the balance, when it was last confirmed, and the memory
/// behind it.
class AccountSpark {
  const AccountSpark({
    required this.accountId,
    required this.name,
    required this.kind,
    required this.balancePaise,
    required this.asOf,
    required this.points,
    required this.readings,
    required this.lowPaise,
    required this.highPaise,
  });

  final String accountId;
  final String name;
  final AccountKind kind;
  final int balancePaise;

  /// When the balance was last confirmed by hand — null drives the "never
  /// checked" cue, not a stale one.
  final DateTime? asOf;
  final List<SeriesPoint> points;

  /// How many readings the sparkline is drawn from — the weight of it.
  final int readings;

  /// Null with fewer than two readings: a range needs something to range over.
  final int? lowPaise;
  final int? highPaise;

  factory AccountSpark.fromJson(Map<String, dynamic> json) => AccountSpark(
        accountId: json.text('account_id'),
        name: json.text('name'),
        kind: json.enumAt('kind', accountKindWire),
        balancePaise: json.whole('balance_paise'),
        asOf: json.instantOrNull('as_of'),
        points: json.objects('points', SeriesPoint.fromJson),
        readings: json.whole('readings'),
        lowPaise: json.wholeOrNull('low_paise'),
        highPaise: json.wholeOrNull('high_paise'),
      );
}
