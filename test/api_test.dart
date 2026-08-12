import 'dart:convert';

import 'package:budgetbox/data/api/api_client.dart';
import 'package:budgetbox/data/api/api_config.dart';
import 'package:budgetbox/data/api/endpoints/endpoints.dart';
import 'package:budgetbox/data/tables.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The endpoint layer, tested against payloads copied from the shapes in
/// `backend/openapi.json`. Nothing here touches the network: every call is
/// answered by a fake client, so what is under test is purely the translation
/// — snake_case to Dart, paise to int, days to strings, and a loud failure
/// when the wire says something unrecognisable.
void main() {
  const config = BbxConfig(baseUrl: 'http://ledger.test', token: 'bbx_test');

  /// A client that answers every request with [body], recording what was
  /// asked. A null [body] answers 204, the way a delete does.
  (BbxClient, List<http.Request>) fakeClient(Object? body) {
    final seen = <http.Request>[];
    final mock = MockClient((request) async {
      seen.add(request);
      if (body == null) return http.Response('', 204);
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return (BbxClient(config, inner: mock), seen);
  }

  // A realistic TxnOut, field for field as the server writes it.
  Map<String, dynamic> txnPayload() => {
    'id': '019810f0-4a3b-7c21-9d55-2b1c4e8f0011',
    'amount_paise': 4250,
    'type': 'expense',
    'title': 'Chai + vada pav',
    'at': '2026-07-31T13:42:00+05:30',
    'account_id': '019810f0-0000-7000-8000-000000000001',
    'category_id': '019810f0-0000-7000-8000-0000000000c1',
    'to_account_id': null,
    'goal_id': null,
    'recurring_id': null,
    'note': null,
    'created_at': '2026-07-31T13:42:01.123456Z',
    'updated_at': '2026-07-31T13:42:01.123456Z',
  };

  group('DTOs read the wire', () {
    test('TxnOut maps snake_case onto Dart names', () {
      final txn = TxnOut.fromJson(txnPayload());

      expect(txn.id, '019810f0-4a3b-7c21-9d55-2b1c4e8f0011');
      expect(txn.title, 'Chai + vada pav');
      expect(txn.type, TxnType.expense);
      expect(txn.accountId, '019810f0-0000-7000-8000-000000000001');
      expect(txn.categoryId, '019810f0-0000-7000-8000-0000000000c1');
      // An instant, in local time, pointing at the same moment.
      expect(
        txn.at.toUtc(),
        DateTime.utc(2026, 7, 31, 8, 12),
        reason: '13:42 IST is 08:12 UTC',
      );
      expect(txn.at.isUtc, isFalse);
    });

    test('paise stay whole — never a double, anywhere', () {
      final txn = TxnOut.fromJson(txnPayload());

      expect(txn.amountPaise, isA<int>());
      expect(txn.amountPaise, 4250);
      expect(txn.amountPaise, isNot(isA<double>()));

      // And a fractional amount is a contract break, not something to round.
      expect(
        () => TxnOut.fromJson(txnPayload()..['amount_paise'] = 42.5),
        throwsA(
          isA<WireFormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('amount_paise'), contains('whole number')),
          ),
        ),
      );
    });

    test('a null optional stays null, and is not invented into a default', () {
      final txn = TxnOut.fromJson(txnPayload());

      expect(txn.note, isNull);
      expect(txn.toAccountId, isNull);
      expect(txn.goalId, isNull);
      expect(txn.recurringId, isNull);
    });

    test('a coaching card keeps its evidence and exact paise', () {
      final insight = CoachingInsight.fromJson({
        'id': '019810f0-0000-7000-8000-000000000099',
        'kind': 'merchant_surge',
        'title': 'Swiggy is above your usual pace',
        'message': 'You spent more than your same-date baseline.',
        'priority': 75,
        'current_paise': 120000,
        'baseline_paise': 30000,
        'difference_paise': 90000,
        'period_start': '2026-08-01',
        'period_end': '2026-08-13',
        'evidence': {
          'reason': 'same_elapsed_days_median',
          'merchant_name': 'Swiggy',
          'classification': 'discretionary',
          'transaction_ids': ['txn-1', 'txn-2'],
          'comparison_months': ['2026-07', '2026-06', '2026-05'],
          'count': 2,
          'budget_name': null,
        },
      });

      expect(insight.kind, CoachingKind.merchantSurge);
      expect(insight.currentPaise, 120000);
      expect(insight.evidence.classification, SpendingClass.discretionary);
      expect(insight.evidence.transactionIds, ['txn-1', 'txn-2']);
    });

    test('a merchant rule reads the owner classification', () {
      final rule = MerchantRule.fromJson({
        'id': '019810f0-0000-7000-8000-000000000098',
        'match_text': 'tea stall',
        'merchant_name': 'Corner tea',
        'classification': 'avoid',
        'active': true,
      });

      expect(rule.matchText, 'tea stall');
      expect(rule.classification, SpendingClass.avoid);
      expect(rule.active, isTrue);
    });

    test('an account with no anchor yet reads as unconfirmed, not stale', () {
      final account = AccountOut.fromJson({
        'id': '019810f0-0000-7000-8000-000000000001',
        'name': 'HDFC savings',
        'kind': 'bank',
        'balance_paise': 0,
        'as_of': null,
        'sort_order': 0,
        'archived': false,
        'created_at': '2026-07-31T04:00:00Z',
        'updated_at': '2026-07-31T04:00:00Z',
      });

      expect(account.kind, AccountKind.bank);
      expect(account.asOf, isNull);
      expect(account.balancePaise, 0);
    });

    test('days stay strings — a day is not an instant', () {
      final summary = TodaySummary.fromJson({
        'day': '2026-07-31',
        'spent_today_paise': 128000,
        'spent_yesterday_paise': 9900,
        'today_txns': [txnPayload()],
        'pinned': <Object>[],
        'upcoming': <Object>[],
        'committed_paise': 1499000,
        'sealed': false,
        'seal_streak_days': 4,
        'quiet_days': ['2026-07-27', '2026-07-28'],
        'window_start': '2026-07-01',
        'window_end': '2026-07-31',
        'window_spent_paise': 2340000,
        'window_elapsed_days': 31,
        'window_total_days': 31,
      });

      expect(summary.day, isA<String>());
      expect(summary.day, '2026-07-31');
      expect(summary.windowStart, '2026-07-01');
      expect(summary.quietDays, isA<List<String>>());
      expect(summary.quietDays, ['2026-07-27', '2026-07-28']);
      expect(summary.todayTxns.single.amountPaise, 4250);

      // Instants inside the same payload still become DateTimes.
      expect(summary.todayTxns.single.at, isA<DateTime>());
    });

    test('a day that is not a day is refused rather than reinterpreted', () {
      expect(
        () => SealOut.fromJson({
          'date': '2026-07-31T00:00:00Z',
          'sealed_at': '2026-07-31T18:30:00Z',
        }),
        throwsA(
          isA<WireFormatException>().having(
            (e) => e.message,
            'message',
            contains("'yyyy-MM-dd'"),
          ),
        ),
      );
    });

    test('a derived read model arrives whole', () {
      final view = BudgetView.fromJson({
        'budget': {
          'id': '019810f0-0000-7000-8000-0000000000b1',
          'name': 'Food',
          'category_id': '019810f0-0000-7000-8000-0000000000c1',
          'limit_paise': 800000,
          'period': 'month',
          'kind': 'all',
          'rollover': false,
          'archived': false,
          'created_at': '2026-07-01T00:00:00Z',
          'updated_at': '2026-07-01T00:00:00Z',
        },
        'category': {
          'id': '019810f0-0000-7000-8000-0000000000c1',
          'name': 'Food',
          'icon': 'bowl',
          'kind': 'expense',
          'sort_order': 1,
          'archived': false,
          'created_at': '2026-07-01T00:00:00Z',
          'updated_at': '2026-07-01T00:00:00Z',
        },
        'pace': {
          'limit_paise': 800000,
          'spent_paise': 512300,
          'remaining_paise': 287700,
          'upcoming_paise': 0,
          'projected_paise': 762000,
          'projected_overspend_paise': 0,
          'elapsed_days': 21,
          'total_days': 31,
          'fraction_elapsed': 0.6774193548387096,
          'fraction_spent': 0.640375,
          'status': 'on_pace',
        },
        'window_start': '2026-07-01',
        'window_end': '2026-07-31',
      });

      expect(view.budget.period, BudgetPeriod.month);
      expect(view.budget.kind, BudgetKind.all);
      expect(view.category?.kind, CategoryKind.expense);
      expect(view.pace.status, BudgetStatus.onPace);
      expect(view.pace.spentPaise, isA<int>());
      expect(view.pace.fractionSpent, closeTo(0.64, 0.001));
      expect(view.windowStart, '2026-07-01');
    });

    test('an overall budget keeps its null category', () {
      final view = BudgetView.fromJson({
        'budget': {
          'id': '019810f0-0000-7000-8000-0000000000b2',
          'name': 'Everything',
          'category_id': null,
          'limit_paise': 4000000,
          'period': 'fy',
          'kind': 'added',
          'rollover': true,
          'archived': false,
          'created_at': '2026-04-01T00:00:00Z',
          'updated_at': '2026-04-01T00:00:00Z',
        },
        'category': null,
        'pace': {
          'limit_paise': 4000000,
          'spent_paise': 0,
          'remaining_paise': 4000000,
          'upcoming_paise': 0,
          'projected_paise': 0,
          'projected_overspend_paise': 0,
          'elapsed_days': 0,
          'total_days': 365,
          'fraction_elapsed': 0,
          'fraction_spent': 0,
          'status': 'pending',
        },
        'window_start': null,
        'window_end': null,
      });

      expect(view.budget.categoryId, isNull);
      expect(view.category, isNull);
      expect(view.windowStart, isNull);
      expect(view.budget.period, BudgetPeriod.fy);
      // An int-shaped ratio still reads as a double.
      expect(view.pace.fractionElapsed, 0.0);
    });

    test('the month story stays quiet where it has no evidence', () {
      final story = MonthStoryOut.fromJson({
        'month': '2026-07',
        'label': 'July 2026',
        'spent_paise': 2340000,
        'income_paise': 5000000,
        'kept_paise': 2660000,
        'quiet_days': 6,
        'vs_last_month': {'spent_delta_paise': -120000, 'verdict': 'lighter'},
        'flows': [
          {'name': 'Salary', 'paise': 5000000, 'is_income': true},
          {'name': 'Food', 'paise': 812300, 'is_income': false},
        ],
        'top_category': {'name': 'Food', 'paise': 812300},
        'biggest_day': {'date': '2026-07-18', 'paise': 342000},
        'quietest_week': null,
        'budget_held': null,
        'goal_moved': null,
      });

      expect(story.label, 'July 2026');
      expect(story.quietestWeek, isNull);
      expect(story.budgetHeld, isNull);
      expect(story.goalMoved, isNull);
      expect(story.vsLastMonth.spentDeltaPaise, -120000);
      expect(story.flows.first.isIncome, isTrue);
      expect(story.biggestDay?.date, '2026-07-18');
    });

    test('a month of mood dots keeps its gaps', () {
      final month = JournalMonth.fromJson({
        'month': '2026-07',
        'entries': <Object>[],
        'mood_dots': [4, null, null, 2, 5],
        'pages_written': 3,
        'streak_days': 0,
        'mood_money': null,
      });

      expect(month.moodDots, [4, null, null, 2, 5]);
      expect(month.moodMoney, isNull);
    });

    test('the changes feed reads ordered upserts and tombstones', () {
      final changes = ChangesOut.fromJson({
        'server_time': '2026-07-31T18:30:00Z',
        'items': [
          {
            'sequence': 41,
            'resource': 'txns',
            'resource_id': '019810f0-4a3b-7c21-9d55-2b1c4e8f0011',
            'operation': 'delete',
          },
        ],
        'next_cursor': 41,
        'has_more': false,
      });

      expect(changes.items.single.resource, 'txns');
      expect(changes.items.single.operation, ChangeOperation.delete);
      expect(changes.nextCursor, 41);
      expect(changes.hasMore, isFalse);
      expect(changes.serverTime.toUtc(), DateTime.utc(2026, 7, 31, 18, 30));
    });
  });

  group('unknown enum values are refused', () {
    test('an unrecognised txn type throws instead of guessing', () {
      expect(
        () => TxnOut.fromJson(txnPayload()..['type'] = 'refund'),
        throwsA(
          isA<WireFormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('unknown txn type'),
              contains('refund'),
              contains('expense'),
            ),
          ),
        ),
      );
    });

    test('an unrecognised budget status does not silently read as on pace', () {
      expect(
        () => budgetStatusWire.fromWire('nearly_over'),
        throwsA(isA<WireFormatException>()),
      );
      expect(
        budgetStatusWire.fromWire('projected_over'),
        BudgetStatus.projectedOver,
      );
    });

    test('every enum on the wire maps both ways', () {
      for (final kind in AccountKind.values) {
        expect(accountKindWire.fromWire(accountKindWire.toWire(kind)), kind);
      }
      for (final repeat in EventRepeat.values) {
        expect(
          eventRepeatWire.fromWire(eventRepeatWire.toWire(repeat)),
          repeat,
        );
      }
      for (final range in NetWorthRange.values) {
        expect(
          netWorthRangeWire.fromWire(netWorthRangeWire.toWire(range)),
          range,
        );
      }
      expect(netWorthRangeWire.toWire(NetWorthRange.sixMonths), '6m');
      expect(
        recurringKindWire.toWire(RecurringKind.subscription),
        'subscription',
      );
      expect(goalKindWire.toWire(GoalKind.clear), 'clear');
    });
  });

  group('requests are shaped correctly', () {
    test('query parameters are named and serialised for the server', () async {
      final (client, seen) = fakeClient({
        'items': <Object>[],
        'next_cursor': null,
      });

      await TxnsApi(client).list(
        fromDay: '2026-07-01',
        toDay: '2026-07-31',
        type: TxnType.transfer,
        accountId: 'acc-1',
        limit: 50,
      );

      final url = seen.single.url;
      expect(url.path, '/v1/txns');
      expect(url.queryParameters, {
        'from_day': '2026-07-01',
        'to_day': '2026-07-31',
        'account_id': 'acc-1',
        'type': 'transfer',
        'limit': '50',
      });
      // The ones nobody asked for never reach the wire.
      expect(url.queryParameters.containsKey('category_id'), isFalse);
      expect(url.queryParameters.containsKey('cursor'), isFalse);
      expect(url.queryParameters.containsKey('q'), isFalse);
    });

    test(
      'booleans and defaults are spelled the way FastAPI reads them',
      () async {
        final (client, seen) = fakeClient(<Object>[]);

        await AccountsApi(client).list(includeArchived: true);
        await CategoriesApi(client).top();

        expect(seen[0].url.queryParameters, {'include_archived': 'true'});
        expect(seen[1].url.queryParameters, {'days': '90', 'limit': '5'});
      },
    );

    test(
      'the changes cursor and page size are whole query parameters',
      () async {
        final (client, seen) = fakeClient({
          'server_time': '2026-07-31T18:30:00Z',
          'items': <Object>[],
          'next_cursor': 120,
          'has_more': false,
        });

        await ChangesApi(client).after(120, limit: 50);

        expect(seen.single.url.queryParameters, {
          'after': '120',
          'limit': '50',
        });
      },
    );

    test('a write with both a body and a query keeps both', () async {
      final (client, seen) = fakeClient(<Object>[]);

      await BudgetsApi(
        client,
      ).rebalance(const RebalanceIn(['b1', 'b2']), month: '2026-07');

      final request = seen.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/budgets/rebalance');
      expect(request.url.queryParameters, {'month': '2026-07'});
      expect(jsonDecode(request.body), {
        'budget_ids': ['b1', 'b2'],
      });
    });

    test('a 204 answer is a completed call, not a parse failure', () async {
      final (client, seen) = fakeClient(null);

      await TxnsApi(client).delete('019810f0-4a3b-7c21-9d55-2b1c4e8f0011');

      expect(seen.single.method, 'DELETE');
      expect(
        seen.single.url.path,
        '/v1/txns/019810f0-4a3b-7c21-9d55-2b1c4e8f0011',
      );
    });

    test('the bearer token rides along', () async {
      final (client, seen) = fakeClient({'ok': true});

      expect(await SystemApi(client).ping(), isTrue);
      expect(seen.single.headers['authorization'], 'Bearer bbx_test');
    });

    test('the CSV export is handed over as a request, not decoded', () {
      final (client, _) = fakeClient(null);
      final api = ExportApi(client);

      expect(
        api.txnsCsvUri().toString(),
        'http://ledger.test/v1/export/txns.csv',
      );
      expect(api.headers['authorization'], 'Bearer bbx_test');
    });
  });

  group('request bodies say exactly what was meant', () {
    test('a PUT sends the whole shape, nulls and all', () {
      final body = TxnIn(
        amountPaise: 4250,
        type: TxnType.expense,
        title: 'Chai',
        at: DateTime.utc(2026, 7, 31, 8, 12),
        accountId: 'acc-1',
        categoryId: 'cat-1',
      ).toJson();

      expect(body, {
        'amount_paise': 4250,
        'type': 'expense',
        'title': 'Chai',
        'at': '2026-07-31T08:12:00.000Z',
        'account_id': 'acc-1',
        'category_id': 'cat-1',
        'to_account_id': null,
        'goal_id': null,
        'note': null,
      });
      expect(body['amount_paise'], isA<int>());
    });

    test('a PATCH only mentions what the caller touched', () {
      expect(const TxnPatch(title: 'Chai + vada pav').toJson(), {
        'title': 'Chai + vada pav',
      });
      expect(const TxnPatch().toJson(), isEmpty);
    });

    test('clearing a field is said out loud, not left to null', () {
      // Absent: the category is untouched.
      expect(
        const TxnPatch(amountPaise: 5000).toJson().containsKey('category_id'),
        isFalse,
      );
      // Present and null: the category is cleared.
      expect(const TxnPatch(categoryId: Opt(null)).toJson(), {
        'category_id': null,
      });
      expect(const TxnPatch(categoryId: Opt('cat-2')).toJson(), {
        'category_id': 'cat-2',
      });
      expect(const GoalPatch(targetDate: Opt(null)).toJson(), {
        'target_date': null,
      });
    });

    test('enum-carrying bodies go out in the wire spelling', () {
      expect(
        const RecurringIn(
          title: 'Netflix',
          amountPaise: 14900,
          kind: RecurringKind.subscription,
          accountId: 'acc-1',
          dayOfMonth: 12,
        ).toJson(),
        containsPair('kind', 'subscription'),
      );
      expect(const AccountPatch(kind: AccountKind.liability).toJson(), {
        'kind': 'liability',
      });
    });
  });

  group('the settings map is a flat map of strings', () {
    test('it reads back whole after a write', () async {
      final (client, seen) = fakeClient({
        'name': 'Krish',
        'currency': 'INR',
        'salary_day': '1',
      });

      final settings = await SettingsApi(client).set('salary_day', '1');

      expect(settings['currency'], 'INR');
      expect(settings['salary_day'], '1');
      expect(seen.single.method, 'PUT');
      expect(jsonDecode(seen.single.body), {'value': '1'});
    });

    test('a non-string value is refused rather than stringified', () {
      expect(
        () => wireStringMap({'salary_day': 1}),
        throwsA(isA<WireFormatException>()),
      );
    });
  });
}
