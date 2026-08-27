import '../api_client.dart';
import 'wire.dart';

/// The folio: money moved out of a bank and into funds.
///
/// Buying a fund is not spending — the money changes shape, not owner — so
/// every contribution crosses the wire as a transfer, exactly like a loan
/// going onto the slate. What makes a fund different is that it moves on its
/// own: a holding carries **units**, and units times the latest AMFI NAV is
/// what it is worth today. Cost and value are never the same number, and the
/// gap between them is the only return figure this book shows.
class FolioApi {
  const FolioApi(this._c);

  final BbxClient _c;

  Future<FolioOverview> overview() async =>
      FolioOverview.fromJson(wireObject(await _c.get('/v1/folio/overview')));

  Future<List<Fund>> funds() async =>
      wireList(await _c.get('/v1/folio/funds'), Fund.fromJson);

  Future<Fund> fund(String id) async =>
      Fund.fromJson(wireObject(await _c.get('/v1/folio/funds/$id')));

  Future<List<FolioEntry>> entries(String id) async =>
      wireList(await _c.get('/v1/folio/funds/$id/entries'), FolioEntry.fromJson);

  /// The two lines the chart draws.
  Future<List<FolioPoint>> series({int days = 180}) async => wireList(
    await _c.get('/v1/folio/series', {'days': '$days'}),
    FolioPoint.fromJson,
  );

  /// Live search over AMFI's daily file — every open-ended Indian scheme.
  Future<List<Scheme>> schemes(String query) async => wireList(
    await _c.get('/v1/folio/schemes', {'query': query}),
    Scheme.fromJson,
  );

  Future<Fund> addFund(String id, FundIn body) async =>
      Fund.fromJson(wireObject(await _c.put('/v1/folio/funds/$id', body.toJson())));

  Future<Fund> patchFund(String id, FundPatch body) async => Fund.fromJson(
    wireObject(await _c.patch('/v1/folio/funds/$id', body.toJson())),
  );

  /// Stamp money in. [kind] is 'sip' or 'lumpsum'.
  Future<FolioEntry> contribute(String id, FolioMoveIn body) async =>
      FolioEntry.fromJson(
        wireObject(
          await _c.post('/v1/folio/funds/$id/contribute', body.toJson()),
        ),
      );

  Future<FolioEntry> redeem(String id, FolioMoveIn body) async =>
      FolioEntry.fromJson(
        wireObject(await _c.post('/v1/folio/funds/$id/redeem', body.toJson())),
      );

  /// The hand-given worth of a fund AMFI does not price.
  Future<Fund> setValue(String id, int valuePaise) async => Fund.fromJson(
    wireObject(
      await _c.post('/v1/folio/funds/$id/value', {'value_paise': valuePaise}),
    ),
  );

  /// Pull today's NAVs now rather than waiting for the nightly job.
  Future<FolioOverview> refresh() async =>
      FolioOverview.fromJson(wireObject(await _c.post('/v1/folio/refresh')));
}

enum FolioEntryKind { sip, lumpsum, redeem }

final folioEntryKindWire = WireEnum<FolioEntryKind>('folio entry kind', const {
  'sip': FolioEntryKind.sip,
  'lumpsum': FolioEntryKind.lumpsum,
  'redeem': FolioEntryKind.redeem,
});

class FolioOverview {
  const FolioOverview({
    required this.costPaise,
    required this.valuePaise,
    required this.gainPaise,
    required this.returnRatio,
    required this.funds,
    required this.monthPaise,
    required this.pricedUpto,
    required this.unpricedFunds,
  });

  /// What was actually paid in. Moves only when money moves.
  final int costPaise;

  /// units × latest NAV. Moves on its own.
  final int valuePaise;
  final int gainPaise;
  final double? returnRatio;
  final int funds;

  /// This month's contributions.
  final int monthPaise;

  /// The oldest NAV among priced funds — how stale the worth figure is.
  final String? pricedUpto;
  final int unpricedFunds;

  bool get up => gainPaise >= 0;

  factory FolioOverview.fromJson(Map<String, dynamic> json) => FolioOverview(
    costPaise: json.whole('cost_paise'),
    valuePaise: json.whole('value_paise'),
    gainPaise: json.whole('gain_paise'),
    returnRatio: json.realOrNull('return_ratio'),
    funds: json.whole('funds'),
    monthPaise: json.whole('month_paise'),
    pricedUpto: json.dayOrNull('priced_upto'),
    unpricedFunds: json.whole('unpriced_funds'),
  );
}

class Fund {
  const Fund({
    required this.id,
    required this.name,
    required this.schemeCode,
    required this.note,
    required this.archived,
    required this.costPaise,
    required this.valuePaise,
    required this.gainPaise,
    required this.returnRatio,
    required this.units,
    required this.nav,
    required this.navDate,
    required this.priced,
    required this.entries,
    required this.sipCount,
    required this.sipPaise,
    required this.firstAt,
    required this.lastAt,
  });

  final String id;
  final String name;
  final String? schemeCode;
  final String? note;
  final bool archived;
  final int costPaise;
  final int valuePaise;
  final int gainPaise;
  final double? returnRatio;
  final double units;
  final double? nav;
  final String? navDate;

  /// True when AMFI prices this fund; false when the figure was typed in.
  final bool priced;
  final int entries;
  final int sipCount;
  final int sipPaise;
  final DateTime? firstAt;
  final DateTime? lastAt;

  bool get up => gainPaise >= 0;

  factory Fund.fromJson(Map<String, dynamic> json) => Fund(
    id: json.text('id'),
    name: json.text('name'),
    schemeCode: json.textOrNull('scheme_code'),
    note: json.textOrNull('note'),
    archived: json.flag('archived'),
    costPaise: json.whole('cost_paise'),
    valuePaise: json.whole('value_paise'),
    gainPaise: json.whole('gain_paise'),
    returnRatio: json.realOrNull('return_ratio'),
    units: json.real('units'),
    nav: json.realOrNull('nav'),
    navDate: json.dayOrNull('nav_date'),
    priced: json.flag('priced'),
    entries: json.whole('entries'),
    sipCount: json.whole('sip_count'),
    sipPaise: json.whole('sip_paise'),
    firstAt: json.instantOrNull('first_at'),
    lastAt: json.instantOrNull('last_at'),
  );
}

class FolioEntry {
  const FolioEntry({
    required this.id,
    required this.fundId,
    required this.kind,
    required this.amountPaise,
    required this.units,
    required this.nav,
    required this.at,
    required this.note,
  });

  final String id;
  final String fundId;
  final FolioEntryKind kind;
  final int amountPaise;

  /// What the money actually bought at that day's price.
  final double? units;
  final double? nav;
  final DateTime at;
  final String? note;

  factory FolioEntry.fromJson(Map<String, dynamic> json) => FolioEntry(
    id: json.text('id'),
    fundId: json.text('fund_id'),
    kind: json.enumAt('kind', folioEntryKindWire),
    amountPaise: json.whole('amount_paise'),
    units: json.realOrNull('units'),
    nav: json.realOrNull('nav'),
    at: json.instant('at'),
    note: json.textOrNull('note'),
  );
}

/// One day of the folio's two lines.
class FolioPoint {
  const FolioPoint({
    required this.date,
    required this.costPaise,
    required this.valuePaise,
  });

  /// 'yyyy-MM-dd'.
  final String date;
  final int costPaise;
  final int valuePaise;

  factory FolioPoint.fromJson(Map<String, dynamic> json) => FolioPoint(
    date: json.day('date'),
    costPaise: json.whole('cost_paise'),
    valuePaise: json.whole('value_paise'),
  );
}

/// A row of AMFI's file, for the search field.
class Scheme {
  const Scheme({
    required this.code,
    required this.label,
    required this.nav,
    required this.navDate,
  });

  final String code;
  final String label;
  final double nav;
  final String navDate;

  factory Scheme.fromJson(Map<String, dynamic> json) => Scheme(
    code: json.text('code'),
    label: json.text('label'),
    nav: json.real('nav'),
    navDate: json.day('nav_date'),
  );
}

class FundIn {
  const FundIn({required this.name, this.schemeCode, this.note});

  final String name;
  final String? schemeCode;
  final String? note;

  Map<String, dynamic> toJson() => {
    'name': name,
    'scheme_code': schemeCode,
    'note': note,
  };
}

class FundPatch {
  const FundPatch({this.name, this.archived, this.note});

  final String? name;
  final bool? archived;
  final Opt<String?>? note;

  Map<String, dynamic> toJson() => (WireBody()
        ..maybe('name', name)
        ..maybe('archived', archived)
        ..opt('note', note))
      .build();
}

class FolioMoveIn {
  const FolioMoveIn({
    required this.amountPaise,
    required this.accountId,
    this.kind = FolioEntryKind.sip,
    this.at,
    this.note,
  });

  final int amountPaise;
  final String accountId;
  final FolioEntryKind kind;

  /// Null means now — backdating is how an old SIP gets onto the folio.
  final DateTime? at;
  final String? note;

  Map<String, dynamic> toJson() => {
    'amount_paise': amountPaise,
    'account_id': accountId,
    'kind': folioEntryKindWire.toWire(kind),
    if (at != null) 'at': wireInstant(at!),
    'note': ?note,
  };
}
