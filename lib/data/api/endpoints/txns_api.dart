import '../../tables.dart';
import '../api_client.dart';
import 'wire.dart';

/// The ledger itself. Writes are idempotent `PUT`s against a uuid7 the phone
/// mints, so a queued entry can be retried blindly on the far side of a tunnel.
class TxnsApi {
  const TxnsApi(this._c);

  final BbxClient _c;

  /// One page of the book, newest first. [fromDay]/[toDay] are 'yyyy-MM-dd'
  /// IST days, inclusive; [cursor] comes from the previous page.
  Future<TxnPage> list({
    String? fromDay,
    String? toDay,
    String? categoryId,
    String? accountId,
    TxnType? type,
    String? q,
    int limit = 100,
    String? cursor,
  }) async =>
      TxnPage.fromJson(
        wireObject(
          await _c.get('/v1/txns', {
            'from_day': fromDay,
            'to_day': toDay,
            'category_id': categoryId,
            'account_id': accountId,
            'type': txnTypeWire.toWireOrNull(type),
            'q': q,
            'limit': limit,
            'cursor': cursor,
          }),
        ),
      );

  Future<TxnOut> get(String id) async =>
      TxnOut.fromJson(wireObject(await _c.get('/v1/txns/$id')));

  Future<TxnOut> upsert(String id, TxnIn body) async =>
      TxnOut.fromJson(wireObject(await _c.put('/v1/txns/$id', body.toJson())));

  Future<TxnOut> patch(String id, TxnPatch body) async => TxnOut.fromJson(
        wireObject(await _c.patch('/v1/txns/$id', body.toJson())),
      );

  Future<void> delete(String id) => _c.delete('/v1/txns/$id');

  /// 'usually ₹40' — the figures this category keeps being written for, so the
  /// keypad can offer them instead of asking.
  Future<List<RecentAmount>> recentAmounts({
    required String categoryId,
    int limit = 3,
  }) async =>
      wireList(
        await _c.get('/v1/txns/recent-amounts', {
          'category_id': categoryId,
          'limit': limit,
        }),
        RecentAmount.fromJson,
      );

  /// Title autocomplete that remembers which category and account the title
  /// usually lands in — three taps saved, not one.
  Future<List<TitleSuggestion>> suggest({
    required String q,
    int limit = 6,
  }) async =>
      wireList(
        await _c.get('/v1/txns/suggest', {'q': q, 'limit': limit}),
        TitleSuggestion.fromJson,
      );
}

class TxnOut {
  const TxnOut({
    required this.id,
    required this.amountPaise,
    required this.type,
    required this.title,
    required this.at,
    required this.accountId,
    required this.categoryId,
    required this.toAccountId,
    required this.goalId,
    required this.recurringId,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Always positive paise; [type] carries the sign.
  final int amountPaise;
  final TxnType type;
  final String title;

  /// When it happened — an instant, not a day.
  final DateTime at;
  final String accountId;
  final String? categoryId;

  /// Transfer destination; null for expense and income.
  final String? toAccountId;
  final String? goalId;

  /// Set when the daily job materialised this from a recurring.
  final String? recurringId;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TxnOut.fromJson(Map<String, dynamic> json) => TxnOut(
        id: json.text('id'),
        amountPaise: json.whole('amount_paise'),
        type: json.enumAt('type', txnTypeWire),
        title: json.text('title'),
        at: json.instant('at'),
        accountId: json.text('account_id'),
        categoryId: json.textOrNull('category_id'),
        toAccountId: json.textOrNull('to_account_id'),
        goalId: json.textOrNull('goal_id'),
        recurringId: json.textOrNull('recurring_id'),
        note: json.textOrNull('note'),
        createdAt: json.instant('created_at'),
        updatedAt: json.instant('updated_at'),
      );
}

class TxnIn {
  const TxnIn({
    required this.amountPaise,
    required this.type,
    required this.title,
    required this.at,
    required this.accountId,
    this.categoryId,
    this.toAccountId,
    this.goalId,
    this.note,
  });

  final int amountPaise;
  final TxnType type;
  final String title;
  final DateTime at;
  final String accountId;
  final String? categoryId;
  final String? toAccountId;
  final String? goalId;
  final String? note;

  Map<String, dynamic> toJson() => {
        'amount_paise': amountPaise,
        'type': txnTypeWire.toWire(type),
        'title': title,
        'at': wireInstant(at),
        'account_id': accountId,
        'category_id': categoryId,
        'to_account_id': toAccountId,
        'goal_id': goalId,
        'note': note,
      };
}

/// The columns that can genuinely be emptied take an [Opt]; the rest read
/// null as "leave it alone". See [Opt] for why.
class TxnPatch {
  const TxnPatch({
    this.amountPaise,
    this.type,
    this.title,
    this.at,
    this.accountId,
    this.categoryId,
    this.toAccountId,
    this.goalId,
    this.note,
  });

  final int? amountPaise;
  final TxnType? type;
  final String? title;
  final DateTime? at;
  final String? accountId;
  final Opt<String?>? categoryId;
  final Opt<String?>? toAccountId;
  final Opt<String?>? goalId;
  final Opt<String?>? note;

  Map<String, dynamic> toJson() => (WireBody()
        ..maybe('amount_paise', amountPaise)
        ..maybe('type', txnTypeWire.toWireOrNull(type))
        ..maybe('title', title)
        ..maybe('at', wireInstantOrNull(at))
        ..maybe('account_id', accountId)
        ..opt('category_id', categoryId)
        ..opt('to_account_id', toAccountId)
        ..opt('goal_id', goalId)
        ..opt('note', note))
      .build();
}

/// A page of the book. [nextCursor] is null once there is nothing older.
class TxnPage {
  const TxnPage({required this.items, required this.nextCursor});

  final List<TxnOut> items;
  final String? nextCursor;

  factory TxnPage.fromJson(Map<String, dynamic> json) => TxnPage(
        items: json.objects('items', TxnOut.fromJson),
        nextCursor: json.textOrNull('next_cursor'),
      );
}

/// An amount this category keeps being written for, and how often.
class RecentAmount {
  const RecentAmount({required this.amountPaise, required this.count});

  final int amountPaise;
  final int count;

  factory RecentAmount.fromJson(Map<String, dynamic> json) => RecentAmount(
        amountPaise: json.whole('amount_paise'),
        count: json.whole('count'),
      );
}

/// A remembered title, carrying the category and account it usually belongs
/// to. Either may be null when the title has been written both ways.
class TitleSuggestion {
  const TitleSuggestion({
    required this.title,
    required this.categoryId,
    required this.accountId,
  });

  final String title;
  final String? categoryId;
  final String? accountId;

  factory TitleSuggestion.fromJson(Map<String, dynamic> json) =>
      TitleSuggestion(
        title: json.text('title'),
        categoryId: json.textOrNull('category_id'),
        accountId: json.textOrNull('account_id'),
      );
}
