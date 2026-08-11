import '../db.dart';
import 'ids.dart';

/// Turns a local Drift row into the exact body `backend/openapi.json` asks
/// for. The rules that never bend: money is integer paise, a calendar day is
/// 'yyyy-MM-dd', an instant is ISO-8601 in UTC, and an enum goes over the
/// wire as its name ('expense', 'bank', 'yearly' …) — which is why the Dart
/// enum members are spelled exactly like the server's.
///
/// Foreign keys are the interesting part: the phone stores `accountId = 3`
/// and the server wants a uuid7, so every reference goes through [RemoteRefs],
/// which mints the mapping and queues the referenced row if the server has
/// never heard of it. That is what keeps a txn from landing before its
/// account.
abstract interface class RemoteRefs {
  Future<String> remote(String kind, int localId);

  Future<String?> remoteOrNull(String kind, int? localId);
}

String isoInstant(DateTime at) => at.toUtc().toIso8601String();

Future<Map<String, dynamic>> txnBody(Txn r, RemoteRefs refs) async {
  return {
    'amount_paise': r.amountPaise,
    'type': r.type.name,
    'account_id': await refs.remote(SyncKinds.account, r.accountId),
    'to_account_id':
        await refs.remoteOrNull(SyncKinds.account, r.toAccountId),
    'category_id': await refs.remoteOrNull(SyncKinds.category, r.categoryId),
    'title': r.title,
    'note': r.note,
    'at': isoInstant(r.at),
    'goal_id': await refs.remoteOrNull(SyncKinds.goal, r.goalId),
    // TxnIn carries no recurring_id: upstream, a materialized charge is
    // stamped by the recurring job, not claimed by the client.
  };
}

/// AccountIn holds no balance — upstream, balances are *derived* from the
/// latest anchor plus signed txn deltas. A confirmed reading travels
/// separately, as [anchorBody].
Map<String, dynamic> accountBody(Account r) => {
      'name': r.name,
      'kind': r.kind.name,
      'sort_order': r.sortOrder,
    };

Map<String, dynamic> anchorBody(int balancePaise, DateTime at) => {
      'balance_paise': balancePaise,
      'at': isoInstant(at),
    };

Map<String, dynamic> categoryBody(Category r) => {
      'name': r.name,
      'icon': r.icon,
      'kind': r.kind.name,
      'sort_order': r.sortOrder,
    };

Future<Map<String, dynamic>> budgetBody(Budget r, RemoteRefs refs) async {
  return {
    'category_id': await refs.remoteOrNull(SyncKinds.category, r.categoryId),
    'name': r.name,
    'limit_paise': r.limitPaise,
    'period': r.period.name,
    'kind': r.kind.name,
    'rollover': r.rollover,
  };
}

Future<Map<String, dynamic>> recurringBody(
    Recurring r, RemoteRefs refs) async {
  return {
    'title': r.title,
    'amount_paise': r.amountPaise,
    'category_id': await refs.remoteOrNull(SyncKinds.category, r.categoryId),
    'account_id': await refs.remote(SyncKinds.account, r.accountId),
    'kind': r.kind.name,
    'every_months': r.everyMonths,
    'day_of_month': r.dayOfMonth,
    'next_due': r.nextDue,
    'active': r.active,
  };
}

Map<String, dynamic> goalBody(Goal r) => {
      'name': r.name,
      'target_paise': r.targetPaise,
      'kind': r.kind.name,
      'target_date': r.targetDate,
      'monthly_paise': r.monthlyPaise,
    };

Future<Map<String, dynamic>> pinnedBody(Pinned r, RemoteRefs refs) async {
  return {
    'title': r.title,
    'amount_paise': r.amountPaise,
    'category_id': await refs.remote(SyncKinds.category, r.categoryId),
    'account_id': await refs.remote(SyncKinds.account, r.accountId),
    'sort_order': r.sortOrder,
  };
}

Map<String, dynamic> noteBody(Note r) => {
      'title': r.title,
      'body': r.body,
      'pinned': r.pinned,
    };

Map<String, dynamic> journalBody(JournalEntry r) => {
      'body': r.body,
      'mood': r.mood,
    };

Map<String, dynamic> focusBody(FocusSession r) => {
      'started_at': isoInstant(r.startedAt),
      'minutes': r.minutes,
      'kind': r.kind.name,
      'completed': r.completed,
      'label': r.label,
    };

Map<String, dynamic> eventBody(Event r) => {
      'title': r.title,
      'note': r.note,
      'date': r.date,
      'time_minutes': r.timeMinutes,
      'repeat': r.repeat.name,
    };

Map<String, dynamic> vaultBody(VaultItem r) => {
      'nonce': r.nonce,
      'cipher': r.cipher,
    };
