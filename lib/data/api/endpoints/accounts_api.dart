import '../../tables.dart';
import '../api_client.dart';
import 'wire.dart';

/// Where the money sits. Balances are **derived** server-side — the latest
/// confirmed anchor plus every signed transaction after it — so the phone
/// never posts a balance, it posts an anchor and reads the answer.
class AccountsApi {
  const AccountsApi(this._c);

  final BbxClient _c;

  Future<List<AccountOut>> list({bool includeArchived = false}) async =>
      wireList(
        await _c.get('/v1/accounts', {'include_archived': includeArchived}),
        AccountOut.fromJson,
      );

  Future<AccountOut> get(String id) async =>
      AccountOut.fromJson(wireObject(await _c.get('/v1/accounts/$id')));

  Future<AccountOut> upsert(String id, AccountIn body) async =>
      AccountOut.fromJson(
        wireObject(await _c.put('/v1/accounts/$id', body.toJson())),
      );

  Future<AccountOut> patch(String id, AccountPatch body) async =>
      AccountOut.fromJson(
        wireObject(await _c.patch('/v1/accounts/$id', body.toJson())),
      );

  /// "This is what the bank actually says today." Everything after it is
  /// re-derived, so a mis-typed transaction never leaves a permanent drift.
  Future<AccountOut> addAnchor(String id, AnchorIn body) async =>
      AccountOut.fromJson(
        wireObject(await _c.post('/v1/accounts/$id/anchors', body.toJson())),
      );
}

class AccountOut {
  const AccountOut({
    required this.id,
    required this.name,
    required this.kind,
    required this.balancePaise,
    required this.asOf,
    required this.sortOrder,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final AccountKind kind;
  final int balancePaise;

  /// When the balance was last confirmed by hand — null until the first
  /// anchor, which is what makes a fresh account read as unconfirmed rather
  /// than stale.
  final DateTime? asOf;
  final int sortOrder;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AccountOut.fromJson(Map<String, dynamic> json) => AccountOut(
        id: json.text('id'),
        name: json.text('name'),
        kind: json.enumAt('kind', accountKindWire),
        balancePaise: json.whole('balance_paise'),
        asOf: json.instantOrNull('as_of'),
        sortOrder: json.whole('sort_order'),
        archived: json.flag('archived'),
        createdAt: json.instant('created_at'),
        updatedAt: json.instant('updated_at'),
      );
}

class AccountIn {
  const AccountIn({
    required this.name,
    required this.kind,
    this.sortOrder = 0,
  });

  final String name;
  final AccountKind kind;
  final int sortOrder;

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': accountKindWire.toWire(kind),
        'sort_order': sortOrder,
      };
}

/// Every column here is `NOT NULL`, so a null simply means "leave it alone".
class AccountPatch {
  const AccountPatch({this.name, this.kind, this.sortOrder, this.archived});

  final String? name;
  final AccountKind? kind;
  final int? sortOrder;
  final bool? archived;

  Map<String, dynamic> toJson() => (WireBody()
        ..maybe('name', name)
        ..maybe('kind', accountKindWire.toWireOrNull(kind))
        ..maybe('sort_order', sortOrder)
        ..maybe('archived', archived))
      .build();
}

/// A balance the user has confirmed. [at] may be backdated — anchoring last
/// Sunday's statement is a normal thing to do.
class AnchorIn {
  const AnchorIn({required this.balancePaise, this.at});

  final int balancePaise;
  final DateTime? at;

  Map<String, dynamic> toJson() => (WireBody()
        ..set('balance_paise', balancePaise)
        ..maybe('at', wireInstantOrNull(at)))
      .build();
}
