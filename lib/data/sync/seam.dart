import '../db.dart';
import 'ids.dart';
import 'outbox.dart';

/// The one hook the repos know about.
///
/// Every mutating repo method calls [bbxSync] from *inside* its own Drift
/// transaction, so the local write and the queued intent commit together or
/// not at all — a crash between the two is not a state this app can reach.
///
/// It is deliberately a plain global rather than a constructor argument: the
/// screens are frozen and `providers.dart` is not mine to change, so repo
/// signatures must stay exactly as they are. Until [SyncEngine] installs a
/// live seam, this is [InertSeam] and the app behaves precisely as it did
/// before the server existed.
abstract interface class SyncSeam {
  Future<void> upsert(String kind, int localId);

  /// A partial edit, for facts the server only accepts on a PATCH — chiefly
  /// `archived`, which no PUT body carries.
  Future<void> patch(String kind, int localId, Map<String, dynamic> body);

  Future<void> remove(String kind, int localId);

  Future<void> anchor(int accountLocalId, int balancePaise, DateTime at);

  /// Day-keyed rows (the journal page, the day seal) reach the same queue
  /// through the day rather than a row number.
  Future<void> upsertDay(String kind, String day);

  Future<void> removeDay(String kind, String day);
}

/// What an unwired app does about syncing: nothing at all.
class InertSeam implements SyncSeam {
  const InertSeam();

  @override
  Future<void> upsert(String kind, int localId) async {}

  @override
  Future<void> patch(
      String kind, int localId, Map<String, dynamic> body) async {}

  @override
  Future<void> remove(String kind, int localId) async {}

  @override
  Future<void> anchor(int accountLocalId, int balancePaise, DateTime at) async {}

  @override
  Future<void> upsertDay(String kind, String day) async {}

  @override
  Future<void> removeDay(String kind, String day) async {}
}

/// The live seam: writes land in the outbox of one database.
class OutboxSeam implements SyncSeam {
  OutboxSeam(this.outbox);

  factory OutboxSeam.on(LedgerDb db) => OutboxSeam(SyncOutbox(db));

  final SyncOutbox outbox;

  @override
  Future<void> upsert(String kind, int localId) =>
      outbox.upsert(kind, localId);

  @override
  Future<void> patch(String kind, int localId, Map<String, dynamic> body) =>
      outbox.patch(kind, localId, body);

  @override
  Future<void> remove(String kind, int localId) =>
      outbox.remove(kind, localId);

  @override
  Future<void> anchor(int accountLocalId, int balancePaise, DateTime at) =>
      outbox.anchor(accountLocalId, balancePaise, at);

  @override
  Future<void> upsertDay(String kind, String day) =>
      outbox.upsert(kind, SyncIds.localIdForDay(day));

  @override
  Future<void> removeDay(String kind, String day) =>
      outbox.remove(kind, SyncIds.localIdForDay(day));
}

/// Inert until an engine installs itself.
SyncSeam bbxSync = const InertSeam();

void installSyncSeam(SyncSeam seam) => bbxSync = seam;

void uninstallSyncSeam() => bbxSync = const InertSeam();
