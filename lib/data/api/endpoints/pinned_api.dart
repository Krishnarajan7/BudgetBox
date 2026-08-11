import '../api_client.dart';
import 'txns_api.dart';
import 'wire.dart';

/// One-tap repeats: the chai, the auto, the mess lunch. The only path that
/// beats five seconds.
class PinnedApi {
  const PinnedApi(this._c);

  final BbxClient _c;

  Future<List<PinnedOut>> list() async =>
      wireList(await _c.get('/v1/pinned'), PinnedOut.fromJson);

  /// The pins plus the repeats that have earned one and don't have it yet —
  /// the board offers, it doesn't nag.
  Future<PinnedBoard> board() async =>
      PinnedBoard.fromJson(wireObject(await _c.get('/v1/pinned/board')));

  Future<PinnedOut> upsert(String id, PinnedIn body) async =>
      PinnedOut.fromJson(
        wireObject(await _c.put('/v1/pinned/$id', body.toJson())),
      );

  Future<void> delete(String id) => _c.delete('/v1/pinned/$id');

  /// Tap a pin, get an entry. [body] only exists to backdate it.
  Future<TxnOut> stamp(String id, {StampIn? body}) async => TxnOut.fromJson(
        wireObject(await _c.post('/v1/pinned/$id/stamp', body?.toJson())),
      );
}

class PinnedOut {
  const PinnedOut({
    required this.id,
    required this.title,
    required this.amountPaise,
    required this.categoryId,
    required this.accountId,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final int amountPaise;
  final String categoryId;
  final String accountId;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PinnedOut.fromJson(Map<String, dynamic> json) => PinnedOut(
        id: json.text('id'),
        title: json.text('title'),
        amountPaise: json.whole('amount_paise'),
        categoryId: json.text('category_id'),
        accountId: json.text('account_id'),
        sortOrder: json.whole('sort_order'),
        createdAt: json.instant('created_at'),
        updatedAt: json.instant('updated_at'),
      );
}

class PinnedIn {
  const PinnedIn({
    required this.title,
    required this.amountPaise,
    required this.categoryId,
    required this.accountId,
    this.sortOrder = 0,
  });

  final String title;
  final int amountPaise;
  final String categoryId;
  final String accountId;
  final int sortOrder;

  Map<String, dynamic> toJson() => {
        'title': title,
        'amount_paise': amountPaise,
        'category_id': categoryId,
        'account_id': accountId,
        'sort_order': sortOrder,
      };
}

/// Backdating a stamp. Left empty it means now.
class StampIn {
  const StampIn({this.at});

  final DateTime? at;

  Map<String, dynamic> toJson() =>
      (WireBody()..maybe('at', wireInstantOrNull(at))).build();
}

class PinnedBoard {
  const PinnedBoard({required this.items, required this.suggestions});

  final List<PinnedUse> items;
  final List<PinnedSuggestion> suggestions;

  factory PinnedBoard.fromJson(Map<String, dynamic> json) => PinnedBoard(
        items: json.objects('items', PinnedUse.fromJson),
        suggestions: json.objects('suggestions', PinnedSuggestion.fromJson),
      );
}

/// A pin and how often it has actually been stamped — 'stamped 14 times'.
class PinnedUse {
  const PinnedUse({
    required this.pinned,
    required this.useCount,
    required this.lastUsedAt,
  });

  final PinnedOut pinned;
  final int useCount;

  /// Null for a pin that has never been used.
  final DateTime? lastUsedAt;

  factory PinnedUse.fromJson(Map<String, dynamic> json) => PinnedUse(
        pinned: json.object('pinned', PinnedOut.fromJson),
        useCount: json.whole('use_count'),
        lastUsedAt: json.instantOrNull('last_used_at'),
      );
}

/// A repeat that has earned a pin and doesn't have one yet.
class PinnedSuggestion {
  const PinnedSuggestion({
    required this.title,
    required this.amountPaise,
    required this.categoryId,
    required this.accountId,
    required this.count,
  });

  final String title;
  final int amountPaise;
  final String categoryId;
  final String accountId;

  /// How many times it has been written by hand — the case for pinning it.
  final int count;

  factory PinnedSuggestion.fromJson(Map<String, dynamic> json) =>
      PinnedSuggestion(
        title: json.text('title'),
        amountPaise: json.whole('amount_paise'),
        categoryId: json.text('category_id'),
        accountId: json.text('account_id'),
        count: json.whole('count'),
      );
}
