import '../api_client.dart';
import 'wire.dart';

/// The once-daily close. Sealing a day is a ritual, not a ledger fact: both
/// directions are idempotent and neither leaves a trace, because taking it
/// back is allowed to cost nothing.
class SealsApi {
  const SealsApi(this._c);

  final BbxClient _c;

  /// Days already closed inside an inclusive 'yyyy-MM-dd' window.
  Future<List<SealOut>> between({
    required String fromDay,
    required String toDay,
  }) async =>
      wireList(
        await _c.get('/v1/seals', {'from_day': fromDay, 'to_day': toDay}),
        SealOut.fromJson,
      );

  Future<SealOut> seal(String day) async =>
      SealOut.fromJson(wireObject(await _c.put('/v1/seals/$day', const {})));

  Future<void> unseal(String day) => _c.delete('/v1/seals/$day');
}

class SealOut {
  const SealOut({required this.date, required this.sealedAt});

  /// 'yyyy-MM-dd' — the day that was closed.
  final String date;

  /// When it was closed.
  final DateTime sealedAt;

  factory SealOut.fromJson(Map<String, dynamic> json) => SealOut(
        date: json.day('date'),
        sealedAt: json.instant('sealed_at'),
      );
}
