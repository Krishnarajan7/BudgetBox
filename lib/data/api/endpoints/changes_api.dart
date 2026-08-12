import '../api_client.dart';
import 'wire.dart';

enum ChangeOperation { upsert, delete }

/// One durable mutation from the server's append-only synchronization log.
class ChangeOut {
  const ChangeOut({
    required this.sequence,
    required this.resource,
    required this.resourceId,
    required this.operation,
  });

  final int sequence;
  final String resource;
  final String resourceId;
  final ChangeOperation operation;

  factory ChangeOut.fromJson(Map<String, dynamic> json) => ChangeOut(
    sequence: json.whole('sequence'),
    resource: json.text('resource'),
    resourceId: json.text('resource_id'),
    operation: switch (json.text('operation')) {
      'upsert' => ChangeOperation.upsert,
      'delete' => ChangeOperation.delete,
      final value => throw WireFormatException(
        'operation: unknown change operation "$value"',
      ),
    },
  );
}

class ChangesOut {
  const ChangesOut({
    required this.serverTime,
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final DateTime serverTime;
  final List<ChangeOut> items;
  final int nextCursor;
  final bool hasMore;

  factory ChangesOut.fromJson(Map<String, dynamic> json) => ChangesOut(
    serverTime: json.instant('server_time'),
    items: wireList(json['items'], ChangeOut.fromJson),
    nextCursor: json.whole('next_cursor'),
    hasMore: json.flag('has_more'),
  );
}

class ChangesApi {
  const ChangesApi(this._c);

  final BbxClient _c;

  Future<ChangesOut> after(int cursor, {int limit = 200}) async =>
      ChangesOut.fromJson(
        wireObject(
          await _c.get('/v1/changes', {'after': cursor, 'limit': limit}),
        ),
      );
}
