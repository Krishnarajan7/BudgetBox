import 'dart:convert';

import 'package:drift/drift.dart';

import '../api/api_client.dart';
import '../db.dart';
import 'ids.dart';
import 'payloads.dart';
import 'wire.dart';

/// Why a drain stopped.
enum DrainStop {
  /// Nothing left that is worth sending.
  done,

  /// The network went away mid-queue. Everything still owed is still queued.
  offline,

  /// The token is missing or wrong. Retrying every row would only burn
  /// attempts on writes that are perfectly fine, so the drain steps back.
  unauthorized,
}

class DrainOutcome {
  const DrainOutcome({required this.sent, required this.stop, this.detail});

  final int sent;
  final DrainStop stop;
  final String? detail;
}

/// The queue of writes owed to the server, and the thing that empties it.
///
/// Two failures, told apart on purpose:
///
/// * [BbxOffline] — the write is still owed. Draining stops where it stands,
///   the queue is left exactly as it was, and **no attempt is burned**: a
///   tunnel is not the write's fault.
/// * [BbxProblem] — the server understood and refused. The row records the
///   reason and burns an attempt, and after [maxAttempts] it is parked. A
///   poisoned write is stepped over, never allowed to dam the ones behind it.
class SyncOutbox implements RemoteRefs {
  SyncOutbox(this._db) : ids = SyncIds(_db);

  final LedgerDb _db;
  final SyncIds ids;

  /// Small on purpose. Four refusals of the same body is evidence, not bad
  /// luck, and the sync page would rather show it than spin on it.
  static const maxAttempts = 4;

  // ————— queueing —————

  /// Queues the current state of a local row as an idempotent PUT, minting
  /// its uuid7 if it has none. Call this **inside the same Drift transaction
  /// as the local write** so a crash between the two is impossible.
  Future<void> upsert(String kind, int localId) async {
    final remoteId = await ids.claim(kind, localId);
    final body = await _bodyFor(kind, localId);
    if (body == null) return; // the row is gone; nothing to say about it
    await _queue(
      kind: kind,
      localId: localId,
      remoteId: remoteId,
      op: OutboxOp.put,
      payload: body,
    );
  }

  /// Queues a partial edit. Some facts — `archived`, above all — exist only
  /// on the server's PATCH bodies, never on the full PUT, so retiring a row
  /// has to travel as its own small write.
  ///
  /// If the row has never been upstream, [remote] queues its PUT first, and
  /// because the queue drains in order the patch lands on a row that exists.
  Future<void> patch(
      String kind, int localId, Map<String, dynamic> body) async {
    final remoteId = await remote(kind, localId);
    await _queue(
      kind: kind,
      localId: localId,
      remoteId: remoteId,
      op: OutboxOp.patch,
      payload: body,
    );
  }

  /// Queues a DELETE. A row the server never acknowledged is simply
  /// forgotten — there is nothing upstream to delete, and asking would only
  /// earn a 404 that parks forever.
  Future<void> remove(String kind, int localId) async {
    final entry = await ids.entry(kind, localId);
    if (entry == null) return;

    await (_db.delete(_db.outbox)
          ..where((o) =>
              o.kind.equals(kind) &
              o.localId.equals(localId) &
              o.op.equalsValue(OutboxOp.delete).not()))
        .go();

    if (entry.syncedAt == null) {
      await ids.forget(kind, localId);
      return;
    }
    await _queue(
      kind: kind,
      localId: localId,
      remoteId: entry.remoteId,
      op: OutboxOp.delete,
      payload: null,
    );
  }

  /// A confirmed balance reading for an account. Coalesces like any other
  /// write, so ten corrections in a row cost one request.
  Future<void> anchor(int accountLocalId, int balancePaise, DateTime at) async {
    final accountRemote = await remote(SyncKinds.account, accountLocalId);
    await _queue(
      kind: SyncKinds.anchor,
      localId: accountLocalId,
      remoteId: accountRemote,
      op: OutboxOp.put,
      payload: anchorBody(balancePaise, at),
    );
  }

  /// The id a foreign key should carry over the wire. If the referenced row
  /// has never been upstream, it is queued *first* — so a transaction can
  /// never arrive before the account it names.
  @override
  Future<String> remote(String kind, int localId) async {
    final known = await ids.remoteFor(kind, localId);
    if (known != null) return known;
    await upsert(kind, localId);
    return await ids.remoteFor(kind, localId) ?? await ids.claim(kind, localId);
  }

  @override
  Future<String?> remoteOrNull(String kind, int? localId) =>
      localId == null ? Future.value() : remote(kind, localId);

  Future<void> _queue({
    required String kind,
    required int localId,
    required String remoteId,
    required OutboxOp op,
    required Map<String, dynamic>? payload,
  }) async {
    var encoded = payload == null ? null : jsonEncode(payload);
    final open = await (_db.select(_db.outbox)
          ..where((o) =>
              o.kind.equals(kind) &
              o.localId.equals(localId) &
              o.op.equalsValue(op))
          ..orderBy([(o) => OrderingTerm.desc(o.id)])
          ..limit(1))
        .getSingleOrNull();

    if (open != null) {
      // Two partial edits are not a replacement for each other: retiring a
      // budget and renaming it are both still owed, so patches merge.
      if (op == OutboxOp.patch && open.payload != null && payload != null) {
        final merged = (jsonDecode(open.payload!) as Map)
            .cast<String, dynamic>()
          ..addAll(payload);
        encoded = jsonEncode(merged);
      }
      // Coalesce: the newest payload replaces the pending one, and the row
      // keeps its place in the queue so dependencies still drain in order.
      // A parked row gets its attempts back — the data changed, so the
      // server's last refusal is no longer about this body.
      await (_db.update(_db.outbox)..where((o) => o.id.equals(open.id))).write(
        OutboxCompanion(
          payload: Value(encoded),
          attempts: const Value(0),
          lastError: const Value(null),
        ),
      );
      return;
    }

    await _db.into(_db.outbox).insert(
          OutboxCompanion.insert(
            kind: kind,
            localId: localId,
            remoteId: remoteId,
            op: op,
            payload: Value(encoded),
          ),
        );
  }

  // ————— counts, for the status line —————

  Future<int> pendingCount() => _countWhere(
      (o) => o.attempts.isSmallerThanValue(maxAttempts));

  Future<int> parkedCount() => _countWhere(
      (o) => o.attempts.isBiggerOrEqualValue(maxAttempts));

  Future<int> totalCount() => _countWhere((o) => const Constant(true));

  Future<int> _countWhere(Expression<bool> Function($OutboxTable) filter) async {
    final count = _db.outbox.id.count();
    final row = await (_db.selectOnly(_db.outbox)
          ..addColumns([count])
          ..where(filter(_db.outbox)))
        .getSingle();
    return row.read(count) ?? 0;
  }

  /// Does the phone still owe the server something about this row? The
  /// puller asks before it applies anything.
  Future<bool> owes(String kind, int localId) async {
    final row = await (_db.select(_db.outbox)
          ..where((o) => o.kind.equals(kind) & o.localId.equals(localId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  // ————— draining —————

  Future<DrainOutcome> drain(SyncWire wire) async {
    final stepped = <int>{};
    var sent = 0;

    while (true) {
      final query = _db.select(_db.outbox)
        ..where((o) => o.attempts.isSmallerThanValue(maxAttempts))
        ..orderBy([
          (o) => OrderingTerm.asc(o.queuedAt),
          (o) => OrderingTerm.asc(o.id),
        ])
        ..limit(1);
      if (stepped.isNotEmpty) {
        query.where((o) => o.id.isNotIn(stepped.toList()));
      }
      final row = await query.getSingleOrNull();
      if (row == null) {
        return DrainOutcome(sent: sent, stop: DrainStop.done);
      }

      try {
        await wire.push(row);
      } on BbxOffline catch (e) {
        return DrainOutcome(
          sent: sent,
          stop: DrainStop.offline,
          detail: e.detail,
        );
      } on BbxProblem catch (e) {
        if (e.isAuth) {
          await _note(row, e.toString(), burn: false);
          return DrainOutcome(
            sent: sent,
            stop: DrainStop.unauthorized,
            detail: e.detail,
          );
        }
        await _note(row, e.toString(), burn: true);
        stepped.add(row.id);
        continue;
      }

      await _db.transaction(() async {
        await (_db.delete(_db.outbox)..where((o) => o.id.equals(row.id))).go();
        if (row.kind == SyncKinds.anchor) return;
        if (row.op == OutboxOp.delete) {
          await ids.forget(row.kind, row.localId);
        } else {
          await ids.stamp(row.kind, row.localId, DateTime.now());
        }
      });
      sent++;
    }
  }

  Future<void> _note(OutboxData row, String why, {required bool burn}) {
    return (_db.update(_db.outbox)..where((o) => o.id.equals(row.id))).write(
      OutboxCompanion(
        attempts: Value(burn ? row.attempts + 1 : row.attempts),
        lastError: Value(why),
      ),
    );
  }

  // ————— row → body —————

  /// Null means the local row is gone, so there is nothing to send.
  Future<Map<String, dynamic>?> _bodyFor(String kind, int localId) async {
    switch (kind) {
      case SyncKinds.txn:
        final r = await _one(_db.txns, (t) => t.id.equals(localId));
        return r == null ? null : await txnBody(r, this);
      case SyncKinds.account:
        final r = await _one(_db.accounts, (t) => t.id.equals(localId));
        return r == null ? null : accountBody(r);
      case SyncKinds.category:
        final r = await _one(_db.categories, (t) => t.id.equals(localId));
        return r == null ? null : categoryBody(r);
      case SyncKinds.budget:
        final r = await _one(_db.budgets, (t) => t.id.equals(localId));
        return r == null ? null : await budgetBody(r, this);
      case SyncKinds.recurring:
        final r = await _one(_db.recurrings, (t) => t.id.equals(localId));
        return r == null ? null : await recurringBody(r, this);
      case SyncKinds.goal:
        final r = await _one(_db.goals, (t) => t.id.equals(localId));
        return r == null ? null : goalBody(r);
      case SyncKinds.pinned:
        final r = await _one(_db.pinneds, (t) => t.id.equals(localId));
        return r == null ? null : await pinnedBody(r, this);
      case SyncKinds.note:
        final r = await _one(_db.notes, (t) => t.id.equals(localId));
        return r == null ? null : noteBody(r);
      case SyncKinds.focus:
        final r = await _one(_db.focusSessions, (t) => t.id.equals(localId));
        return r == null ? null : focusBody(r);
      case SyncKinds.event:
        final r = await _one(_db.events, (t) => t.id.equals(localId));
        return r == null ? null : eventBody(r);
      case SyncKinds.vault:
        final r = await _one(_db.vaultItems, (t) => t.id.equals(localId));
        return r == null ? null : vaultBody(r);
      case SyncKinds.journal:
        final day = SyncIds.dayForLocalId(localId);
        final r = await _one(_db.journalEntries, (t) => t.date.equals(day));
        return r == null ? null : journalBody(r);
      case SyncKinds.seal:
        // Sealing a day carries no body: the day in the path is the whole
        // fact. An empty map still proves the row is there to be sent.
        final day = SyncIds.dayForLocalId(localId);
        final r = await _one(_db.daySeals, (t) => t.date.equals(day));
        return r == null ? null : const <String, dynamic>{};
      default:
        return null;
    }
  }

  Future<D?> _one<T extends HasResultSet, D>(
    ResultSetImplementation<T, D> table,
    Expression<bool> Function(T) filter,
  ) {
    return (_db.select(table)..where(filter)).getSingleOrNull();
  }
}
