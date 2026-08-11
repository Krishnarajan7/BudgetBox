import '../../tables.dart';
import '../api_client.dart';
import 'txns_api.dart';
import 'wire.dart';

/// Undo, and the trail behind it. Every mutation of the ledger logs a snapshot
/// in the same database transaction, so an undo replays the inverse rather
/// than writing a correction.
class ActivitiesApi {
  const ActivitiesApi(this._c);

  final BbxClient _c;

  /// Newest first. Pass [txnId] to read one entry's own history.
  Future<List<ActivityOut>> recent({int limit = 20, String? txnId}) async =>
      wireList(
        await _c.get('/v1/activities', {'limit': limit, 'txn_id': txnId}),
        ActivityOut.fromJson,
      );

  /// Replays the inverse and consumes the row — the same activity cannot be
  /// undone twice.
  Future<UndoResult> undo(String activityId) async => UndoResult.fromJson(
        wireObject(await _c.post('/v1/activities/$activityId/undo')),
      );
}

class ActivityOut {
  const ActivityOut({
    required this.id,
    required this.txnId,
    required this.action,
    required this.at,
    required this.title,
    required this.amountPaise,
    required this.txnType,
    required this.undoable,
  });

  final String id;
  final String txnId;
  final ActivityAction action;
  final DateTime at;

  /// The snapshot's own words — null when the row carried none.
  final String? title;
  final int? amountPaise;
  final TxnType? txnType;

  /// False once the entry has moved on and the inverse would no longer be
  /// honest.
  final bool undoable;

  factory ActivityOut.fromJson(Map<String, dynamic> json) => ActivityOut(
        id: json.text('id'),
        txnId: json.text('txn_id'),
        action: json.enumAt('action', activityActionWire),
        at: json.instant('at'),
        title: json.textOrNull('title'),
        amountPaise: json.wholeOrNull('amount_paise'),
        txnType: json.enumOrNullAt('txn_type', txnTypeWire),
        undoable: json.flag('undoable'),
      );
}

/// What the undo actually did. [txn] is the restored or re-edited entry —
/// null when the undo was of a creation, which leaves nothing behind.
class UndoResult {
  const UndoResult({required this.action, required this.txn});

  /// The action that was reversed, not the one performed.
  final ActivityAction action;
  final TxnOut? txn;

  factory UndoResult.fromJson(Map<String, dynamic> json) => UndoResult(
        action: json.enumAt('action', activityActionWire),
        txn: json.objectOrNull('txn', TxnOut.fromJson),
      );
}
