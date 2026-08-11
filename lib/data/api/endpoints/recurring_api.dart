import '../../tables.dart';
import '../api_client.dart';
import 'txns_api.dart';
import 'wire.dart';

/// The charges that arrive whether or not anyone remembers them.
///
/// The daily job materialises these into real transactions and the catch-up is
/// idempotent, so a week of downtime self-heals rather than double-charging.
class RecurringApi {
  const RecurringApi(this._c);

  final BbxClient _c;

  Future<List<RecurringOut>> list({bool includeInactive = false}) async =>
      wireList(
        await _c.get('/v1/recurring', {'include_inactive': includeInactive}),
        RecurringOut.fromJson,
      );

  Future<RecurringOut> upsert(String id, RecurringIn body) async =>
      RecurringOut.fromJson(
        wireObject(await _c.put('/v1/recurring/$id', body.toJson())),
      );

  Future<RecurringOut> patch(String id, RecurringPatch body) async =>
      RecurringOut.fromJson(
        wireObject(await _c.patch('/v1/recurring/$id', body.toJson())),
      );

  /// Stops future charges without erasing the ones already written — cancelling
  /// a subscription should not rewrite last year.
  Future<RecurringOut> deactivate(String id) async => RecurringOut.fromJson(
        wireObject(await _c.delete('/v1/recurring/$id')),
      );

  /// What is due between now and [until] ('yyyy-MM-dd'), with the yearly
  /// weight of it all — the number that makes a ₹149 subscription feel real.
  Future<UpcomingOut> upcoming({String? until}) async => UpcomingOut.fromJson(
        wireObject(await _c.get('/v1/recurring/upcoming', {'until': until})),
      );

  /// Pay one by hand, retry-safe: [txnId] is the phone's uuid7, so a repeated
  /// attempt lands on the same transaction rather than a second one.
  Future<TxnOut> pay(
    String recurringId,
    String txnId,
    RecurringPaymentIn body,
  ) async =>
      TxnOut.fromJson(
        wireObject(
          await _c.put(
            '/v1/recurring/$recurringId/payments/$txnId',
            body.toJson(),
          ),
        ),
      );
}

class RecurringOut {
  const RecurringOut({
    required this.id,
    required this.title,
    required this.amountPaise,
    required this.kind,
    required this.accountId,
    required this.categoryId,
    required this.everyMonths,
    required this.dayOfMonth,
    required this.nextDue,
    required this.lastMaterializedDue,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final int amountPaise;
  final RecurringKind kind;
  final String accountId;
  final String? categoryId;

  /// 1 is monthly, 12 is yearly.
  final int everyMonths;

  /// Clamped to the month's length, so the 31st still lands in February.
  final int dayOfMonth;

  /// 'yyyy-MM-dd'.
  final String nextDue;

  /// The last due date the job actually wrote a transaction for; null until
  /// the first one lands.
  final String? lastMaterializedDue;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory RecurringOut.fromJson(Map<String, dynamic> json) => RecurringOut(
        id: json.text('id'),
        title: json.text('title'),
        amountPaise: json.whole('amount_paise'),
        kind: json.enumAt('kind', recurringKindWire),
        accountId: json.text('account_id'),
        categoryId: json.textOrNull('category_id'),
        everyMonths: json.whole('every_months'),
        dayOfMonth: json.whole('day_of_month'),
        nextDue: json.day('next_due'),
        lastMaterializedDue: json.dayOrNull('last_materialized_due'),
        active: json.flag('active'),
        createdAt: json.instant('created_at'),
        updatedAt: json.instant('updated_at'),
      );
}

class RecurringIn {
  const RecurringIn({
    required this.title,
    required this.amountPaise,
    required this.kind,
    required this.accountId,
    required this.dayOfMonth,
    this.categoryId,
    this.everyMonths = 1,
    this.nextDue,
    this.active = true,
  });

  final String title;
  final int amountPaise;
  final RecurringKind kind;
  final String accountId;
  final int dayOfMonth;
  final String? categoryId;
  final int everyMonths;

  /// 'yyyy-MM-dd'. Left null, the server works out the next landing itself.
  final String? nextDue;
  final bool active;

  Map<String, dynamic> toJson() => {
        'title': title,
        'amount_paise': amountPaise,
        'kind': recurringKindWire.toWire(kind),
        'account_id': accountId,
        'day_of_month': dayOfMonth,
        'category_id': categoryId,
        'every_months': everyMonths,
        'next_due': nextDue,
        'active': active,
      };
}

/// `kind` is fixed once set. Only `category_id` can genuinely be emptied, so
/// only it takes an [Opt]; the rest read null as "leave it alone".
class RecurringPatch {
  const RecurringPatch({
    this.title,
    this.amountPaise,
    this.accountId,
    this.categoryId,
    this.everyMonths,
    this.dayOfMonth,
    this.nextDue,
    this.active,
  });

  final String? title;
  final int? amountPaise;
  final String? accountId;
  final Opt<String?>? categoryId;
  final int? everyMonths;
  final int? dayOfMonth;

  /// 'yyyy-MM-dd'.
  final String? nextDue;
  final bool? active;

  Map<String, dynamic> toJson() => (WireBody()
        ..maybe('title', title)
        ..maybe('amount_paise', amountPaise)
        ..maybe('account_id', accountId)
        ..opt('category_id', categoryId)
        ..maybe('every_months', everyMonths)
        ..maybe('day_of_month', dayOfMonth)
        ..maybe('next_due', nextDue)
        ..maybe('active', active))
      .build();
}

/// A charge with a date on it. [isBill] separates the unavoidable from the
/// merely subscribed.
class DueItem {
  const DueItem({
    required this.recurring,
    required this.due,
    required this.isBill,
  });

  final RecurringOut recurring;

  /// 'yyyy-MM-dd'.
  final String due;
  final bool isBill;

  factory DueItem.fromJson(Map<String, dynamic> json) => DueItem(
        recurring: json.object('recurring', RecurringOut.fromJson),
        due: json.day('due'),
        isBill: json.flag('is_bill'),
      );
}

/// What is coming, and what it all weighs over a year.
class UpcomingOut {
  const UpcomingOut({
    required this.items,
    required this.committedMonthlyPaise,
    required this.committedUnpaidPaise,
    required this.yearlyPaise,
    required this.yearlyBillPaise,
    required this.yearlySubscriptionPaise,
  });

  final List<DueItem> items;

  /// Everything active, normalised to a month.
  final int committedMonthlyPaise;

  /// Of that, what has not been paid yet this cycle.
  final int committedUnpaidPaise;
  final int yearlyPaise;
  final int yearlyBillPaise;
  final int yearlySubscriptionPaise;

  factory UpcomingOut.fromJson(Map<String, dynamic> json) => UpcomingOut(
        items: json.objects('items', DueItem.fromJson),
        committedMonthlyPaise: json.whole('committed_monthly_paise'),
        committedUnpaidPaise: json.whole('committed_unpaid_paise'),
        yearlyPaise: json.whole('yearly_paise'),
        yearlyBillPaise: json.whole('yearly_bill_paise'),
        yearlySubscriptionPaise: json.whole('yearly_subscription_paise'),
      );
}

/// A hand-made payment. Everything is optional: left alone it pays the
/// recurring's own amount, now.
class RecurringPaymentIn {
  const RecurringPaymentIn({this.amountPaise, this.at, this.note});

  /// Override for the month the electricity bill was unusual.
  final int? amountPaise;
  final DateTime? at;
  final String? note;

  Map<String, dynamic> toJson() => (WireBody()
        ..maybe('amount_paise', amountPaise)
        ..maybe('at', wireInstantOrNull(at))
        ..maybe('note', note))
      .build();
}
