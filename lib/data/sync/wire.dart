import 'dart:convert';

import '../api/api_client.dart';
import '../db.dart';
import 'ids.dart';

typedef SyncChange = ({
  int sequence,
  String resource,
  String resourceId,
  bool deleted,
});

typedef SyncChangePage = ({
  DateTime serverTime,
  List<SyncChange> items,
  int nextCursor,
  bool hasMore,
});

/// **Every** network call the sync engine makes lives in this file, on
/// purpose. It talks to [BbxClient] in raw paths and maps rather than to the
/// typed endpoint layer growing under `lib/data/api/endpoints/`, so that the
/// day the typed layer is ready this is the only file that changes — the
/// outbox, the puller and the engine never learn a URL.
class SyncWire {
  SyncWire(this.client);

  final BbxClient client;

  /// `PUT /v1/{resource}/{uuid7}` — the whole write protocol. The id is
  /// minted on the phone, so the same request can be sent any number of times
  /// and mean the same thing.
  static String pathFor(String kind, String remoteId) => switch (kind) {
    SyncKinds.txn => '/v1/txns/$remoteId',
    SyncKinds.account => '/v1/accounts/$remoteId',
    SyncKinds.anchor => '/v1/accounts/$remoteId/anchors',
    SyncKinds.category => '/v1/categories/$remoteId',
    SyncKinds.budget => '/v1/budgets/$remoteId',
    SyncKinds.recurring => '/v1/recurring/$remoteId',
    SyncKinds.goal => '/v1/goals/$remoteId',
    SyncKinds.pinned => '/v1/pinned/$remoteId',
    SyncKinds.seal => '/v1/seals/$remoteId',
    SyncKinds.note => '/v1/notes/$remoteId',
    SyncKinds.journal => '/v1/journal/$remoteId',
    SyncKinds.focus => '/v1/focus/sessions/$remoteId',
    SyncKinds.event => '/v1/events/$remoteId',
    SyncKinds.vault => '/v1/vault/$remoteId',
    _ => throw BbxProblem(
      status: 400,
      slug: 'unknown-kind',
      detail: 'nothing upstream answers to "$kind"',
    ),
  };

  /// Sends one queued write. Throws [BbxOffline] (still owed) or
  /// [BbxProblem] (refused) — the outbox tells those two apart.
  Future<void> push(OutboxData row) async {
    final path = pathFor(row.kind, row.remoteId);
    final body = row.payload == null
        ? <String, dynamic>{}
        : (jsonDecode(row.payload!) as Map).cast<String, dynamic>();

    // An anchor is a reading, not a row: it is the one write the server takes
    // as a POST. Retrying it can leave a duplicate reading of the same
    // balance, which is harmless — the latest anchor wins either way.
    if (row.kind == SyncKinds.anchor) {
      await client.post(path, body);
      return;
    }

    switch (row.op) {
      case OutboxOp.put:
        await client.put(path, body);
      case OutboxOp.patch:
        await client.patch(path, body);
      case OutboxOp.delete:
        await client.delete(path);
    }
  }

  // ————— reads, for the puller —————

  /// One durable page of the server's append-only change log. Unlike an
  /// updated-at scan this includes deletion tombstones, and the cursor only
  /// moves through rows the phone has actually received.
  Future<SyncChangePage> changes(int after, {int limit = 200}) async {
    final body = await client.get('/v1/changes', {
      'after': after,
      'limit': limit,
    });
    final map = (body as Map).cast<String, dynamic>();
    final rawItems = (map['items'] as List?) ?? const [];
    return (
      serverTime: DateTime.parse('${map['server_time']}').toUtc(),
      items: [
        for (final raw in rawItems)
          (
            sequence: (raw as Map)['sequence'] as int,
            resource: '${raw['resource']}',
            resourceId: '${raw['resource_id']}',
            deleted: raw['operation'] == 'delete',
          ),
      ],
      nextCursor: map['next_cursor'] as int,
      hasMore: map['has_more'] == true,
    );
  }

  Future<List<Map<String, dynamic>>> list(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    final body = await client.get(path, query);
    if (body is! List) return const [];
    return [for (final r in body) (r as Map).cast<String, dynamic>()];
  }

  /// A single transaction. `/v1/txns` is a paged, day-filtered read, so the
  /// puller fetches the handful of ids `changes` named instead.
  Future<Map<String, dynamic>?> txn(String remoteId) async {
    final body = await client.get('/v1/txns/$remoteId');
    if (body is! Map) return null;
    return body.cast<String, dynamic>();
  }

  static String isoOf(DateTime at) => at.toUtc().toIso8601String();
}
