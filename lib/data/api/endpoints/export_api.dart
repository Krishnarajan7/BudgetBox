import '../api_client.dart';

/// 'My data leaves whenever I want' — the whole ledger as CSV, names resolved,
/// dates in IST.
///
/// This is the one endpoint that does not answer in JSON, so it cannot come
/// back through the shared client: `text/csv` would decode to nothing. What
/// this class hands over instead is a request anyone can make — the address and
/// the token — for whatever actually does the download or the share sheet.
class ExportApi {
  const ExportApi(this._c);

  final BbxClient _c;

  /// Where the CSV lives.
  Uri txnsCsvUri() => _c.config.resolve('/v1/export/txns.csv');

  /// What it needs to be asked for. The same bearer token the client uses.
  Map<String, String> get headers => {
        'authorization': 'Bearer ${_c.config.token}',
        'accept': 'text/csv',
      };

  /// The filename the server suggests, for a share sheet that wants one.
  static const filename = 'budgetbox-txns.csv';
}
